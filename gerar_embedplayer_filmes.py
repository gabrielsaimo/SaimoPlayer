#!/usr/bin/env python3
"""Gera fontes HLS do Embedplayer para todos os filmes do catálogo Saimo.

O catálogo VOD não guarda IMDb, mas cada fonte Xtream possui um stream_id. Este
programa nunca tenta identificar um filme pelo nome. A cadeia é sempre:

    stream_id da fonte -> tmdb_id informado pela fonte -> imdb_id -> master.txt

Assim, refilmagens e títulos parecidos não podem ser misturados. O programa:

1. lê ``vod/filmes-[A-Z#].txt``;
2. consulta o código interno no servidor que forneceu a própria fonte;
3. converte o TMDB ID exato em IMDb ID;
4. resolve a página ``api.embedplayer.site/tt...`` até o ``master.txt``;
5. valida se a resposta final é realmente uma playlist HLS;
6. grava uma lista compacta para os apps, uma M3U e relatórios;
7. opcionalmente acrescenta a nova fonte como principal nas fatias ``vod``.

O cache SQLite permite interromper e continuar sem repetir trabalho. Nenhuma IA
é usada. Execute ``python3 gerar_embedplayer_filmes.py --help`` para as opções.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import contextlib
import csv
import fcntl
import html
import http.cookiejar
import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


ROOT = Path(__file__).resolve().parent
VOD_DIR = ROOT / "vod"
DEFAULT_OUTPUT = ROOT / "arquivos-gerados" / "embedplayer-filmes"
TMDB_BASE = "https://api.themoviedb.org/3"
EMBED_API = "https://api.embedplayer.site"
USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0 Safari/537.36"
)
YEAR_AT_END = re.compile(r"\s*\(((?:19|20)\d{2})\)\s*$")
IMDB_ID = re.compile(r"^tt\d{7,10}$")
PLAYER_ID = re.compile(
    r'class=["\'][^"\']*player_select_item[^"\']*["\'][^>]*\bidS=["\']([^"\']+)',
    re.I,
)
PLAYER_ID_REVERSED = re.compile(
    r'\bidS=["\']([^"\']+)["\'][^>]*class=["\'][^"\']*player_select_item',
    re.I,
)
STREAM_TOKEN_RE = re.compile(r"(?<![A-Fa-f0-9])([A-Fa-f0-9]{128})(?![A-Fa-f0-9])")
PLAYER_URL_RE = re.compile(
    r"(?i)https?://(?:www\.)?embedplayer\d*\.xyz/video/[A-Za-z0-9_-]{8,64}"
)
STRONG_STREAM_TOKEN_PATTERNS = (
    re.compile(
        r"(?is)\b(?:idS|stream[_-]?id|streamId|data[-_:](?:id|stream|ids))\b"
        r"[^A-Fa-f0-9]{0,180}([A-Fa-f0-9]{128})"
    ),
    re.compile(r'''(?is)\b(?:run|play|load)\s*\(\s*["']([A-Fa-f0-9]{128})["']'''),
)
STREAM_CONTEXT_MARKERS = (
    "ids", "stream", "server", "servidor", "assistir", "player", "gstream", "run(", "play("
)
MAX_STREAM_TOKENS = 8
MAX_PLAYER_CANDIDATES = 8
MAX_EMBED_SOURCES = 6
TITLE_TAG = re.compile(r"<title>(.*?)</title>", re.I | re.S)
PRINT_LOCK = threading.Lock()
CACHE_LOCK = threading.Lock()
PROVIDER_ID_CACHE: dict[tuple[str, str], str] = {}
TMDB_IMDB_CACHE: dict[str, str] = {}
EMBED_RESULT_CACHE: dict[str, tuple[tuple["EmbedSource", ...], str]] = {}
EXACT_ID_HINTS: dict[str, tuple[str, str]] = {}
KEY_LOCKS: dict[tuple[str, str], threading.Lock] = {}


def key_lock(namespace: str, key: str) -> threading.Lock:
    with CACHE_LOCK:
        return KEY_LOCKS.setdefault((namespace, key), threading.Lock())


@dataclass(frozen=True)
class Movie:
    title: str
    name: str
    year: str
    file: Path
    sources: tuple[tuple[int, str], ...]


@dataclass(frozen=True)
class Provider:
    index: int
    api: str
    username: str
    password: str


@dataclass(frozen=True)
class EmbedSource:
    url: str
    language: str = "dub"
    label: str = "Dublado"


@dataclass
class Result:
    title: str
    status: str
    imdb: str = ""
    tmdb_id: str = ""
    url: str = ""
    api_title: str = ""
    error: str = ""
    sources: tuple[EmbedSource, ...] = ()


def split_title_year(title: str) -> tuple[str, str]:
    match = YEAR_AT_END.search(title)
    if not match:
        return title.strip(), ""
    return title[: match.start()].strip(), match.group(1)


def catalog_movies(selected_titles: set[str] | None = None) -> list[Movie]:
    movies: list[Movie] = []
    seen: set[str] = set()
    valid_names = {f"filmes-{letter}.txt" for letter in "#ABCDEFGHIJKLMNOPQRSTUVWXYZ"}
    for file in sorted(VOD_DIR.glob("filmes-*.txt")):
        if file.name not in valid_names:
            continue
        for raw in file.read_text(encoding="utf-8").splitlines():
            title = raw.split("\t", 1)[0].strip()
            if not title or title in seen:
                continue
            if selected_titles and title not in selected_titles:
                continue
            seen.add(title)
            name, year = split_title_year(title)
            sources: list[tuple[int, str]] = []
            for field in raw.split("\t")[1:]:
                if "=" not in field:
                    continue
                for source in field.split("=", 1)[1].split(","):
                    match = re.fullmatch(r"(\d+):(.+)", source.strip())
                    if match:
                        pair = (int(match.group(1)), match.group(2))
                        if pair not in sources:
                            sources.append(pair)
            movies.append(
                Movie(title=title, name=name, year=year, file=file, sources=tuple(sources))
            )
    return movies


def catalog_embed_sources() -> dict[str, tuple[EmbedSource, ...]]:
    """Recupera fontes já publicadas; uma oscilação nunca pode apagá-las."""
    recovered: dict[str, tuple[EmbedSource, ...]] = {}
    valid_names = {f"filmes-{letter}.txt" for letter in "#ABCDEFGHIJKLMNOPQRSTUVWXYZ"}
    for file in sorted(VOD_DIR.glob("filmes-*.txt")):
        if file.name not in valid_names:
            continue
        for raw in file.read_text(encoding="utf-8").splitlines():
            fields = raw.split("\t")
            if not fields or not fields[0]:
                continue
            found: list[EmbedSource] = []
            seen: set[str] = set()
            for field in fields[1:]:
                if "=" not in field:
                    continue
                language, values = field.split("=", 1)
                language = "leg" if language == "leg" else "dub"
                label = "Legendado" if language == "leg" else "Dublado"
                for value in values.split(","):
                    value = value.strip()
                    parsed = urllib.parse.urlsplit(value)
                    if (
                        value in seen
                        or parsed.scheme != "https"
                        or not re.fullmatch(r"(?:www\.)?embedplayer\d*\.xyz", parsed.hostname or "", re.I)
                        or not parsed.path.endswith("/master.txt")
                    ):
                        continue
                    seen.add(value)
                    found.append(EmbedSource(value, language, label))
            if found:
                recovered[fields[0]] = tuple(found)
    return recovered


def catalog_providers() -> dict[int, Provider]:
    """Lê host e credenciais já publicados em vod/indice.txt."""
    providers: dict[int, Provider] = {}
    pattern = re.compile(r"^base:\s*(\d+)\s+(https?://[^/]+)/(?:movie|series)/([^/]+)/([^/]+)/")
    for raw in (VOD_DIR / "indice.txt").read_text(encoding="utf-8").splitlines():
        match = pattern.match(raw.strip())
        if not match:
            continue
        index = int(match.group(1))
        providers[index] = Provider(
            index=index,
            api=f"{match.group(2)}/player_api.php",
            username=match.group(3),
            password=match.group(4),
        )
    return providers


def discover_tmdb_key(explicit: str) -> str:
    if explicit:
        return explicit
    if os.environ.get("TMDB_API_KEY"):
        return os.environ["TMDB_API_KEY"]
    # O projeto irmão já usa a chave para enriquecer o mesmo catálogo. Ler de
    # lá evita duplicar credencial neste repositório e mantém a execução local
    # automática no workspace atual.
    # A cópia do agendamento (fora do workspace, sem os projetos irmãos ao
    # lado) guarda a chave aqui, num arquivo que o git ignora.
    with contextlib.suppress(OSError):
        guardada = (ROOT / "arquivos-gerados" / "tmdb-chave.txt").read_text(encoding="utf-8").strip()
        if guardada:
            return guardada
    candidates = [
        ROOT.parent / "Saimo-TV" / "scripts" / "fix-enriched-data.cjs",
        ROOT.parent / "Saimo-Cell-V2" / "services" / "tmdbService.ts",
    ]
    pattern = re.compile(r"TMDB_API_KEY\s*=\s*['\"]([^'\"]+)['\"]")
    for file in candidates:
        with contextlib.suppress(OSError):
            match = pattern.search(file.read_text(encoding="utf-8"))
            if match:
                return match.group(1)
    raise SystemExit(
        "TMDB_API_KEY não encontrado. Informe --tmdb-key ou defina TMDB_API_KEY."
    )


def request(
    opener: urllib.request.OpenerDirector,
    url: str,
    *,
    data: bytes | None = None,
    headers: dict[str, str] | None = None,
    timeout: float = 30,
) -> tuple[bytes, str]:
    final_headers = {"User-Agent": USER_AGENT, "Accept-Language": "pt-BR,pt;q=0.9"}
    if headers:
        final_headers.update(headers)
    req = urllib.request.Request(url, data=data, headers=final_headers)
    with opener.open(req, timeout=timeout) as response:
        return response.read(), response.geturl()


def tmdb_json(path: str, params: dict[str, str], key: str) -> dict:
    query = urllib.parse.urlencode({**params, "api_key": key})
    opener = urllib.request.build_opener()
    body, _ = request(opener, f"{TMDB_BASE}{path}?{query}")
    return json.loads(body)


def provider_tmdb_ids(movie: Movie, providers: dict[int, Provider]) -> set[str]:
    """Obtém IDs diretamente dos stream_ids, nunca do título do filme."""
    ids: set[str] = set()
    successful_response = False
    failures: list[str] = []
    # As bases 6 e 2 estão acessíveis e cobrem quase todo o catálogo. Outras
    # entram depois, para não esperar DNS de uma reserva quando a principal já
    # forneceu o mesmo identificador.
    ordered = sorted(movie.sources, key=lambda pair: ({6: 0, 2: 1}.get(pair[0], 2), pair))
    seen_streams: set[tuple[int, str]] = set()
    for base_index, remainder in ordered:
        # Reservas antigas (principalmente base 8/9) estão sem DNS. Se uma das
        # origens acessíveis já identificou o item, não há por que atrasar cada
        # filme esperando essas reservas. Quando forem a única fonte, ainda são
        # consultadas e o caso fica registrado no relatório.
        if ids and base_index not in {2, 6}:
            continue
        provider = providers.get(base_index)
        stream_match = re.match(r"(\d+)", remainder)
        if not provider or not stream_match or "desativado.invalid" in provider.api:
            continue
        stream_id = stream_match.group(1)
        identity = (base_index, stream_id)
        if identity in seen_streams:
            continue
        seen_streams.add(identity)
        provider_cache_key = (provider.api, stream_id)
        with CACHE_LOCK:
            cached_provider_id = PROVIDER_ID_CACHE.get(provider_cache_key)
        if cached_provider_id is not None:
            successful_response = True
            if cached_provider_id:
                ids.add(cached_provider_id)
            if len(ids) > 1:
                return ids
            continue
        params = urllib.parse.urlencode(
            {
                "username": provider.username,
                "password": provider.password,
                "action": "get_vod_info",
                "vod_id": stream_id,
            }
        )
        try:
            body, _ = request(
                urllib.request.build_opener(),
                f"{provider.api}?{params}",
                headers={"Accept": "application/json"},
                timeout=20,
            )
            payload = json.loads(body)
            successful_response = True
        except Exception as error:
            failures.append(f"base {base_index}/{stream_id}: {type(error).__name__}")
            continue
        info = payload.get("info") or {}
        movie_data = payload.get("movie_data") or {}
        raw_id = info.get("tmdb_id") or movie_data.get("tmdb_id")
        if not raw_id:
            tmdb_url = str(info.get("kinopoisk_url") or "")
            match = re.search(r"themoviedb\.org/movie/(\d+)", tmdb_url)
            raw_id = match.group(1) if match else ""
        if str(raw_id).isdigit():
            exact_id = str(raw_id)
            ids.add(exact_id)
        else:
            exact_id = ""
        with CACHE_LOCK:
            PROVIDER_ID_CACHE[provider_cache_key] = exact_id
        # Duas fontes do próprio item discordaram. Não há motivo para continuar
        # consultando: o registro precisa ir ao relatório de conflito.
        if len(ids) > 1:
            return ids
    if not ids and failures and not successful_response:
        raise RuntimeError("fontes de metadados inacessíveis: " + ", ".join(failures[:3]))
    return ids


def tmdb_imdb_id(tmdb_id: str, key: str) -> str:
    with CACHE_LOCK:
        cached = TMDB_IMDB_CACHE.get(tmdb_id)
    if cached is not None:
        return cached
    # Títulos duplicados ficam próximos no catálogo e chegam juntos nas
    # threads. Somente a primeira consulta a rede; as demais aguardam e usam o
    # resultado compartilhado.
    with key_lock("tmdb", tmdb_id):
        with CACHE_LOCK:
            cached = TMDB_IMDB_CACHE.get(tmdb_id)
        if cached is not None:
            return cached
        external = tmdb_json(f"/movie/{tmdb_id}/external_ids", {}, key)
        imdb = str(external.get("imdb_id") or "")
        result = imdb if IMDB_ID.fullmatch(imdb) else ""
        with CACHE_LOCK:
            TMDB_IMDB_CACHE[tmdb_id] = result
        return result


def audio_from_context(source: str, position: int, public_url: str) -> tuple[str, str]:
    """Infere o idioma perto do botão/token sem transformar palpite em ID."""
    if "/dub" in public_url.lower():
        return "dub", "Dublado"
    start = max(0, position - 1800)
    end = min(len(source), position + 450)
    context = source[start:end].lower()
    relative = position - start
    candidates: list[tuple[int, str, str]] = []
    for language, label, words in (
        ("dub", "Dublado", ("dublado", "dub")),
        ("leg", "Legendado", ("legendado", "leg")),
    ):
        best: int | None = None
        for word in words:
            offset = 0
            while True:
                found = context.find(word, offset)
                if found < 0:
                    break
                score = abs(found - relative) + (0 if found <= relative else 300)
                best = score if best is None else min(best, score)
                offset = found + len(word)
        if best is not None:
            candidates.append((best, language, label))
    if candidates:
        _, language, label = min(candidates)
        return language, label
    return "dub", "Dublado"


def extract_stream_tokens(page: str, public_url: str) -> list[tuple[str, str, str]]:
    """Retorna todos os idS em ordem, junto do idioma inferido para a UI."""
    text = html.unescape(page).replace("\\/", "/")
    rows: list[tuple[int, int, str, str, str]] = []
    seen: set[str] = set()

    def add(token: str, position: int, strength: int) -> None:
        if not STREAM_TOKEN_RE.fullmatch(token) or token in seen:
            return
        seen.add(token)
        language, label = audio_from_context(text, position, public_url)
        rows.append((strength, position, token, language, label))

    for pattern in STRONG_STREAM_TOKEN_PATTERNS:
        for match in pattern.finditer(text):
            add(match.group(1), match.start(1), 0)
    generic = list(STREAM_TOKEN_RE.finditer(text))
    for match in generic:
        vicinity = text[max(0, match.start() - 900):min(len(text), match.end() + 450)].lower()
        if any(marker in vicinity for marker in STREAM_CONTEXT_MARKERS):
            add(match.group(1), match.start(1), 1)
    if any(marker in text.lower() for marker in STREAM_CONTEXT_MARKERS):
        for match in generic:
            add(match.group(1), match.start(1), 2)
    rows.sort(key=lambda item: (item[0], item[1]))
    return [(token, language, label) for _, _, token, language, label in rows[:MAX_STREAM_TOKENS]]


def language_from_payload(item: dict, fallback: tuple[str, str]) -> tuple[str, str]:
    description = " ".join(
        str(item.get(key) or "") for key in ("name", "title", "label", "description", "language")
    ).lower()
    if "legendado" in description or re.search(r"(^|\W)leg(\W|$)", description):
        return "leg", "Legendado"
    if "dublado" in description or re.search(r"(^|\W)dub(\W|$)", description):
        return "dub", "Dublado"
    return fallback


def player_candidates(page: str, api_page: str, opener) -> list[tuple[str, str, str]]:
    """Resolve todos os tokens e preserva cada servidor/idioma encontrado."""
    candidates: list[tuple[str, str, str]] = []
    seen: set[str] = set()
    for token, language, label in extract_stream_tokens(page, api_page):
        stream_data = urllib.parse.urlencode({"idS": token}).encode()
        try:
            stream_body, _ = request(
                opener,
                f"{EMBED_API}/stream",
                data=stream_data,
                headers={
                    "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
                    "Origin": EMBED_API,
                    "Referer": api_page,
                    "X-Requested-With": "XMLHttpRequest",
                },
            )
            payload = json.loads(stream_body)
        except Exception:
            continue
        sources = (payload.get("resources") or {}).get("sources") or []
        if isinstance(sources, dict):
            sources = [sources]
        for item in sources:
            if not isinstance(item, dict):
                continue
            iframe = html.unescape(str(item.get("file") or "")).replace("\\/", "/")
            parsed = urllib.parse.urlparse(iframe)
            if (
                parsed.scheme != "https"
                or not re.fullmatch(r"(?:www\.)?embedplayer\d*\.xyz", parsed.hostname or "", re.I)
                or not re.fullmatch(r"/video/[A-Za-z0-9_-]{8,64}/?", parsed.path)
                or iframe in seen
            ):
                continue
            seen.add(iframe)
            item_language, item_label = language_from_payload(item, (language, label))
            candidates.append((iframe, item_language, item_label))
            if len(candidates) >= MAX_PLAYER_CANDIDATES:
                return candidates

    # Compatibilidade caso o provedor volte a publicar iframes no HTML.
    normalized = html.unescape(page).replace("\\/", "/")
    for match in PLAYER_URL_RE.finditer(normalized):
        iframe = match.group(0)
        if iframe in seen:
            continue
        seen.add(iframe)
        language, label = audio_from_context(normalized, match.start(), api_page)
        candidates.append((iframe, language, label))
        if len(candidates) >= MAX_PLAYER_CANDIDATES:
            break
    return candidates


def normalize_player_source(value: str) -> str:
    source = html.unescape(str(value or "")).replace("\\/", "/")
    parts = urllib.parse.urlsplit(source)
    if parts.scheme != "https" or not re.fullmatch(
        r"(?:www\.)?embedplayer\d*\.xyz", parts.hostname or "", re.I
    ):
        return ""
    if parts.path.endswith("/master.m3u8"):
        return urllib.parse.urlunsplit(
            (parts.scheme, parts.netloc, parts.path[:-len("master.m3u8")] + "master.txt", "", "")
        )
    if parts.path.endswith("/master.txt"):
        return urllib.parse.urlunsplit((parts.scheme, parts.netloc, parts.path, parts.query, ""))
    return ""


def validate_hls(source: str, iframe: str) -> bool:
    curl = shutil.which("curl")
    if not curl:
        raise RuntimeError("curl não encontrado para validar o HLS por HTTP/2")
    checked = subprocess.run(
        [
            curl, "-sS", "-L", "--compressed", "--max-time", "20", "--range", "0-4095",
            "-H", f"Referer: {iframe}", "--write-out", "\n__HTTP_STATUS__:%{http_code}", source,
        ],
        check=False,
        capture_output=True,
        timeout=25,
    )
    if checked.returncode != 0:
        raise RuntimeError(f"falha ao validar master.txt (curl {checked.returncode})")
    marker = b"\n__HTTP_STATUS__:"
    body, separator, raw_status = checked.stdout.rpartition(marker)
    return bool(
        separator and raw_status.strip().isdigit()
        and 200 <= int(raw_status.strip()) < 300 and b"#EXTM3U" in body[:4096]
    )


def resolve_embed_page(api_page: str, validate: bool) -> tuple[tuple[EmbedSource, ...], str]:
    api_jar = http.cookiejar.CookieJar()
    api_opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(api_jar))
    page_body, _ = request(api_opener, api_page)
    page = page_body.decode("utf-8", "replace")
    page_title_match = TITLE_TAG.search(page)
    api_title = html.unescape(page_title_match.group(1)).strip() if page_title_match else ""
    resolved: list[EmbedSource] = []
    seen_sources: set[str] = set()
    for iframe, language, label in player_candidates(page, api_page, api_opener):
        iframe_parts = urllib.parse.urlparse(iframe)
        player_origin = f"{iframe_parts.scheme}://{iframe_parts.netloc}"
        video_hash = iframe_parts.path.rstrip("/").rsplit("/", 1)[-1]
        player_data = urllib.parse.urlencode({"hash": video_hash, "r": api_page}).encode()
        try:
            player_body, _ = request(
                urllib.request.build_opener(),
                f"{player_origin}/player/index.php?data={video_hash}&do=getVideo",
                data=player_data,
                headers={
                    "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
                    "Origin": player_origin,
                    "Referer": iframe,
                    "X-Requested-With": "XMLHttpRequest",
                },
            )
            player = json.loads(player_body)
        except Exception:
            continue
        for raw_source in (player.get("videoSource"), player.get("securedLink")):
            source = normalize_player_source(str(raw_source or ""))
            if not source or source in seen_sources:
                continue
            if validate and not validate_hls(source, iframe):
                continue
            seen_sources.add(source)
            resolved.append(EmbedSource(source, language, label))
            if len(resolved) >= MAX_EMBED_SOURCES:
                return tuple(resolved), api_title
    return tuple(resolved), api_title


def resolve_embed_uncached(imdb: str, validate: bool) -> tuple[tuple[EmbedSource, ...], str]:
    return resolve_embed_page(f"{EMBED_API}/{imdb}/", validate)


def resolve_embed(imdb: str, validate: bool) -> tuple[tuple[EmbedSource, ...], str]:
    with CACHE_LOCK:
        cached = EMBED_RESULT_CACHE.get(imdb)
    if cached is not None:
        return cached
    with key_lock("embed", imdb):
        with CACHE_LOCK:
            cached = EMBED_RESULT_CACHE.get(imdb)
        if cached is not None:
            return cached
        result = resolve_embed_uncached(imdb, validate)
        with CACHE_LOCK:
            EMBED_RESULT_CACHE[imdb] = result
        return result


def process_movie_once(
    movie: Movie,
    providers: dict[int, Provider],
    tmdb_key: str,
    validate: bool,
    delay: float,
) -> Result:
    tmdb_id = ""
    imdb = ""
    api_title = ""
    try:
        cached_ids = EXACT_ID_HINTS.get(movie.title)
        if cached_ids and cached_ids[0] and cached_ids[1]:
            tmdb_id, imdb = cached_ids
        else:
            exact_ids = provider_tmdb_ids(movie, providers)
            if len(exact_ids) > 1:
                return Result(
                    movie.title,
                    "conflito_id",
                    error="TMDB IDs das fontes: " + ",".join(sorted(exact_ids)),
                )
            if not exact_ids:
                return Result(movie.title, "sem_codigo_origem")
            tmdb_id = next(iter(exact_ids))
            imdb = tmdb_imdb_id(tmdb_id, tmdb_key)
        if not imdb:
            return Result(movie.title, "sem_imdb", tmdb_id=tmdb_id)
        if delay:
            time.sleep(delay)
        sources, api_title = resolve_embed(imdb, validate)
        if not sources:
            return Result(movie.title, "indisponivel", imdb, tmdb_id, api_title=api_title)
        return Result(
            movie.title, "encontrado", imdb, tmdb_id, sources[0].url, api_title,
            sources=sources,
        )
    except urllib.error.HTTPError as error:
        status = "indisponivel" if error.code == 404 else "erro"
        return Result(
            movie.title, status, imdb, tmdb_id, api_title=api_title,
            error=f"HTTP {error.code}: {error.reason}"
        )
    except Exception as error:  # a falha fica no relatório e pode ser retomada
        return Result(
            movie.title, "erro", imdb, tmdb_id, api_title=api_title,
            error=f"{type(error).__name__}: {error}"
        )


def process_movie(
    movie: Movie,
    providers: dict[int, Provider],
    tmdb_key: str,
    validate: bool,
    delay: float,
) -> Result:
    """Processa com retentativa para oscilações de CDN, DNS e JSON vazio."""
    result = Result(movie.title, "erro", error="não iniciado")
    for attempt in range(3):
        result = process_movie_once(movie, providers, tmdb_key, validate, delay)
        if result.status != "erro":
            return result
        if attempt < 2:
            time.sleep(1.5 * (attempt + 1))
    return result


def open_cache(path: Path) -> sqlite3.Connection:
    path.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(path)
    db.execute("PRAGMA journal_mode=WAL")
    db.execute("PRAGMA synchronous=NORMAL")
    db.execute("PRAGMA busy_timeout=5000")
    db.execute(
        """
        CREATE TABLE IF NOT EXISTS movies (
          title TEXT PRIMARY KEY,
          status TEXT NOT NULL,
          imdb TEXT NOT NULL DEFAULT '',
          tmdb_id TEXT NOT NULL DEFAULT '',
          url TEXT NOT NULL DEFAULT '',
          api_title TEXT NOT NULL DEFAULT '',
          error TEXT NOT NULL DEFAULT '',
          updated_at INTEGER NOT NULL
        )
        """
    )
    columns = {row[1] for row in db.execute("PRAGMA table_info(movies)")}
    if "sources_json" not in columns:
        db.execute("ALTER TABLE movies ADD COLUMN sources_json TEXT NOT NULL DEFAULT '[]'")
    db.commit()
    return db


def acquire_execution_lock(output: Path):
    """Impede dois geradores de escreverem no mesmo cache simultaneamente."""
    output.mkdir(parents=True, exist_ok=True)
    lock_path = output / "execucao.lock"
    handle = lock_path.open("a+", encoding="utf-8")
    try:
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        handle.seek(0)
        owner = handle.read().strip()
        raise SystemExit(
            "Já existe uma geração em andamento"
            + (f" (PID {owner})" if owner else "")
            + ". A segunda execução foi cancelada para proteger o cache."
        )
    handle.seek(0)
    handle.truncate()
    handle.write(str(os.getpid()))
    handle.flush()
    return handle


def cache_rows(db: sqlite3.Connection) -> dict[str, Result]:
    rows = db.execute(
        "SELECT title,status,imdb,tmdb_id,url,api_title,error,sources_json FROM movies"
    ).fetchall()
    results: dict[str, Result] = {}
    for row in rows:
        try:
            raw_sources = json.loads(row[7] or "[]")
            sources = tuple(
                EmbedSource(str(item["url"]), str(item.get("language") or "dub"),
                            str(item.get("label") or "Dublado"))
                for item in raw_sources if isinstance(item, dict) and item.get("url")
            )
        except Exception:
            sources = ()
        results[row[0]] = Result(*row[:7], sources=sources)
    return results


def save_result(db: sqlite3.Connection, result: Result) -> None:
    db.execute(
        """
        INSERT INTO movies(title,status,imdb,tmdb_id,url,api_title,error,updated_at,sources_json)
        VALUES(?,?,?,?,?,?,?,?,?)
        ON CONFLICT(title) DO UPDATE SET
          status=excluded.status, imdb=excluded.imdb, tmdb_id=excluded.tmdb_id,
          url=excluded.url, api_title=excluded.api_title, error=excluded.error,
          updated_at=excluded.updated_at, sources_json=excluded.sources_json
        """,
        (
            result.title,
            result.status,
            result.imdb,
            result.tmdb_id,
            result.url,
            result.api_title,
            result.error,
            int(time.time()),
            json.dumps(
                [source.__dict__ for source in result.sources],
                ensure_ascii=False,
                separators=(",", ":"),
            ),
        ),
    )


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(content, encoding="utf-8")
    temporary.replace(path)


def quote_m3u(value: str) -> str:
    return value.replace('"', "'").replace("\n", " ")


def result_sources(item: Result) -> tuple[EmbedSource, ...]:
    if item.sources:
        return item.sources
    return (EmbedSource(item.url),) if item.url else ()


def app_fields(item: Result) -> list[str]:
    grouped: dict[str, list[str]] = {}
    for source in result_sources(item):
        bucket = grouped.setdefault(source.language if source.language in {"dub", "leg"} else "dub", [])
        if source.url not in bucket:
            bucket.append(source.url)
    return [f"{language}=" + ",".join(grouped[language]) for language in ("dub", "leg") if grouped.get(language)]


def write_outputs(output: Path, movies: Iterable[Movie], results: dict[str, Result]) -> None:
    ordered = [results[movie.title] for movie in movies if movie.title in results]
    found = [item for item in ordered if item.status == "encontrado" and item.url]

    # Mesmo formato das fatias VOD: título, versão e uma ou mais fontes.
    app_lines = ["\t".join([item.title] + app_fields(item)) for item in found]
    atomic_write(output / "filmes-embedplayer.txt", "\n".join(app_lines) + ("\n" if app_lines else ""))

    m3u = ["#EXTM3U"]
    for item in found:
        sources = result_sources(item)
        for number, source in enumerate(sources, 1):
            m3u.append(
                f'#EXTINF:-1 tvg-id="{item.imdb}" group-title="Filmes" '
                f'audio="{source.language}" source="{number}",'
                f'{quote_m3u(item.title)} — {quote_m3u(source.label)} — Fonte {number}'
            )
            m3u.append(source.url)
    atomic_write(output / "filmes-embedplayer.m3u", "\n".join(m3u) + "\n")

    with (output / "filmes-embedplayer.csv").open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["titulo", "imdb", "tmdb", "idioma", "fonte", "url", "titulo_no_provedor"])
        for item in found:
            for number, source in enumerate(result_sources(item), 1):
                writer.writerow([
                    item.title, item.imdb, item.tmdb_id, source.language,
                    number, source.url, item.api_title,
                ])

    for status, filename in (
        ("sem_imdb", "sem-imdb.txt"),
        ("sem_codigo_origem", "sem-codigo-na-origem.txt"),
        ("conflito_id", "conflitos-de-id.txt"),
        ("indisponivel", "nao-disponiveis.txt"),
        ("erro", "erros.txt"),
    ):
        lines = []
        for item in ordered:
            if item.status == status:
                detail = item.error or item.api_title or item.imdb
                lines.append(f"{item.title}\t{detail}".rstrip())
        atomic_write(output / filename, "\n".join(lines) + ("\n" if lines else ""))

    counts: dict[str, int] = {}
    for item in ordered:
        counts[item.status] = counts.get(item.status, 0) + 1
    summary = {
        "total_catalogo": len(list(movies)) if not isinstance(movies, list) else len(movies),
        "processados": len(ordered),
        **counts,
        "gerado_em": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
    }
    atomic_write(output / "resumo.json", json.dumps(summary, ensure_ascii=False, indent=2) + "\n")
    atomic_write(
        output / "LEIA-ME.txt",
        "LISTA AUTOMÁTICA DE FILMES EMBEDPLAYER\n\n"
        "filmes-embedplayer.txt  Formato compacto usado pelo catálogo VOD dos apps.\n"
        "filmes-embedplayer.m3u  Formato compatível com players M3U.\n"
        "filmes-embedplayer.csv  Relação técnica com IMDb, TMDB e endereço final.\n"
        "nao-disponiveis.txt     Filmes conhecidos, mas sem HLS válido no provedor.\n"
        "sem-imdb.txt            Títulos que não puderam ser associados com segurança.\n"
        "erros.txt               Falhas temporárias que podem ser tentadas novamente.\n"
        "sem-codigo-na-origem.txt Itens cuja fonte não informou TMDB/IMDb.\n"
        "conflitos-de-id.txt     Fontes do mesmo item que informaram IDs diferentes.\n"
        "resumo.json             Totais e data da última geração.\n\n"
        "Para atualizar e colocar os links como fontes principais no catálogo:\n"
        "python3 gerar_embedplayer_filmes.py --repetir-erros --aplicar\n\n"
        "O cache.sqlite3 permite continuar sem refazer filmes já concluídos.\n",
    )


def apply_to_catalog(results: dict[str, Result]) -> int:
    sources_by_title = {
        title: result_sources(item)
        for title, item in results.items()
        if item.status == "encontrado" and item.url
    }
    changed = 0
    valid_names = {f"filmes-{letter}.txt" for letter in "#ABCDEFGHIJKLMNOPQRSTUVWXYZ"}
    for file in sorted(VOD_DIR.glob("filmes-*.txt")):
        if file.name not in valid_names:
            continue
        output: list[str] = []
        file_changed = False
        for raw in file.read_text(encoding="utf-8").splitlines():
            fields = raw.split("\t")
            new_sources = sources_by_title.get(fields[0]) if fields else None
            if not new_sources:
                output.append(raw)
                continue
            grouped: dict[str, list[str]] = {}
            for source in new_sources:
                grouped.setdefault(source.language if source.language in {"dub", "leg"} else "dub", []).append(source.url)
            for language in ("leg", "dub"):
                fresh = grouped.get(language, [])
                if not fresh:
                    continue
                field_index = next(
                    (i for i, field in enumerate(fields[1:], 1) if field.startswith(language + "=")),
                    None,
                )
                if field_index is None:
                    fields.insert(1, language + "=" + ",".join(dict.fromkeys(fresh)))
                    file_changed = True
                else:
                    old = [source for source in fields[field_index][4:].split(",") if source]
                    merged = list(dict.fromkeys(fresh + old))
                    replacement = language + "=" + ",".join(merged)
                    if fields[field_index] != replacement:
                        fields[field_index] = replacement
                        file_changed = True
            output.append("\t".join(fields))
        if file_changed:
            atomic_write(file, "\n".join(output) + "\n")
            changed += 1
    return changed


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Resolve filmes por stream_id -> TMDB ID -> IMDb ID -> master.txt, "
            "sem pesquisa por nome."
        )
    )
    parser.add_argument("--tmdb-key", default="", help="chave TMDB; também aceita TMDB_API_KEY")
    parser.add_argument("--workers", type=int, default=4, help="consultas paralelas (padrão: 4)")
    parser.add_argument("--delay", type=float, default=0.25, help="pausa por filme antes do provedor")
    parser.add_argument("--limit", type=int, default=0, help="processa somente N pendentes")
    parser.add_argument("--titulo", action="append", default=[], help="processa somente título exato")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--cache", type=Path, default=DEFAULT_OUTPUT / "cache.sqlite3")
    parser.add_argument("--sem-validar", action="store_true", help="não abre o master.txt para validar HLS")
    parser.add_argument("--repetir-erros", action="store_true", help="tenta novamente erros já armazenados")
    parser.add_argument("--reprocessar", action="store_true", help="refaz inclusive resultados concluídos")
    parser.add_argument(
        "--completar-fontes",
        action="store_true",
        help="refaz resultados antigos que guardavam somente um servidor, preservando IDs do cache",
    )
    parser.add_argument(
        "--aplicar",
        action="store_true",
        help="coloca cada master.txt como primeira fonte nas fatias vod existentes",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.workers < 1 or args.workers > 96:
        raise SystemExit("--workers deve estar entre 1 e 96")
    selected = set(args.titulo) or None
    movies = catalog_movies(selected)
    if not movies:
        raise SystemExit("Nenhum filme encontrado no catálogo para os filtros informados.")
    tmdb_key = discover_tmdb_key(args.tmdb_key)
    providers = catalog_providers()
    if not providers:
        raise SystemExit("Nenhum servidor de origem foi encontrado em vod/indice.txt.")
    # A variável permanece viva até o fim de main e, com ela, a trava do SO.
    execution_lock = acquire_execution_lock(args.output)
    db = open_cache(args.cache)
    previous = cache_rows(db)
    if args.completar_fontes:
        # A passagem anterior pode ter recebido 404/503 temporário. Restaura o
        # que já está publicado antes de consultar novamente e jamais rebaixa.
        for title, published_sources in catalog_embed_sources().items():
            old = previous.get(title)
            if old is None or not old.imdb or not old.tmdb_id:
                continue
            merged = tuple(dict.fromkeys(published_sources + old.sources))
            restored = Result(
                old.title, "encontrado", old.imdb, old.tmdb_id,
                merged[0].url, old.api_title, old.error, merged,
            )
            previous[title] = restored
            save_result(db, restored)
        db.commit()
    # Reaproveita também entre retomadas, não apenas entre threads da mesma
    # execução. O cache contém somente relações obtidas por IDs exatos.
    with CACHE_LOCK:
        for cached_result in previous.values():
            if cached_result.tmdb_id and cached_result.imdb:
                EXACT_ID_HINTS[cached_result.title] = (
                    cached_result.tmdb_id, cached_result.imdb,
                )
            if cached_result.tmdb_id and (
                cached_result.imdb or cached_result.status == "sem_imdb"
            ):
                TMDB_IMDB_CACHE.setdefault(cached_result.tmdb_id, cached_result.imdb)
            if (
                cached_result.imdb
                and cached_result.status in {"encontrado", "indisponivel"}
                and (cached_result.status == "indisponivel" or cached_result.sources)
            ):
                EMBED_RESULT_CACHE.setdefault(
                    cached_result.imdb,
                    (cached_result.sources, cached_result.api_title),
                )
    terminal = {
        "encontrado", "sem_imdb", "sem_codigo_origem", "conflito_id", "indisponivel"
    }
    pending = []
    for movie in movies:
        old = previous.get(movie.title)
        if args.reprocessar or old is None:
            pending.append(movie)
        elif args.completar_fontes and old.status == "encontrado" and len(old.sources) < 2:
            pending.append(movie)
        elif old.status == "erro" and args.repetir_erros:
            pending.append(movie)
        elif old.status not in terminal and old.status != "erro":
            pending.append(movie)
    if args.limit:
        pending = pending[: args.limit]

    print(f"Catálogo: {len(movies)} filmes | pendentes nesta execução: {len(pending)}")
    completed = 0
    started = time.monotonic()
    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
            futures = {
                pool.submit(
                    process_movie,
                    movie,
                    providers,
                    tmdb_key,
                    not args.sem_validar,
                    args.delay,
                ): movie
                for movie in pending
            }
            for future in concurrent.futures.as_completed(futures):
                result = future.result()
                old = previous.get(result.title)
                if args.completar_fontes and old is not None and old.status == "encontrado":
                    if result.status != "encontrado" or not result.sources:
                        result = old
                    else:
                        merged = tuple(dict.fromkeys(result.sources + old.sources))
                        result.sources = merged
                        result.url = merged[0].url
                save_result(db, result)
                previous[result.title] = result
                completed += 1
                if completed % 10 == 0:
                    db.commit()
                if completed == 1 or completed % 25 == 0 or completed == len(pending):
                    elapsed = max(time.monotonic() - started, 0.001)
                    rate = completed / elapsed
                    remaining = (len(pending) - completed) / rate if rate else 0
                    with PRINT_LOCK:
                        print(
                            f"[{completed}/{len(pending)}] {result.status}: {result.title} "
                            f"| restante aproximado {remaining / 60:.1f} min",
                            flush=True,
                        )
    except KeyboardInterrupt:
        print("\nInterrompido: o progresso ficou salvo e será retomado na próxima execução.")
    finally:
        db.commit()
        all_results = cache_rows(db)
        write_outputs(args.output, movies, all_results)
        db.close()

    if args.aplicar:
        changed = apply_to_catalog(all_results)
        print(f"Catálogo atualizado: {changed} arquivos de letras alterados.")
    found = sum(
        1
        for movie in movies
        if (item := all_results.get(movie.title)) and item.status == "encontrado"
    )
    print(f"Concluído nesta etapa. Links válidos no arquivo: {found}")
    print(f"Saída: {args.output / 'filmes-embedplayer.txt'}")
    execution_lock.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
