#!/usr/bin/env python3
"""Sincroniza IDs exatos da RedeFlix e resolve fontes EmbedPlayer.

Não pesquisa por nome. Filmes usam TMDB -> IMDb -> EmbedPlayer; séries,
animes e doramas usam diretamente TMDB/temporada/episódio -> EmbedPlayer.
O cache permite retomar a execução e reaproveita os resultados dos geradores
anteriores do projeto.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import re
import sqlite3
import threading
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path

from gerar_embedplayer_filmes import (
    EMBED_API,
    USER_AGENT,
    EmbedSource,
    acquire_execution_lock,
    atomic_write,
    discover_tmdb_key,
    resolve_embed,
    tmdb_json,
)
from gerar_embedplayer_series import resolve_episode


ROOT = Path(__file__).resolve().parent
STATE = ROOT / "vod" / "redeflix"
OUTPUT = ROOT / "arquivos-gerados" / "redeflix"
URLS = {
    "filmes": "https://redeflixapi.store/list-movie-ids.txt",
    "series": "https://redeflixapi.store/list-tv-ids.txt",
    "animes": "https://redeflixapi.store/list-anime-ids.txt",
    "doramas": "https://redeflixapi.store/list-dorama-ids.txt",
}
PRINT_LOCK = threading.Lock()
TMDB_RATE_LOCK = threading.Lock()
TMDB_NEXT_REQUEST = 0.0
ANIMATION_GENRE_ID = 16
LEGACY_SERIES_CACHE = ROOT / "arquivos-gerados" / "embedplayer-series" / "cache.sqlite3"
LEGACY_TMDB_INDEX = STATE / "series-tmdb.json"


@dataclass(frozen=True)
class Episode:
    category: str
    tmdb: str
    title: str
    year: str
    season: int
    episode: int


@dataclass
class Resolved:
    media_type: str
    tmdb: str
    season: int
    episode: int
    status: str
    title: str = ""
    year: str = ""
    imdb: str = ""
    sources: tuple[EmbedSource, ...] = ()
    error: str = ""


def download(url: str) -> bytes:
    request = urllib.request.Request(
        url,
        headers={"User-Agent": USER_AGENT, "Accept": "text/plain,application/json,*/*"},
    )
    with urllib.request.urlopen(request, timeout=90) as response:
        return response.read()


def unique_ids(values) -> list[str]:
    seen: set[str] = set()
    output: list[str] = []
    for value in values:
        value = str(value).strip()
        if value.isdigit() and value not in seen:
            seen.add(value)
            output.append(value)
    return output


def load_previous(path: Path) -> set[str]:
    try:
        return {line.strip() for line in path.read_text(encoding="utf-8").splitlines() if line.strip()}
    except OSError:
        return set()


def persist_collection(category: str, items: list[dict]) -> None:
    """Grava a coleção já classificada no formato consumido pelos apps."""
    ids = unique_ids(item["id"] for item in items)
    episode_keys = [
        f'{item["id"]}\t{season}\t{episode}'
        for item in items for season, episode in item["episodios"]
    ]
    atomic_write(STATE / f"ids-{category}.txt", "\n".join(ids) + ("\n" if ids else ""))
    atomic_write(
        STATE / f"episodios-{category}.txt",
        "\n".join(episode_keys) + ("\n" if episode_keys else ""),
    )
    lines = [
        f'{item["id"]}\t{item["nome"]}\t{item["ano"]}\t{len(item["episodios"])}'
        for item in items
    ]
    atomic_write(STATE / f"catalogo-{category}.txt", "\n".join(lines) + ("\n" if lines else ""))


def separate_animations(collections: dict[str, list[dict]]) -> list[dict]:
    """Move toda animação que veio em Doramas para Animes pelo ID TMDB.

    A lista de origem pode repetir ou classificar incorretamente um título. A
    decisão usa o gênero 16 do próprio TMDB e fica em cache, portanto a rotina
    semanal só consulta IDs novos. Episódios de duplicatas são unidos em vez de
    uma das listas apagar a outra.
    """
    doramas = collections.get("doramas", [])
    if not doramas:
        return []
    cache_path = STATE / "classificacao-tv.json"
    try:
        cache = json.loads(cache_path.read_text(encoding="utf-8"))
        if not isinstance(cache, dict):
            cache = {}
    except (OSError, json.JSONDecodeError):
        cache = {}

    missing = [item["id"] for item in doramas if item["id"] not in cache]
    if missing:
        key = discover_tmdb_key("")

        def inspect(tmdb: str) -> tuple[str, bool | None]:
            try:
                data = tmdb_json(f"/tv/{tmdb}", {"language": "pt-BR"}, key)
                genres = data.get("genres") or []
                return tmdb, any(int(genre.get("id") or 0) == ANIMATION_GENRE_ID for genre in genres)
            except Exception:
                # Falha transitória não vira classificação definitiva: o ID
                # fica fora do cache e será tentado novamente na próxima semana.
                return tmdb, None

        with concurrent.futures.ThreadPoolExecutor(max_workers=20) as pool:
            for tmdb, animation in pool.map(inspect, missing):
                if animation is None:
                    continue
                cache[tmdb] = {"animacao": animation, "verificado_em": int(time.time())}
        atomic_write(cache_path, json.dumps(cache, ensure_ascii=False, indent=2) + "\n")

    anime_by_id = {item["id"]: item for item in collections.get("animes", [])}
    moved: list[dict] = []
    kept: list[dict] = []
    for item in doramas:
        classified = cache.get(item["id"], {})
        if not bool(classified.get("animacao")):
            kept.append(item)
            continue
        moved.append(item)
        existing = anime_by_id.get(item["id"])
        if existing is None:
            anime_by_id[item["id"]] = item
            continue
        pairs = {tuple(pair) for pair in existing["episodios"]}
        existing["episodios"] = sorted(existing["episodios"] + [
            pair for pair in item["episodios"] if tuple(pair) not in pairs
        ])

    collections["animes"] = list(anime_by_id.values())
    collections["doramas"] = kept
    persist_collection("animes", collections["animes"])
    persist_collection("doramas", collections["doramas"])
    return moved


def sync_lists() -> tuple[list[str], dict[str, list[dict]], dict[str, set[str]], dict[str, set[str]]]:
    STATE.mkdir(parents=True, exist_ok=True)
    movie_ids = unique_ids(download(URLS["filmes"]).decode("utf-8", "replace").splitlines())
    collections: dict[str, list[dict]] = {}
    new_ids: dict[str, set[str]] = {}
    new_episodes: dict[str, set[str]] = {}

    movie_path = STATE / "ids-filmes.txt"
    old_movies = load_previous(movie_path)
    new_ids["filmes"] = set(movie_ids) - old_movies
    atomic_write(movie_path, "\n".join(movie_ids) + "\n")

    for category in ("series", "animes", "doramas"):
        payload = json.loads(download(URLS[category]))
        items = payload.get("items") if isinstance(payload, dict) else None
        if not isinstance(items, list):
            raise RuntimeError(f"lista {category} em formato inesperado")
        clean: list[dict] = []
        episode_keys: list[str] = []
        for raw in items:
            tmdb = str(raw.get("id_tmdb") or "")
            if not tmdb.isdigit():
                continue
            title = str(raw.get("nome") or f"TMDB {tmdb}").replace("\t", " ").strip()
            year = str(raw.get("ano") or "")
            episodes: list[list[int]] = []
            for season, numbers in (raw.get("episodios") or {}).items():
                if not str(season).isdigit() or not isinstance(numbers, dict):
                    continue
                for episode in numbers:
                    if str(episode).isdigit():
                        pair = [int(season), int(episode)]
                        episodes.append(pair)
                        episode_keys.append(f"{tmdb}\t{pair[0]}\t{pair[1]}")
            episodes.sort()
            clean.append({"id": tmdb, "nome": title, "ano": year, "episodios": episodes})
        collections[category] = clean

        id_path = STATE / f"ids-{category}.txt"
        episode_path = STATE / f"episodios-{category}.txt"
        ids = unique_ids(item["id"] for item in clean)
        old_ids = load_previous(id_path)
        old_episodes = load_previous(episode_path)
        new_ids[category] = set(ids) - old_ids
        new_episodes[category] = set(episode_keys) - old_episodes
        atomic_write(id_path, "\n".join(ids) + ("\n" if ids else ""))
        atomic_write(episode_path, "\n".join(episode_keys) + ("\n" if episode_keys else ""))
        catalog_lines = [
            f'{item["id"]}\t{item["nome"]}\t{item["ano"]}\t{len(item["episodios"])}'
            for item in clean
        ]
        atomic_write(STATE / f"catalogo-{category}.txt", "\n".join(catalog_lines) + "\n")

    moved = separate_animations(collections)
    if moved:
        print(
            f"Classificação corrigida: {len(moved)} animações movidas de Doramas para Animes.",
            flush=True,
        )

    manifest = {
        "atualizado_em": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "fontes": URLS,
        "totais": {
            "filmes": len(movie_ids),
            **{category: len(items) for category, items in collections.items()},
        },
        "episodios": {
            category: sum(len(item["episodios"]) for item in items)
            for category, items in collections.items()
        },
        "novos_ids": {category: len(values) for category, values in new_ids.items()},
        "novos_episodios": {category: len(values) for category, values in new_episodes.items()},
    }
    atomic_write(STATE / "manifesto.json", json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    return movie_ids, collections, new_ids, new_episodes


def open_cache(path: Path) -> sqlite3.Connection:
    path.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(path)
    db.execute("PRAGMA journal_mode=WAL")
    db.execute("PRAGMA synchronous=NORMAL")
    db.execute("PRAGMA busy_timeout=5000")
    db.execute(
        """CREATE TABLE IF NOT EXISTS resolved (
          media_type TEXT NOT NULL, tmdb TEXT NOT NULL, season INTEGER NOT NULL,
          episode INTEGER NOT NULL, status TEXT NOT NULL, title TEXT NOT NULL DEFAULT '',
          year TEXT NOT NULL DEFAULT '', imdb TEXT NOT NULL DEFAULT '',
          sources_json TEXT NOT NULL DEFAULT '[]', error TEXT NOT NULL DEFAULT '',
          updated_at INTEGER NOT NULL,
          PRIMARY KEY(media_type,tmdb,season,episode)
        )"""
    )
    db.commit()
    return db


def decode_sources(raw: str) -> tuple[EmbedSource, ...]:
    try:
        return tuple(
            EmbedSource(str(x["url"]), str(x.get("language") or "dub"), str(x.get("label") or "Dublado"))
            for x in json.loads(raw or "[]") if isinstance(x, dict) and x.get("url")
        )
    except Exception:
        return ()


def load_cache(db: sqlite3.Connection) -> dict[tuple[str, str, int, int], Resolved]:
    output = {}
    for row in db.execute(
        "SELECT media_type,tmdb,season,episode,status,title,year,imdb,sources_json,error FROM resolved"
    ):
        item = Resolved(*row[:8], sources=decode_sources(row[8]), error=row[9])
        output[(item.media_type, item.tmdb, item.season, item.episode)] = item
    return output


def save(db: sqlite3.Connection, item: Resolved) -> None:
    raw = json.dumps([source.__dict__ for source in item.sources], ensure_ascii=False, separators=(",", ":"))
    db.execute(
        """INSERT INTO resolved
        (media_type,tmdb,season,episode,status,title,year,imdb,sources_json,error,updated_at)
        VALUES(?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(media_type,tmdb,season,episode) DO UPDATE SET
          status=excluded.status,title=excluded.title,year=excluded.year,imdb=excluded.imdb,
          sources_json=excluded.sources_json,error=excluded.error,updated_at=excluded.updated_at""",
        (item.media_type, item.tmdb, item.season, item.episode, item.status,
         item.title, item.year, item.imdb, raw, item.error, int(time.time())),
    )


def import_legacy(db: sqlite3.Connection) -> None:
    if db.execute("SELECT COUNT(*) FROM resolved").fetchone()[0]:
        return
    movie_cache = ROOT / "arquivos-gerados/embedplayer-filmes/cache.sqlite3"
    if movie_cache.exists():
        old = sqlite3.connect(f"file:{movie_cache}?mode=ro", uri=True)
        for title, status, imdb, tmdb, raw, error in old.execute(
            "SELECT title,status,imdb,tmdb_id,sources_json,error FROM movies WHERE tmdb_id<>''"
        ):
            if not str(tmdb).isdigit():
                continue
            item = Resolved("movie", str(tmdb), 0, 0, status, title=title, imdb=imdb,
                            sources=decode_sources(raw), error=error)
            current = db.execute(
                "SELECT status FROM resolved WHERE media_type='movie' AND tmdb=? AND season=0 AND episode=0",
                (str(tmdb),),
            ).fetchone()
            rank = {"encontrado": 4, "indisponivel": 3, "sem_imdb": 2, "erro": 1}
            if not current or rank.get(status, 0) > rank.get(current[0], 0):
                save(db, item)
        old.close()

    series_cache = ROOT / "arquivos-gerados/embedplayer-series/cache.sqlite3"
    if series_cache.exists():
        old = sqlite3.connect(f"file:{series_cache}?mode=ro", uri=True)
        for title, season, episode, status, tmdb, raw, error in old.execute(
            "SELECT title,season,episode,status,tmdb_id,sources_json,error FROM episodes WHERE tmdb_id<>''"
        ):
            if str(tmdb).isdigit():
                save(db, Resolved("tv", str(tmdb), int(season), int(episode), status,
                                  title=title, sources=decode_sources(raw), error=error))
        old.close()
    db.commit()


def process_movie(tmdb: str, tmdb_key: str, validate: bool) -> Resolved:
    global TMDB_NEXT_REQUEST
    try:
        # O TMDB aceita paralelismo, mas limita rajadas. Espaçar somente o
        # começo dessas chamadas evita 429 sem reduzir séries/animes/doramas.
        with TMDB_RATE_LOCK:
            wait = TMDB_NEXT_REQUEST - time.monotonic()
            if wait > 0:
                time.sleep(wait)
            TMDB_NEXT_REQUEST = time.monotonic() + 0.04
        data = tmdb_json(
            f"/movie/{tmdb}",
            {"language": "pt-BR", "append_to_response": "external_ids"},
            tmdb_key,
        )
        title = str(data.get("title") or data.get("original_title") or f"TMDB {tmdb}")
        year = str(data.get("release_date") or "")[:4]
        imdb = str((data.get("external_ids") or {}).get("imdb_id") or "")
        if not re.fullmatch(r"tt\d{7,10}", imdb):
            return Resolved("movie", tmdb, 0, 0, "sem_imdb", title, year)
        sources, api_title = resolve_embed(imdb, validate)
        if not sources:
            return Resolved("movie", tmdb, 0, 0, "indisponivel", title, year, imdb)
        return Resolved("movie", tmdb, 0, 0, "encontrado", title, year, imdb, sources)
    except urllib.error.HTTPError as error:
        status = "indisponivel" if error.code == 404 else "erro"
        return Resolved("movie", tmdb, 0, 0, status, error=f"HTTP {error.code}")
    except Exception as error:
        return Resolved("movie", tmdb, 0, 0, "erro", error=f"{type(error).__name__}: {error}")


def process_episode(
    item: Episode, validate: bool, missing_attempts: int = 1, delay: float = 0.0,
) -> Resolved:
    class Block:
        key = item.tmdb
        title = item.title
    result = None
    for attempt in range(max(1, missing_attempts)):
        result = resolve_episode(
            Block(), item.tmdb, item.season, item.episode, validate, delay
        )
        if result.status != "indisponivel" or attempt + 1 >= missing_attempts:
            break
        # Um 404 durante rajada pode ser proteção temporária do provedor. Uma
        # segunda tentativa espaçada evita gravá-lo como ausência definitiva.
        time.sleep(0.35 * (attempt + 1))
    assert result is not None
    return Resolved("tv", item.tmdb, item.season, item.episode, result.status,
                    item.title, item.year, sources=result.sources, error=result.error)


def progress(done: int, total: int, started: float, item: Resolved) -> None:
    elapsed = max(time.monotonic() - started, 0.001)
    rate = done / elapsed
    eta = (total - done) / rate if rate else 0
    with PRINT_LOCK:
        suffix = f" S{item.season:02}E{item.episode:02}" if item.media_type == "tv" else ""
        print(f"[{done}/{total}] {rate:.1f}/s · ETA {eta/60:.1f} min · {item.status} · TMDB {item.tmdb}{suffix}", flush=True)


def generate(movie_ids: list[str], collections: dict[str, list[dict]], args) -> dict:
    db = open_cache(args.cache)
    import_legacy(db)
    cached = load_cache(db)
    terminal = {"encontrado", "indisponivel", "sem_imdb"}
    selected = {value.strip() for value in args.categorias.split(",") if value.strip()}
    invalid = selected - {"filmes", "series", "animes", "doramas"}
    if invalid:
        raise SystemExit("categorias desconhecidas: " + ", ".join(sorted(invalid)))
    movies = ([tmdb for tmdb in movie_ids if ("movie", tmdb, 0, 0) not in cached]
              if "filmes" in selected else [])
    if args.repetir_erros and "filmes" in selected:
        movies += [tmdb for tmdb in movie_ids if cached.get(("movie", tmdb, 0, 0), Resolved("movie", tmdb, 0, 0, "")).status == "erro"]

    episodes: list[Episode] = []
    seen: set[tuple[str, int, int]] = set()
    for category, items in collections.items():
        if category not in selected:
            continue
        published: set[str] | None = None
        if args.somente_titulos_publicados:
            published = set()
            try:
                for line in (STATE / f"links-{category}.txt").read_text(
                    encoding="utf-8"
                ).splitlines():
                    if line.startswith("@"):
                        fields = line[1:].split("\t")
                        if len(fields) >= 3 and fields[2].isdigit():
                            published.add(fields[2])
            except OSError:
                pass
        for raw in items:
            # Título que ainda não está no app ganha uma tentativa por episódio
            # nunca visto — é assim que anime e dorama novos entram. O que já
            # foi tentado e deu indisponível fica quieto: repescar os duzentos
            # e tantos mil episódios desses títulos todo dia levaria horas, e é
            # para isso que a repescagem vale só para os já publicados.
            titulo_novo = published is not None and raw["id"] not in published
            for season, episode in raw["episodios"]:
                key = (raw["id"], season, episode)
                old = cached.get(("tv", *key))
                if titulo_novo and old is not None:
                    continue
                retry_unavailable = bool(
                    old and old.status == "indisponivel" and args.repetir_indisponiveis
                )
                if key in seen or (
                    old and old.status in terminal and not args.reprocessar and not retry_unavailable
                ):
                    continue
                if old and old.status == "erro" and not args.repetir_erros and not args.reprocessar:
                    continue
                seen.add(key)
                episodes.append(Episode(category, raw["id"], raw["nome"], raw["ano"], season, episode))
    if args.reprocessar and "filmes" in selected:
        movies = list(movie_ids)
    tasks = [("movie", value) for value in dict.fromkeys(movies)] + [("tv", value) for value in episodes]
    if args.limit:
        tasks = tasks[:args.limit]
    print(f"Cache reaproveitado: {len(cached)} itens | pendentes: {len(tasks)}", flush=True)
    tmdb_key = discover_tmdb_key(args.tmdb_key) if any(kind == "movie" for kind, _ in tasks) else ""
    started = time.monotonic()
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = {
            pool.submit(process_movie, value, tmdb_key, not args.sem_validar)
            if kind == "movie" else
            pool.submit(
                process_episode, value, not args.sem_validar,
                args.tentativas_indisponiveis, args.delay_episodio,
            ): (kind, value)
            for kind, value in tasks
        }
        for done, future in enumerate(concurrent.futures.as_completed(futures), 1):
            item = future.result()
            old = cached.get((item.media_type, item.tmdb, item.season, item.episode))
            if old and old.status == "encontrado" and item.status != "encontrado":
                item = old
            save(db, item)
            cached[(item.media_type, item.tmdb, item.season, item.episode)] = item
            if done % 25 == 0 or done == len(tasks):
                db.commit()
                progress(done, len(tasks), started, item)
    db.commit()
    write_outputs(cached, movie_ids, collections)
    changed = apply_to_catalog(cached) if args.aplicar else {"filmes": 0, "series": 0}
    db.close()
    return {"pendentes_processados": len(tasks), "arquivos_alterados": changed}


def write_outputs(cache, movie_ids, collections) -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    movie_lines = []
    for tmdb in movie_ids:
        item = cache.get(("movie", tmdb, 0, 0))
        if not item or item.status != "encontrado" or not item.sources:
            continue
        title = item.title + (f" ({item.year})" if item.year else "")
        urls = ",".join(dict.fromkeys(source.url for source in item.sources))
        movie_lines.append(f"{title}\tdub={urls}\ttmdb={tmdb}\timdb={item.imdb}")
    movie_text = "\n".join(movie_lines) + ("\n" if movie_lines else "")
    atomic_write(OUTPUT / "filmes.txt", movie_text)
    atomic_write(STATE / "links-filmes.txt", movie_text)

    legacy_sources = load_legacy_series_sources()
    for category, items in collections.items():
        category_reserves = legacy_sources if category in {"animes", "doramas"} else {}
        lines: list[str] = []
        for raw in items:
            found = []
            for season, episode in raw["episodios"]:
                item = cache.get(("tv", raw["id"], season, episode))
                by_language: dict[str, list[str]] = {}
                if item and item.status == "encontrado" and item.sources:
                    for source in item.sources:
                        language = source.language if source.language in {"dub", "leg"} else "dub"
                        by_language.setdefault(language, []).append(source.url)
                # A fonte nova continua principal. As fontes do catálogo geral
                # de Séries entram depois como reservas e também completam um
                # episódio quando o EmbedPlayer ainda não o publicou.
                for language in ("dub", "leg"):
                    reserves = category_reserves.get(
                        (raw["id"], season, episode, language), ()
                    )
                    urls = list(dict.fromkeys(by_language.get(language, []) + list(reserves)))
                    if urls:
                        found.append(f"{season}\t{episode}\t{language}\t{','.join(urls)}")
            if found:
                lines.append(f'@{raw["nome"]}\t{raw["ano"]}\t{raw["id"]}')
                lines.extend(found)
        category_text = "\n".join(lines) + ("\n" if lines else "")
        atomic_write(OUTPUT / f"{category}.txt", category_text)
        atomic_write(STATE / f"links-{category}.txt", category_text)

    statuses: dict[str, int] = {}
    for item in cache.values():
        statuses[item.status] = statuses.get(item.status, 0) + 1
    summary = {"gerado_em": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "status": statuses}
    atomic_write(OUTPUT / "resumo.json", json.dumps(summary, ensure_ascii=False, indent=2) + "\n")


def load_legacy_series_sources() -> dict[tuple[str, int, int, str], tuple[str, ...]]:
    """Lê as fontes já catalogadas em Séries e indexa-as pelo ID TMDB.

    Os arquivos antigos comprimem cada endereço como ``base:resto``. Esse
    formato é preservado para não repetir nem publicar as credenciais contidas
    nas bases; cada aplicativo já expande o código usando ``vod/indice.txt``.
    """
    index_path = ROOT / "vod" / "indice.txt"
    if not index_path.exists():
        return {}

    bases: dict[int, str] = {}
    for raw in index_path.read_text(encoding="utf-8").splitlines():
        match = re.fullmatch(r"base:\s*(\d+)\s+(.+)", raw)
        if match and "desativado.invalid" not in match.group(2):
            bases[int(match.group(1))] = match.group(2)

    identities: dict[tuple[str, str], str] = {}
    if LEGACY_SERIES_CACHE.exists():
        db = sqlite3.connect(f"file:{LEGACY_SERIES_CACHE}?mode=ro", uri=True)
        for key, title, tmdb in db.execute(
            "SELECT key,title,tmdb_id FROM series "
            "WHERE status='encontrado' AND tmdb_id<>''"
        ):
            if not str(tmdb).isdigit():
                continue
            parts = str(key).split("\x1f", 1)
            if len(parts) == 2:
                identities[(parts[0], parts[1])] = str(tmdb)
            else:
                identities[(parts[0], str(title))] = str(tmdb)
        db.close()
        # O cache SQLite é local e grande demais para o Git. Este índice leve
        # deixa a automação semanal reconstruir as mesmas reservas na nuvem.
        portable = {
            f"{file_name}\x1f{title}": tmdb
            for (file_name, title), tmdb in sorted(identities.items())
        }
        atomic_write(
            LEGACY_TMDB_INDEX,
            json.dumps(portable, ensure_ascii=False, separators=(",", ":")) + "\n",
        )
    elif LEGACY_TMDB_INDEX.exists():
        try:
            portable = json.loads(LEGACY_TMDB_INDEX.read_text(encoding="utf-8"))
            for key, tmdb in portable.items():
                parts = str(key).split("\x1f", 1)
                if len(parts) == 2 and str(tmdb).isdigit():
                    identities[(parts[0], parts[1])] = str(tmdb)
        except (OSError, json.JSONDecodeError):
            return {}
    else:
        return {}

    collected: dict[tuple[str, int, int, str], list[str]] = {}
    for file_name in sorted({file_name for file_name, _ in identities}):
        path = ROOT / "vod" / file_name
        if not path.exists():
            continue
        title = ""
        for raw in path.read_text(encoding="utf-8").splitlines():
            if raw.startswith("@"):
                title = raw[1:].split("\t", 1)[0].strip()
                continue
            tmdb = identities.get((file_name, title))
            fields = raw.split("\t")
            if not tmdb or len(fields) < 4 or not fields[0].isdigit() or not fields[1].isdigit():
                continue
            language = fields[2] if fields[2] in {"dub", "leg"} else "dub"
            key = (tmdb, int(fields[0]), int(fields[1]), language)
            urls = collected.setdefault(key, [])
            for compact in fields[3].split(","):
                compact = compact.strip()
                if compact.startswith("https://"):
                    safe_value = compact
                elif compact.startswith("http://"):
                    # Endereço HTTP completo pode carregar credenciais. As
                    # reservas publicadas devem usar somente o código compacto.
                    continue
                else:
                    match = re.fullmatch(r"(\d+):(.+)", compact)
                    if not match or int(match.group(1)) not in bases:
                        continue
                    safe_value = compact
                if safe_value not in urls:
                    urls.append(safe_value)
    return {key: tuple(urls) for key, urls in collected.items()}


def apply_to_catalog(cache) -> dict[str, int]:
    movie_map: dict[str, list[str]] = {}
    old_movie = ROOT / "arquivos-gerados/embedplayer-filmes/cache.sqlite3"
    if old_movie.exists():
        db = sqlite3.connect(f"file:{old_movie}?mode=ro", uri=True)
        for title, tmdb in db.execute("SELECT title,tmdb_id FROM movies WHERE tmdb_id<>''"):
            movie_map.setdefault(str(tmdb), []).append(title)
        db.close()
    by_title: dict[str, tuple[EmbedSource, ...]] = {}
    for (kind, tmdb, season, episode), item in cache.items():
        if kind == "movie" and item.status == "encontrado":
            for title in movie_map.get(tmdb, []):
                by_title[title] = item.sources
    changed_movies = 0
    for path in sorted((ROOT / "vod").glob("filmes-*.txt")):
        if not re.fullmatch(r"filmes-(?:#|[A-Z])\.txt", path.name):
            continue
        lines, changed = [], False
        for raw in path.read_text(encoding="utf-8").splitlines():
            fields = raw.split("\t")
            sources = by_title.get(fields[0])
            if sources:
                urls = [source.url for source in sources if source.language == "dub"] or [source.url for source in sources]
                for index, field in enumerate(fields[1:], 1):
                    if field.startswith("dub="):
                        old = field[4:].split(",") if field[4:] else []
                        fields[index] = "dub=" + ",".join(dict.fromkeys(urls + old))
                        break
                else:
                    fields.insert(1, "dub=" + ",".join(dict.fromkeys(urls)))
            replacement = "\t".join(fields)
            changed = changed or replacement != raw
            lines.append(replacement)
        if changed:
            atomic_write(path, "\n".join(lines) + "\n")
            changed_movies += 1

    series_map: dict[str, str] = {}
    old_series = ROOT / "arquivos-gerados/embedplayer-series/cache.sqlite3"
    if old_series.exists():
        db = sqlite3.connect(f"file:{old_series}?mode=ro", uri=True)
        for title, tmdb in db.execute("SELECT title,tmdb_id FROM series WHERE status='encontrado'"):
            series_map[title] = str(tmdb)
        db.close()
    changed_series = 0
    for path in sorted((ROOT / "vod").glob("series-*-*.txt")):
        title = ""
        lines, changed = [], False
        for raw in path.read_text(encoding="utf-8").splitlines():
            if raw.startswith("@"):
                title = raw[1:].split("\t", 1)[0]
                lines.append(raw)
                continue
            match = re.fullmatch(r"(\d+)\t(\d+)\t(dub|leg)\t(.+)", raw)
            tmdb = series_map.get(title)
            if not match or match.group(3) != "dub" or not tmdb:
                lines.append(raw)
                continue
            item = cache.get(("tv", tmdb, int(match.group(1)), int(match.group(2))))
            if not item or item.status != "encontrado" or not item.sources:
                lines.append(raw)
                continue
            urls = [source.url for source in item.sources if source.language == "dub"] or [source.url for source in item.sources]
            replacement = "\t".join(match.group(i) for i in range(1, 4)) + "\t" + ",".join(
                dict.fromkeys(urls + match.group(4).split(","))
            )
            changed = changed or replacement != raw
            lines.append(replacement)
        if changed:
            atomic_write(path, "\n".join(lines) + "\n")
            changed_series += 1
    return {"filmes": changed_movies, "series": changed_series}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Atualiza IDs RedeFlix e gera fontes por IDs exatos.")
    parser.add_argument("--gerar", action="store_true", help="resolve as fontes ainda pendentes")
    parser.add_argument("--aplicar", action="store_true", help="coloca as fontes no catálogo VOD atual")
    parser.add_argument("--workers", type=int, default=64)
    parser.add_argument("--delay-episodio", type=float, default=0.0)
    parser.add_argument("--tentativas-indisponiveis", type=int, default=1)
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--tmdb-key", default="")
    parser.add_argument("--sem-validar", action="store_true")
    parser.add_argument("--repetir-erros", action="store_true")
    parser.add_argument(
        "--repetir-indisponiveis", action="store_true",
        help="consulta novamente itens antes ausentes; preserva qualquer fonte já encontrada",
    )
    parser.add_argument("--reprocessar", action="store_true")
    parser.add_argument(
        "--categorias", default="filmes,series,animes,doramas",
        help="limita a geração, por exemplo: animes,doramas",
    )
    parser.add_argument(
        "--somente-titulos-publicados", action="store_true",
        help="repesca indisponíveis só de títulos já no app; título novo tenta só episódio nunca visto",
    )
    parser.add_argument("--cache", type=Path, default=OUTPUT / "cache.sqlite3")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not 1 <= args.workers <= 192:
        raise SystemExit("--workers deve estar entre 1 e 192")
    if not 1 <= args.tentativas_indisponiveis <= 5:
        raise SystemExit("--tentativas-indisponiveis deve estar entre 1 e 5")
    lock = acquire_execution_lock(OUTPUT)
    movies, collections, new_ids, new_episodes = sync_lists()
    print("Listas sincronizadas: " + ", ".join(
        [f"{len(movies)} filmes"] + [f"{len(items)} {category}" for category, items in collections.items()]
    ), flush=True)
    print("Novos IDs: " + ", ".join(f"{k}={len(v)}" for k, v in new_ids.items()), flush=True)
    result = generate(movies, collections, args) if args.gerar else {"modo": "somente sincronização"}
    atomic_write(OUTPUT / "ultima-execucao.json", json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    lock.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
