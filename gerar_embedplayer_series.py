#!/usr/bin/env python3
"""Gera fontes EmbedPlayer para as séries usando somente identificadores exatos.

Cadeia de identificação:

    stream_id do episódio -> TMDB ID do episódio -> redirecionamento oficial
    do TMDB -> TMDB ID da série -> /tv/<id>/<temporada>/<episódio>/dub

O título nunca é usado como pesquisa. O cache SQLite permite interromper e
continuar, e ``--aplicar`` acrescenta cada fonte nova antes das fontes atuais.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import csv
import json
import re
import sqlite3
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path

from gerar_embedplayer_filmes import (
    EMBED_API,
    USER_AGENT,
    EmbedSource,
    Provider,
    acquire_execution_lock,
    atomic_write,
    catalog_providers,
    request,
    resolve_embed_page,
)


ROOT = Path(__file__).resolve().parent
VOD_DIR = ROOT / "vod"
DEFAULT_OUTPUT = ROOT / "arquivos-gerados" / "embedplayer-series"
SERIES_FILE = re.compile(r"series-(?:#|[A-Z])-\d+\.txt$")
EPISODE_LINE = re.compile(r"^(\d+)\t(\d+)\t(dub|leg)\t(.+)$")
SOURCE = re.compile(r"^(\d+):(.+)$")
TMDB_REDIRECT = re.compile(
    r"/tv/(\d+)(?:-[^/]*)?/season/(\d+)/episode/(\d+)(?:/|$)", re.I
)
PRINT_LOCK = threading.Lock()
NETWORK_LOCK = threading.Lock()
EPISODE_TMDB_CACHE: dict[tuple[str, str], str] = {}
SERIES_TMDB_CACHE: dict[str, tuple[str, int, int]] = {}


@dataclass(frozen=True)
class EpisodeRow:
    season: int
    episode: int
    language: str
    sources: tuple[tuple[int, str], ...]


@dataclass(frozen=True)
class SeriesBlock:
    key: str
    title: str
    file: Path
    episodes: tuple[EpisodeRow, ...]


@dataclass
class SeriesResult:
    key: str
    title: str
    status: str
    tmdb_id: str = ""
    episode_tmdb: str = ""
    error: str = ""


@dataclass
class EpisodeResult:
    key: str
    title: str
    season: int
    episode: int
    status: str
    tmdb_id: str = ""
    api_title: str = ""
    error: str = ""
    sources: tuple[EmbedSource, ...] = ()


def catalog_series(selected: set[str] | None = None) -> list[SeriesBlock]:
    blocks: list[SeriesBlock] = []
    for file in sorted(VOD_DIR.glob("series-*.txt")):
        if not SERIES_FILE.fullmatch(file.name):
            continue
        title = ""
        rows: list[EpisodeRow] = []

        def finish() -> None:
            if not title or (selected and title not in selected):
                return
            key = f"{file.name}\x1f{title}"
            blocks.append(SeriesBlock(key, title, file, tuple(rows)))

        for raw in file.read_text(encoding="utf-8").splitlines():
            if raw.startswith("@"):
                finish()
                title = raw[1:].strip()
                rows = []
                continue
            match = EPISODE_LINE.fullmatch(raw)
            if not title or not match:
                continue
            sources: list[tuple[int, str]] = []
            for value in match.group(4).split(","):
                source = SOURCE.fullmatch(value.strip())
                if source:
                    pair = (int(source.group(1)), source.group(2))
                    if pair not in sources:
                        sources.append(pair)
            rows.append(
                EpisodeRow(
                    int(match.group(1)), int(match.group(2)), match.group(3), tuple(sources)
                )
            )
        finish()
    return blocks


def episode_tmdb_id(
    row: EpisodeRow, providers: dict[int, Provider]
) -> tuple[str, list[str]]:
    """Obtém o TMDB do episódio diretamente da fonte que publicou o stream."""
    ids: set[str] = set()
    errors: list[str] = []
    ordered = sorted(row.sources, key=lambda pair: ({3: 0, 7: 1}.get(pair[0], 2), pair))
    for base_index, remainder in ordered:
        provider = providers.get(base_index)
        stream = re.match(r"(\d+)", remainder)
        if not provider or not stream or "desativado.invalid" in provider.api:
            continue
        stream_id = stream.group(1)
        cache_key = (provider.api, stream_id)
        with NETWORK_LOCK:
            cached = EPISODE_TMDB_CACHE.get(cache_key)
        if cached is not None:
            if cached:
                ids.add(cached)
            continue
        query = urllib.parse.urlencode(
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
                f"{provider.api}?{query}",
                headers={"Accept": "application/json"},
                timeout=20,
            )
            payload = json.loads(body)
            info = payload.get("info") or {}
            movie = payload.get("movie_data") or {}
            raw_id = info.get("tmdb_id") or movie.get("tmdb_id")
            exact = str(raw_id) if str(raw_id).isdigit() else ""
            with NETWORK_LOCK:
                EPISODE_TMDB_CACHE[cache_key] = exact
            if exact:
                ids.add(exact)
        except Exception as error:
            errors.append(f"base {base_index}/{stream_id}: {type(error).__name__}")
        if len(ids) > 1:
            break
    if len(ids) > 1:
        raise ValueError("IDs TMDB de episódio divergentes: " + ",".join(sorted(ids)))
    return (next(iter(ids)) if ids else ""), errors


def series_id_from_episode(episode_tmdb: str, season: int, episode: int) -> str:
    with NETWORK_LOCK:
        cached = SERIES_TMDB_CACHE.get(episode_tmdb)
    if cached is not None:
        series_id, cached_season, cached_episode = cached
        return series_id if (cached_season, cached_episode) == (season, episode) else ""
    opener = urllib.request.build_opener()
    _, final_url = request(
        opener,
        f"https://www.themoviedb.org/tv/episode/{episode_tmdb}",
        headers={"Accept": "text/html"},
        timeout=25,
    )
    match = TMDB_REDIRECT.search(urllib.parse.urlparse(final_url).path)
    if not match:
        return ""
    result = (match.group(1), int(match.group(2)), int(match.group(3)))
    with NETWORK_LOCK:
        SERIES_TMDB_CACHE[episode_tmdb] = result
    return result[0] if result[1:] == (season, episode) else ""


def map_series_once(block: SeriesBlock, providers: dict[int, Provider]) -> SeriesResult:
    errors: list[str] = []
    # Dublado primeiro porque é a rota disponibilizada pelo provedor final.
    rows = sorted(block.episodes, key=lambda row: (row.language != "dub", row.season, row.episode))
    for row in rows[:8]:
        try:
            episode_tmdb, source_errors = episode_tmdb_id(row, providers)
            errors.extend(source_errors)
            if not episode_tmdb:
                continue
            series_tmdb = series_id_from_episode(episode_tmdb, row.season, row.episode)
            if series_tmdb:
                return SeriesResult(
                    block.key, block.title, "encontrado", series_tmdb, episode_tmdb
                )
            errors.append(
                f"episódio TMDB {episode_tmdb} não confirmou S{row.season:02}E{row.episode:02}"
            )
        except urllib.error.HTTPError as error:
            errors.append(f"HTTP {error.code}")
        except Exception as error:
            errors.append(f"{type(error).__name__}: {error}")
    status = "erro" if any("HTTP 5" in item or "URLError" in item for item in errors) else "sem_id"
    return SeriesResult(block.key, block.title, status, error="; ".join(errors[:5]))


def map_series(block: SeriesBlock, providers: dict[int, Provider]) -> SeriesResult:
    result = SeriesResult(block.key, block.title, "erro", error="não iniciado")
    for attempt in range(3):
        result = map_series_once(block, providers)
        if result.status != "erro":
            return result
        if attempt < 2:
            time.sleep(1.5 * (attempt + 1))
    return result


def resolve_episode_once(
    block: SeriesBlock,
    series_tmdb: str,
    season: int,
    episode: int,
    validate: bool,
    delay: float,
) -> EpisodeResult:
    api_page = f"{EMBED_API}/tv/{series_tmdb}/{season}/{episode}/dub"
    try:
        if delay:
            time.sleep(delay)
        sources, api_title = resolve_embed_page(api_page, validate)
        if not sources:
            return EpisodeResult(
                block.key, block.title, season, episode, "indisponivel", series_tmdb,
                api_title=api_title,
            )
        return EpisodeResult(
            block.key, block.title, season, episode, "encontrado", series_tmdb,
            api_title, sources=sources,
        )
    except urllib.error.HTTPError as error:
        status = "indisponivel" if error.code == 404 else "erro"
        return EpisodeResult(
            block.key, block.title, season, episode, status, series_tmdb,
            error=f"HTTP {error.code}: {error.reason}",
        )
    except Exception as error:
        return EpisodeResult(
            block.key, block.title, season, episode, "erro", series_tmdb,
            error=f"{type(error).__name__}: {error}",
        )


def resolve_episode(*args) -> EpisodeResult:
    result: EpisodeResult | None = None
    for attempt in range(3):
        result = resolve_episode_once(*args)
        if result.status != "erro":
            return result
        if attempt < 2:
            time.sleep(1.5 * (attempt + 1))
    assert result is not None
    return result


def open_cache(path: Path) -> sqlite3.Connection:
    path.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(path)
    db.execute("PRAGMA journal_mode=WAL")
    db.execute("PRAGMA synchronous=NORMAL")
    db.execute("PRAGMA busy_timeout=5000")
    db.execute(
        """CREATE TABLE IF NOT EXISTS series (
          key TEXT PRIMARY KEY, title TEXT NOT NULL, status TEXT NOT NULL,
          tmdb_id TEXT NOT NULL DEFAULT '', episode_tmdb TEXT NOT NULL DEFAULT '',
          error TEXT NOT NULL DEFAULT '', updated_at INTEGER NOT NULL
        )"""
    )
    db.execute(
        """CREATE TABLE IF NOT EXISTS episodes (
          key TEXT NOT NULL, title TEXT NOT NULL, season INTEGER NOT NULL,
          episode INTEGER NOT NULL, status TEXT NOT NULL,
          tmdb_id TEXT NOT NULL DEFAULT '', api_title TEXT NOT NULL DEFAULT '',
          error TEXT NOT NULL DEFAULT '', sources_json TEXT NOT NULL DEFAULT '[]',
          updated_at INTEGER NOT NULL,
          PRIMARY KEY(key,season,episode)
        )"""
    )
    db.commit()
    return db


def load_series(db: sqlite3.Connection) -> dict[str, SeriesResult]:
    return {
        row[0]: SeriesResult(*row)
        for row in db.execute("SELECT key,title,status,tmdb_id,episode_tmdb,error FROM series")
    }


def save_series(db: sqlite3.Connection, item: SeriesResult) -> None:
    db.execute(
        """INSERT INTO series(key,title,status,tmdb_id,episode_tmdb,error,updated_at)
        VALUES(?,?,?,?,?,?,?) ON CONFLICT(key) DO UPDATE SET
        title=excluded.title,status=excluded.status,tmdb_id=excluded.tmdb_id,
        episode_tmdb=excluded.episode_tmdb,error=excluded.error,updated_at=excluded.updated_at""",
        (item.key, item.title, item.status, item.tmdb_id, item.episode_tmdb,
         item.error, int(time.time())),
    )


def decode_sources(raw: str) -> tuple[EmbedSource, ...]:
    try:
        return tuple(
            EmbedSource(str(item["url"]), str(item.get("language") or "dub"),
                        str(item.get("label") or "Dublado"))
            for item in json.loads(raw or "[]") if isinstance(item, dict) and item.get("url")
        )
    except Exception:
        return ()


def load_episodes(db: sqlite3.Connection) -> dict[tuple[str, int, int], EpisodeResult]:
    results = {}
    for row in db.execute(
        "SELECT key,title,season,episode,status,tmdb_id,api_title,error,sources_json FROM episodes"
    ):
        results[(row[0], row[2], row[3])] = EpisodeResult(*row[:8], sources=decode_sources(row[8]))
    return results


def save_episode(db: sqlite3.Connection, item: EpisodeResult) -> None:
    db.execute(
        """INSERT INTO episodes
        (key,title,season,episode,status,tmdb_id,api_title,error,sources_json,updated_at)
        VALUES(?,?,?,?,?,?,?,?,?,?) ON CONFLICT(key,season,episode) DO UPDATE SET
        title=excluded.title,status=excluded.status,tmdb_id=excluded.tmdb_id,
        api_title=excluded.api_title,error=excluded.error,
        sources_json=excluded.sources_json,updated_at=excluded.updated_at""",
        (
            item.key, item.title, item.season, item.episode, item.status, item.tmdb_id,
            item.api_title, item.error,
            json.dumps([source.__dict__ for source in item.sources], ensure_ascii=False,
                       separators=(",", ":")),
            int(time.time()),
        ),
    )


def write_outputs(
    output: Path,
    blocks: list[SeriesBlock],
    mappings: dict[str, SeriesResult],
    episodes: dict[tuple[str, int, int], EpisodeResult],
) -> None:
    lines: list[str] = []
    m3u = ["#EXTM3U"]
    rows: list[list[object]] = []
    for block in blocks:
        found = [
            item for (key, _, _), item in episodes.items()
            if key == block.key and item.status == "encontrado" and item.sources
        ]
        if not found:
            continue
        lines.append("@" + block.title)
        for item in sorted(found, key=lambda value: (value.season, value.episode)):
            urls = list(dict.fromkeys(source.url for source in item.sources))
            lines.append(f"{item.season}\t{item.episode}\tdub\t" + ",".join(urls))
            for number, source in enumerate(item.sources, 1):
                display = f"{block.title} S{item.season:02}E{item.episode:02} — Fonte {number}"
                m3u.extend([
                    f'#EXTINF:-1 group-title="Séries" tvg-id="{item.tmdb_id}",{display}',
                    source.url,
                ])
                rows.append([
                    block.title, item.tmdb_id, item.season, item.episode,
                    source.language, number, source.url, item.api_title,
                ])
    atomic_write(output / "series-embedplayer.txt", "\n".join(lines) + ("\n" if lines else ""))
    atomic_write(output / "series-embedplayer.m3u", "\n".join(m3u) + "\n")
    with (output / "series-embedplayer.csv").open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["serie", "tmdb", "temporada", "episodio", "idioma", "fonte", "url", "titulo_no_provedor"])
        writer.writerows(rows)
    mapping_errors = [
        f"{item.title}\t{item.status}\t{item.error}".rstrip()
        for item in mappings.values() if item.status != "encontrado"
    ]
    episode_errors = [
        f"{item.title}\tS{item.season:02}E{item.episode:02}\t{item.status}\t{item.error}".rstrip()
        for item in episodes.values() if item.status not in {"encontrado", "indisponivel"}
    ]
    atomic_write(output / "series-sem-id.txt", "\n".join(mapping_errors) + ("\n" if mapping_errors else ""))
    atomic_write(output / "erros.txt", "\n".join(episode_errors) + ("\n" if episode_errors else ""))
    counts: dict[str, int] = {}
    for item in episodes.values():
        counts[item.status] = counts.get(item.status, 0) + 1
    summary = {
        "series_catalogo": len(blocks),
        "series_identificadas": sum(item.status == "encontrado" for item in mappings.values()),
        "episodios_processados": len(episodes),
        **counts,
        "gerado_em": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
    }
    atomic_write(output / "resumo.json", json.dumps(summary, ensure_ascii=False, indent=2) + "\n")


def apply_to_catalog(
    blocks: list[SeriesBlock], episodes: dict[tuple[str, int, int], EpisodeResult]
) -> int:
    block_by_file_title = {(block.file.name, block.title): block for block in blocks}
    changed_files = 0
    for file in sorted({block.file for block in blocks}):
        title = ""
        output: list[str] = []
        changed = False
        for raw in file.read_text(encoding="utf-8").splitlines():
            if raw.startswith("@"):
                title = raw[1:].strip()
                output.append(raw)
                continue
            match = EPISODE_LINE.fullmatch(raw)
            block = block_by_file_title.get((file.name, title))
            if not match or not block or match.group(3) != "dub":
                output.append(raw)
                continue
            result = episodes.get((block.key, int(match.group(1)), int(match.group(2))))
            if not result or result.status != "encontrado" or not result.sources:
                output.append(raw)
                continue
            fresh = [source.url for source in result.sources if source.language == "dub"]
            if not fresh:
                fresh = [source.url for source in result.sources]
            old = [value for value in match.group(4).split(",") if value]
            merged = list(dict.fromkeys(fresh + old))
            replacement = "\t".join(match.group(i) for i in range(1, 4)) + "\t" + ",".join(merged)
            output.append(replacement)
            changed = changed or replacement != raw
        if changed:
            atomic_write(file, "\n".join(output) + "\n")
            changed_files += 1
    return changed_files


def progress(label: str, completed: int, total: int, started: float, status: str) -> None:
    elapsed = max(time.monotonic() - started, 0.001)
    rate = completed / elapsed
    eta = (total - completed) / rate if rate else 0
    with PRINT_LOCK:
        print(
            f"{label}: {completed}/{total} | {rate:.1f}/s | ETA {eta / 60:.1f} min | {status}",
            flush=True,
        )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Gera fontes de séries por IDs exatos.")
    parser.add_argument("--workers", type=int, default=32)
    parser.add_argument("--delay", type=float, default=0.0)
    parser.add_argument("--limit-series", type=int, default=0)
    parser.add_argument("--limit-episodes", type=int, default=0)
    parser.add_argument("--serie", action="append", default=[], help="título exato")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--cache", type=Path, default=DEFAULT_OUTPUT / "cache.sqlite3")
    parser.add_argument("--sem-validar", action="store_true")
    parser.add_argument("--repetir-erros", action="store_true")
    parser.add_argument("--reprocessar", action="store_true")
    parser.add_argument("--aplicar", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.workers < 1 or args.workers > 96:
        raise SystemExit("--workers deve estar entre 1 e 96")
    blocks = catalog_series(set(args.serie) or None)
    if not blocks:
        raise SystemExit("Nenhuma série encontrada para os filtros informados.")
    providers = catalog_providers()
    execution_lock = acquire_execution_lock(args.output)
    db = open_cache(args.cache)
    mappings = load_series(db)
    mapping_pending = [
        block for block in blocks
        if args.reprocessar or block.key not in mappings
        or (args.repetir_erros and mappings[block.key].status == "erro")
    ]
    if args.limit_series:
        mapping_pending = mapping_pending[:args.limit_series]
    print(f"Catálogo: {len(blocks)} séries | identificações pendentes: {len(mapping_pending)}", flush=True)
    started = time.monotonic()
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = {pool.submit(map_series, block, providers): block for block in mapping_pending}
        for completed, future in enumerate(concurrent.futures.as_completed(futures), 1):
            item = future.result()
            old = mappings.get(item.key)
            if old and old.status == "encontrado" and item.status != "encontrado":
                item = old
            mappings[item.key] = item
            save_series(db, item)
            if completed % 20 == 0 or completed == len(futures):
                db.commit()
                progress("Séries", completed, len(futures), started, item.status)
    db.commit()

    episode_results = load_episodes(db)
    tasks: list[tuple[SeriesBlock, str, int, int]] = []
    for block in blocks:
        mapping = mappings.get(block.key)
        if not mapping or mapping.status != "encontrado":
            continue
        seen: set[tuple[int, int]] = set()
        for row in block.episodes:
            identity = (row.season, row.episode)
            if row.language != "dub" or identity in seen:
                continue
            seen.add(identity)
            old = episode_results.get((block.key, *identity))
            if args.reprocessar or old is None or (args.repetir_erros and old.status == "erro"):
                tasks.append((block, mapping.tmdb_id, *identity))
    if args.limit_episodes:
        tasks = tasks[:args.limit_episodes]
    print(f"Episódios pendentes: {len(tasks)}", flush=True)
    started = time.monotonic()
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = {
            pool.submit(resolve_episode, block, tmdb, season, episode,
                        not args.sem_validar, args.delay): (block, season, episode)
            for block, tmdb, season, episode in tasks
        }
        for completed, future in enumerate(concurrent.futures.as_completed(futures), 1):
            item = future.result()
            identity = (item.key, item.season, item.episode)
            old = episode_results.get(identity)
            if old and old.status == "encontrado" and item.status != "encontrado":
                item = old
            episode_results[identity] = item
            save_episode(db, item)
            if completed % 25 == 0 or completed == len(futures):
                db.commit()
                progress("Episódios", completed, len(futures), started, item.status)
    db.commit()
    write_outputs(args.output, blocks, mappings, episode_results)
    changed = apply_to_catalog(blocks, episode_results) if args.aplicar else 0
    found = sum(item.status == "encontrado" for item in episode_results.values())
    print(f"Concluído: {found} episódios encontrados | arquivos alterados: {changed}", flush=True)
    db.close()
    del execution_lock
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
