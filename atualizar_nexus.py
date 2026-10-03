#!/usr/bin/env python3
"""Integra a NexusTV Play como fonte PRIMÁRIA de filmes.

Baixa o catálogo completo de nexustvplay.bbroot.com, resolve cada URL via
API em paralelo e insere como PRIMEIRA fonte dub= nos arquivos vod/filmes-*.txt.
Filmes novos (ainda não cadastrados) são adicionados automaticamente no
arquivo correto, em ordem alfabética.

O cache SQLite em arquivos-gerados/nexus/cache.sqlite3 permite retomar a
execução e evita consultas redundantes à API.

Uso típico
----------
    python3 atualizar_nexus.py                   # fluxo completo
    python3 atualizar_nexus.py --sem-baixar      # reutiliza catálogo local
    python3 atualizar_nexus.py --sem-aplicar     # resolve sem gravar arquivos
    python3 atualizar_nexus.py --workers 40      # aumenta paralelismo
    python3 atualizar_nexus.py --limite 500      # testa com 500 filmes
"""

from __future__ import annotations

import argparse
import contextlib
import json
import os
import re
import sqlite3
import sys
import tempfile
import threading
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from scripts.corrigir_catalogo_tvbox import corrigir_linha

# ---------------------------------------------------------------------------
# Constantes
# ---------------------------------------------------------------------------

ROOT = Path(__file__).resolve().parent
VOD_DIR = ROOT / "vod"
GENERATED = ROOT / "arquivos-gerados" / "nexus"
CACHE_DB = GENERATED / "cache.sqlite3"
CATALOG_CACHE = GENERATED / "catalogo.json"
REPORT_PATH = GENERATED / "relatorio.json"
LOCK_FILE = GENERATED / "execucao.lock"

CATALOG_BASE = "https://nexustvplay.bbroot.com/filmes-json/page-{:03d}.json"
API_URL = "https://fallback1.nexustvplay.bbroot.com/api/play/{id}?t"

# Domínio R2 das URLs retornadas pela API — usado para detectar
# fontes Nexus já inseridas (idempotência).
NEXUS_R2_MARKER = "r2.dev/m/"

USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
)
DEFAULT_WORKERS = 30
CATALOG_WORKERS = 20
REQUEST_TIMEOUT = 20

PRINT_LOCK = threading.Lock()


# ---------------------------------------------------------------------------
# Utilitários gerais
# ---------------------------------------------------------------------------

def log(msg: str) -> None:
    with PRINT_LOCK:
        print(msg, flush=True)


def atomic_write(path: Path, content: str) -> None:
    """Grava content em path de forma atômica (evita arquivo corrompido)."""
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=".tmp_")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(content)
        os.replace(tmp, path)
    except Exception:
        with contextlib.suppress(OSError):
            os.unlink(tmp)
        raise


def acquire_lock() -> None:
    """Impede duas execuções simultâneas."""
    GENERATED.mkdir(parents=True, exist_ok=True)
    if LOCK_FILE.exists():
        try:
            pid = int(LOCK_FILE.read_text().strip())
            # Verifica se o PID ainda está ativo
            os.kill(pid, 0)
            raise SystemExit(
                f"Outra execução em andamento (PID {pid}). "
                f"Se não houver, apague {LOCK_FILE} e tente novamente."
            )
        except (ValueError, ProcessLookupError, PermissionError):
            pass  # PID morreu — lock obsoleto, seguro continuar
    LOCK_FILE.write_text(str(os.getpid()))


def release_lock() -> None:
    LOCK_FILE.unlink(missing_ok=True)


# ---------------------------------------------------------------------------
# Normalização de títulos
# ---------------------------------------------------------------------------

def normalize(text: str) -> str:
    """Normaliza um título para comparação: sem acentos, minúsculas, sem pontuação."""
    # Remove sufixo de ano: "Título (2020)" → "Título"
    text = re.sub(r"\s*\(\d{4}\)\s*$", "", text.strip())
    # Remove acentos via NFD
    nfkd = unicodedata.normalize("NFD", text)
    text = "".join(c for c in nfkd if unicodedata.category(c) != "Mn")
    text = text.lower()
    # Remove pontuação (mantém alfanumérico e espaços)
    text = re.sub(r"[^\w\s]", " ", text)
    # Colapsa espaços
    return re.sub(r"\s+", " ", text).strip()


def extract_year(title: str) -> tuple[str, str]:
    """Separa 'Título (2020)' → ('Título', '2020'). Sem ano → ('Título', '')."""
    m = re.search(r"\((\d{4})\)\s*$", title.strip())
    if m:
        return title[: m.start()].strip(), m.group(1)
    return title.strip(), ""


def first_letter_key(title: str) -> str:
    """Retorna a letra do arquivo vod correspondente ao título."""
    clean = normalize(title)
    if not clean:
        return "#"
    first = clean[0]
    if first.isalpha():
        return first.upper()
    return "#"


# ---------------------------------------------------------------------------
# Download do catálogo NexusTV
# ---------------------------------------------------------------------------

def _fetch_page(page: int) -> list[dict] | None:
    """Baixa uma página do catálogo e retorna a lista de filmes (ou None se vazia/erro)."""
    url = CATALOG_BASE.format(page)
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT) as resp:
            data = json.loads(resp.read().decode("utf-8", "replace"))
        if not isinstance(data, list) or not data:
            return None
        return data
    except (urllib.error.HTTPError, urllib.error.URLError, json.JSONDecodeError):
        return None


def download_catalog(force: bool = False) -> list[dict]:
    """
    Baixa todas as páginas do catálogo NexusTV em paralelo.

    Se force=False e houver cache local válido, usa o cache.
    Retorna a lista consolidada de todos os filmes.
    """
    if not force and CATALOG_CACHE.exists():
        log(f"Catálogo local encontrado: {CATALOG_CACHE}")
        try:
            movies = json.loads(CATALOG_CACHE.read_text(encoding="utf-8"))
            log(f"  → {len(movies):,} filmes carregados do cache")
            return movies
        except (json.JSONDecodeError, OSError):
            log("  → Cache inválido, baixando novamente…")

    log("Baixando catálogo NexusTV Play (busca paralela de páginas)…")
    all_movies: list[dict] = []
    page = 1
    empty_streak = 0
    MAX_EMPTY = 3  # Para ao encontrar 3 páginas vazias seguidas

    # Fase 1: descobre até onde ir (sequencial nas primeiras páginas)
    # Fase 2: baixa em paralelo usando o range descoberto
    # Abordagem: tenta em blocos de CATALOG_WORKERS páginas por vez

    with ThreadPoolExecutor(max_workers=CATALOG_WORKERS) as pool:
        while empty_streak < MAX_EMPTY:
            pages_batch = list(range(page, page + CATALOG_WORKERS))
            futures = {pool.submit(_fetch_page, p): p for p in pages_batch}
            batch_results: dict[int, list[dict] | None] = {}
            for fut in as_completed(futures):
                p = futures[fut]
                batch_results[p] = fut.result()

            got_any = False
            for p in sorted(pages_batch):
                result = batch_results.get(p)
                if result:
                    all_movies.extend(result)
                    got_any = True
                    empty_streak = 0
                else:
                    empty_streak += 1
                    if empty_streak >= MAX_EMPTY:
                        break

            if got_any:
                log(f"  Páginas {pages_batch[0]:03d}-{pages_batch[-1]:03d} → "
                    f"{len(all_movies):,} filmes acumulados")
            page += CATALOG_WORKERS

    # Elimina duplicatas por ID
    seen: set[int] = set()
    unique: list[dict] = []
    for m in all_movies:
        mid = m.get("id") or m.get("tmdb")
        if mid and mid not in seen:
            seen.add(mid)
            unique.append(m)

    GENERATED.mkdir(parents=True, exist_ok=True)
    CATALOG_CACHE.write_text(
        json.dumps(unique, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    log(f"Catálogo salvo: {len(unique):,} filmes únicos → {CATALOG_CACHE}")
    return unique


# ---------------------------------------------------------------------------
# Cache SQLite de URLs resolvidas
# ---------------------------------------------------------------------------

def open_cache(path: Path) -> sqlite3.Connection:
    path.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(str(path), check_same_thread=False)
    db.execute("PRAGMA journal_mode=WAL")
    db.execute("PRAGMA synchronous=NORMAL")
    db.execute("PRAGMA busy_timeout=5000")
    db.execute("""
        CREATE TABLE IF NOT EXISTS nexus_urls (
            tmdb       TEXT    NOT NULL PRIMARY KEY,
            url        TEXT    NOT NULL DEFAULT '',
            error      TEXT    NOT NULL DEFAULT '',
            updated_at INTEGER NOT NULL
        )
    """)
    db.commit()
    return db


def load_cache(db: sqlite3.Connection) -> dict[str, str]:
    """Retorna {tmdb_id: url} para todos os filmes já resolvidos com sucesso."""
    return {
        row[0]: row[1]
        for row in db.execute(
            "SELECT tmdb, url FROM nexus_urls WHERE url != ''"
        )
    }


def load_failed(db: sqlite3.Connection) -> set[str]:
    """TMDBs que já foram tentados e não têm URL."""
    return {
        row[0]
        for row in db.execute(
            "SELECT tmdb FROM nexus_urls WHERE url = '' AND error != ''"
        )
    }


def save_result(db: sqlite3.Connection, tmdb: str, url: str, error: str) -> None:
    db.execute(
        """INSERT INTO nexus_urls (tmdb, url, error, updated_at)
           VALUES (?, ?, ?, ?)
           ON CONFLICT(tmdb) DO UPDATE SET
             url=excluded.url, error=excluded.error,
             updated_at=excluded.updated_at""",
        (tmdb, url, error, int(time.time())),
    )


# ---------------------------------------------------------------------------
# Resolução de URLs via API Nexus
# ---------------------------------------------------------------------------

_DB_LOCK = threading.Lock()
_KV_LIMIT_REACHED = threading.Event()


def resolve_url(tmdb: str, max_retries: int = 3) -> tuple[str, str]:
    """
    Chama a API Nexus. Tenta de novo se tomar 502/503.
    Retorna (url, error) — um deles sempre vazio.
    """
    if _KV_LIMIT_REACHED.is_set():
        return "", "KV_LIMIT_REACHED"

    api = API_URL.format(id=tmdb)
    
    for attempt in range(max_retries):
        if _KV_LIMIT_REACHED.is_set():
            return "", "KV_LIMIT_REACHED"
            
        req = urllib.request.Request(api, headers={"User-Agent": USER_AGENT})
        try:
            with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT) as resp:
                raw_data = resp.read().decode("utf-8", "replace")
                data = json.loads(raw_data)
                
            if "KV put() limit exceeded" in raw_data:
                _KV_LIMIT_REACHED.set()
                return "", "KV_LIMIT_REACHED"
                
            url = data.get("url", "").strip()
            err = data.get("error", "").strip()
            
            # Se for proxy de DMCA, resolvemos o link direto
            if url and "proxy-video?url=" in url:
                parsed = urllib.parse.urlparse(url)
                qs = urllib.parse.parse_qs(parsed.query)
                if "url" in qs:
                    url = qs["url"][0]

            if url:
                return url, ""
            return "", err or "sem_url"
            
        except urllib.error.HTTPError as e:
            if e.code in (500, 502, 503, 504, 429):
                # Tenta ler o corpo para ver se é o erro de KV
                try:
                    err_body = e.read().decode("utf-8", "replace")
                    if "KV put() limit exceeded" in err_body:
                        _KV_LIMIT_REACHED.set()
                        return "", "KV_LIMIT_REACHED"
                except Exception:
                    pass
                
                # Exponential backoff: 1s, 2s, 4s
                time.sleep(1.0 * (2 ** attempt))
                continue
            return "", f"HTTP {e.code}"
        except urllib.error.URLError as e:
            time.sleep(1.0 * (2 ** attempt))
            continue
        except Exception as e:
            return "", f"{type(e).__name__}: {e}"
            
    return "", "TIMEOUT_RETRIES"


def resolve_all(
    movies: list[dict],
    db: sqlite3.Connection,
    workers: int,
    retry_failed: bool = False,
) -> dict[str, str]:
    """
    Resolve URLs para todos os filmes em paralelo.
    Usa cache SQLite — só chama a API para filmes ainda não tentados.
    Retorna {tmdb_id: url} para os filmes com URL disponível.
    """
    cached_urls = load_cache(db)
    cached_failed = load_failed(db)

    pending = []
    for movie in movies:
        tmdb = str(movie.get("id") or movie.get("tmdb") or "")
        if not tmdb:
            continue
        if tmdb in cached_urls:
            continue
        if tmdb in cached_failed and not retry_failed:
            continue
        pending.append(tmdb)

    log(f"\nResolução de URLs:")
    log(f"  Cache: {len(cached_urls):,} com URL | {len(cached_failed):,} indisponíveis")
    log(f"  Pendentes para API: {len(pending):,} filmes")

    if not pending:
        log("  → Tudo em cache, pulando chamadas à API.")
        return cached_urls

    done = 0
    found = 0
    missing = 0
    started = time.monotonic()
    batch_buffer: list[tuple[str, str, str]] = []
    FLUSH_INTERVAL = 20

    def flush_buffer() -> None:
        nonlocal batch_buffer
        if not batch_buffer:
            return
        with _DB_LOCK:
            for row in batch_buffer:
                save_result(db, *row)
            db.commit()
        batch_buffer = []

    _KV_LIMIT_REACHED.clear()

    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures = {pool.submit(resolve_url, tmdb): tmdb for tmdb in pending}
        for fut in as_completed(futures):
            tmdb = futures[fut]
            url, error = fut.result()
            
            if error == "KV_LIMIT_REACHED":
                log("\n⚠️ ATENÇÃO: A API Nexus atingiu o limite DIÁRIO de operações no Cloudflare KV!")
                log("   Interrompendo a busca. Todo o progresso foi salvo.")
                log("   Execute este script novamente amanhã para continuar de onde parou.\n")
                pool.shutdown(wait=False, cancel_futures=True)
                break
                
            done += 1

            with _DB_LOCK:
                batch_buffer.append((tmdb, url, error))
                if url:
                    cached_urls[tmdb] = url

            if url:
                found += 1
            else:
                missing += 1

            if done % FLUSH_INTERVAL == 0 or done == len(pending):
                flush_buffer()
                elapsed = max(time.monotonic() - started, 0.001)
                rate = done / elapsed
                eta = (len(pending) - done) / rate if rate else 0
                log(
                    f"  [{done:,}/{len(pending):,}] "
                    f"{rate:.1f}/s · ETA {eta/60:.1f} min · "
                    f"✓ {found:,} URLs · ✗ {missing:,} indisponíveis"
                )

    flush_buffer()
    log(f"\n  Total com URL: {len(cached_urls):,} | Indisponíveis: {missing:,}")
    return cached_urls


# ---------------------------------------------------------------------------
# Leitura e indexação dos arquivos VOD existentes
# ---------------------------------------------------------------------------

def parse_vod_sources(line: str) -> tuple[str, dict[str, list[str]], list[str]]:
    """
    Analisa uma linha do VOD:
      'Título\tdub=url1,url2\tleg=url1\ttmdb=123'
    Retorna (titulo, {'dub': [...], 'leg': [...]}, ['tmdb=123']).
    """
    parts = line.split("\t")
    title = parts[0].strip()
    langs: dict[str, list[str]] = {}
    extras: list[str] = []
    for field in parts[1:]:
        field = field.strip()
        if not field:
            continue
        m = re.match(r"^(dub|leg)=(.+)$", field)
        if m:
            lang = m.group(1)
            urls = [u.strip() for u in m.group(2).split(",") if u.strip()]
            langs[lang] = urls
        else:
            extras.append(field)
    return title, langs, extras


def build_vod_line(title: str, langs: dict[str, list[str]], extras: list[str]) -> str:
    """Reconstrói uma linha VOD a partir do título, fontes e extras preservados."""
    parts = [title]
    for lang in ("dub", "leg"):
        urls = langs.get(lang, [])
        if urls:
            parts.append(f"{lang}=" + ",".join(urls))
    # Os clientes antigos tratam todo campo chave=valor como versão de vídeo.
    # tmdb=123 fazia o TV Box chamar take(-1), travando a letra inteira.
    # Os IDs já ficam preservados no catálogo/cache Nexus, fora das fatias.
    parts.extend(e for e in extras if not re.match(r"^(tmdb|imdb)=", e))
    return corrigir_linha("\t".join(parts))[0]


def load_vod_files() -> dict[str, list[tuple[int, str]]]:
    """
    Lê todos os arquivos vod/filmes-*.txt.
    Retorna {filename: [(line_idx, raw_line), ...]}.
    """
    result: dict[str, list[tuple[int, str]]] = {}
    for path in sorted(VOD_DIR.glob("filmes-*.txt")):
        lines = path.read_text(encoding="utf-8").splitlines()
        result[path.name] = [(i, line) for i, line in enumerate(lines) if line.strip()]
    return result


def build_title_index(
    vod_files: dict[str, list[tuple[int, str]]]
) -> dict[tuple[str, str], list[tuple[str, int]]]:
    """
    Constrói índice para cruzamento:
      (norm_title, year) → [(filename, line_idx), ...]
      (norm_title, '')   → [(filename, line_idx), ...]

    A chave com ano vazio agrupa todas as linhas com esse título,
    independente de terem ou não ano.
    """
    index: dict[tuple[str, str], list[tuple[str, int]]] = defaultdict(list)
    for fname, lines in vod_files.items():
        for idx, raw in lines:
            title_raw, _, _ = parse_vod_sources(raw)
            title_clean, year = extract_year(title_raw)
            norm = normalize(title_clean)
            if not norm:
                continue
            # Com ano
            if year:
                index[(norm, year)].append((fname, idx))
            # Sem ano (chave genérica)
            index[(norm, "")].append((fname, idx))
    return index


# ---------------------------------------------------------------------------
# Aplicação das atualizações
# ---------------------------------------------------------------------------

def nexus_already_present(urls: list[str]) -> bool:
    """Verifica se a fonte Nexus (R2) já está na lista de URLs."""
    return any(NEXUS_R2_MARKER in u for u in urls)


def append_nexus(urls: list[str], nexus_url: str) -> list[str]:
    """
    Insere nexus_url como PRIMEIRO elemento (fonte primária), sem duplicar.
    Remove qualquer versão anterior do Nexus que pudesse existir para colocá-la no início.
    """
    filtered = [u for u in urls if NEXUS_R2_MARKER not in u]
    return filtered + [nexus_url]


def apply_updates(
    movies: list[dict],
    tmdb_to_url: dict[str, str],
    vod_files: dict[str, list[tuple[int, str]]],
    title_index: dict[tuple[str, str], list[tuple[str, int]]],
    dry_run: bool = False,
) -> dict:
    """
    Para cada filme com URL resolvida:
      1. Localiza a entrada correspondente nos arquivos VOD
      2. Insere a URL Nexus como primeira fonte dub=
      3. Filmes novos são adicionados no arquivo correto

    Retorna estatísticas da operação.
    """
    # Trabalha sobre uma cópia mutável das linhas por arquivo
    # {filename: {line_idx: new_raw_line}}
    updates: dict[str, dict[int, str]] = defaultdict(dict)
    new_entries: dict[str, list[str]] = defaultdict(list)  # {filename: [lines]}

    stats = {
        "atualizados": 0,
        "ja_tinham_nexus": 0,
        "novos_adicionados": 0,
        "sem_url": 0,
        "sem_match": 0,
    }

    for movie in movies:
        tmdb = str(movie.get("id") or movie.get("tmdb") or "")
        if not tmdb:
            continue
        nexus_url = tmdb_to_url.get(tmdb, "")
        if not nexus_url:
            stats["sem_url"] += 1
            continue

        nome = str(movie.get("nome") or "").strip()
        ano = str(movie.get("ano") or "").strip()
        if not nome:
            continue

        norm = normalize(nome)

        # Tenta encontrar nos arquivos VOD existentes
        # Prioridade: (título_normalizado, ano) → (título_normalizado, '')
        matches: list[tuple[str, int]] = []
        if ano:
            matches = title_index.get((norm, ano), [])
        if not matches:
            matches = title_index.get((norm, ""), [])

        if matches:
            matched_any = False
            for fname, idx in matches:
                # Recupera a linha original do arquivo
                file_lines = dict(vod_files[fname])
                raw = file_lines.get(idx, "")
                if not raw:
                    continue

                title_raw, langs, extras = parse_vod_sources(raw)
                dub_urls = langs.get("dub", [])

                new_dub = append_nexus(dub_urls, nexus_url)
                if new_dub == dub_urls:
                    stats["ja_tinham_nexus"] += 1
                    matched_any = True
                    continue

                # Insere Nexus como PRIMEIRA fonte dub= (primária)
                langs["dub"] = append_nexus(dub_urls, nexus_url)
                new_raw = build_vod_line(title_raw, langs, extras)
                updates[fname][idx] = new_raw
                stats["atualizados"] += 1
                matched_any = True

            if not matched_any:
                # Todas as entradas já tinham Nexus
                pass
        else:
            # Filme novo — determina o arquivo de destino
            stats["sem_match"] += 1
            letter = first_letter_key(nome)
            fname = f"filmes-{letter}.txt"
            # Cria a entrada com ano se disponível
            if ano:
                entry_title = f"{nome} ({ano})"
            else:
                entry_title = nome
            # Novos filmes não têm tmdb extras para preservar, adiciona vazio
            new_line = build_vod_line(entry_title, {"dub": [nexus_url]}, [])
            new_entries[fname].append(new_line)
            stats["novos_adicionados"] += 1

    if dry_run:
        log("\n[--sem-aplicar] Nenhum arquivo foi gravado.")
        return stats

    # ---- Grava os arquivos atualizados ----
    files_changed = 0
    for fname, line_updates in updates.items():
        if not line_updates:
            continue
        path = VOD_DIR / fname
        original_lines = [raw for _, raw in vod_files.get(fname, [])]
        new_lines = list(original_lines)
        for idx, new_raw in line_updates.items():
            if idx < len(new_lines):
                new_lines[idx] = new_raw
        atomic_write(path, "\n".join(new_lines) + "\n")
        files_changed += 1

    # ---- Adiciona filmes novos ----
    for fname, new_lines in new_entries.items():
        path = VOD_DIR / fname
        if path.exists():
            existing = path.read_text(encoding="utf-8").splitlines()
        else:
            existing = []
        # Insere novos entries em ordem alfabética (pelo título normalizado)
        all_lines = existing + new_lines
        # Ordena usando normalize como chave (stable sort preserva ordem de iguais)
        all_lines.sort(key=lambda l: normalize(l.split("\t")[0]))
        atomic_write(path, "\n".join(l for l in all_lines if l.strip()) + "\n")
        files_changed += 1

    log(f"\n  Arquivos atualizados: {files_changed}")
    return stats


# ---------------------------------------------------------------------------
# Relatório
# ---------------------------------------------------------------------------

def write_report(stats: dict, total_movies: int, total_with_url: int) -> None:
    report = {
        "gerado_em": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "catalogo_nexus": total_movies,
        "com_url_resolvida": total_with_url,
        "atualizacoes": stats,
    }
    GENERATED.mkdir(parents=True, exist_ok=True)
    REPORT_PATH.write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    log(f"\nRelatório salvo: {REPORT_PATH}")


# ---------------------------------------------------------------------------
# Argumentos de linha de comando
# ---------------------------------------------------------------------------

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--sem-baixar",
        action="store_true",
        help="Não baixa o catálogo; usa o cache local (arquivos-gerados/nexus/catalogo.json)",
    )
    parser.add_argument(
        "--sem-aplicar",
        action="store_true",
        help="Resolve URLs mas NÃO grava os arquivos VOD (modo diagnóstico)",
    )
    parser.add_argument(
        "--retry-falhos",
        action="store_true",
        help="Tenta novamente filmes que deram erro na última execução",
    )
    parser.add_argument(
        "--workers",
        type=int,
        default=DEFAULT_WORKERS,
        metavar="N",
        help=f"Workers paralelos para a API (padrão: {DEFAULT_WORKERS})",
    )
    parser.add_argument(
        "--limite",
        type=int,
        default=0,
        metavar="N",
        help="Processa apenas os N primeiros filmes (0 = todos; útil para testes)",
    )
    parser.add_argument(
        "--catalogo",
        type=Path,
        default=None,
        metavar="PATH",
        help="Caminho para um JSON de catálogo existente (substitui o download)",
    )
    return parser.parse_args()


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    args = parse_args()

    acquire_lock()
    try:
        return _run(args)
    finally:
        release_lock()


def _run(args: argparse.Namespace) -> int:
    t0 = time.monotonic()
    log("=" * 60)
    log("  NexusTV Play — Atualização de Fontes de Filmes")
    log("=" * 60)

    # 1. Catálogo
    if args.catalogo and args.catalogo.exists():
        log(f"\nCarregando catálogo de {args.catalogo}…")
        movies = json.loads(args.catalogo.read_text(encoding="utf-8"))
        log(f"  → {len(movies):,} filmes")
    else:
        movies = download_catalog(force=not args.sem_baixar)

    if args.limite:
        movies = movies[: args.limite]
        log(f"  (limitado a {len(movies):,} filmes para teste)")

    # 2. Resolução de URLs via API
    log(f"\nAbrindo cache em {CACHE_DB}…")
    db = open_cache(CACHE_DB)
    tmdb_to_url = resolve_all(movies, db, args.workers, args.retry_falhos)
    db.close()

    total_with_url = len(tmdb_to_url)
    log(f"\n  {total_with_url:,} filmes com URL Nexus disponível")

    # 3. Leitura dos arquivos VOD existentes
    log("\nLendo arquivos vod/filmes-*.txt…")
    vod_files = load_vod_files()
    total_vod_entries = sum(len(lines) for lines in vod_files.values())
    log(f"  → {len(vod_files)} arquivos · {total_vod_entries:,} entradas")

    log("\nConstruindo índice de títulos…")
    title_index = build_title_index(vod_files)
    log(f"  → {len(title_index):,} chaves de busca")

    # 4. Aplicação das atualizações
    log(f"\n{'[MODO DIAGNÓSTICO] ' if args.sem_aplicar else ''}Aplicando atualizações…")
    stats = apply_updates(
        movies, tmdb_to_url, vod_files, title_index, dry_run=args.sem_aplicar
    )

    # 5. Relatório
    elapsed = time.monotonic() - t0
    log("\n" + "=" * 60)
    log("  RESUMO")
    log("=" * 60)
    log(f"  Catálogo Nexus:         {len(movies):,} filmes")
    log(f"  Com URL resolvida:      {total_with_url:,}")
    log(f"  Sem URL (indisponível): {stats['sem_url']:,}")
    log(f"  Atualizados no VOD:     {stats['atualizados']:,}")
    log(f"  Já tinham Nexus:        {stats['ja_tinham_nexus']:,}")
    log(f"  Filmes novos adicionados:{stats['novos_adicionados']:,}")
    log(f"  Sem correspondência:    {stats['sem_match'] - stats['novos_adicionados']:,}")
    log(f"  Tempo total:            {elapsed:.1f}s")
    log("=" * 60)

    write_report(stats, len(movies), total_with_url)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
