#!/usr/bin/env python3
"""Extrator e Injetor de fontes do NexEmbed como FONTE RESERVA no SaimoPlayer.

O NexEmbed serve vídeos HLS (.m3u8) de alta velocidade via CDN Cloudflare (comprarebom.xyz)
com CORS aberto (*), sem tokens temporários e sem travas de reprodução.

Todas as fontes extraídas entram SEMPRE como FONTE RESERVA (no final da lista de fontes),
preservando estritamente a fonte pub- (Cloudflare R2) como a 1ª opção primária absoluta.

Uso:
    python3 atualizar_nexembed.py --dry-run
    python3 atualizar_nexembed.py --so-filmes --aplicar
    python3 atualizar_nexembed.py --so-series --aplicar
    python3 atualizar_nexembed.py --aplicar
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sqlite3
import sys
import threading
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

ROOT = Path(__file__).resolve().parent
VOD = ROOT / "vod"
CACHE_DIR = ROOT / "arquivos-gerados" / "nexembed"
IMDB_DB = ROOT / "arquivos-gerados" / "imdb.sqlite3"

AGENTE = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0 Safari/537.36"
NEX_HEADERS = {
    "User-Agent": AGENTE,
    "Referer": "https://nexembed.xyz/",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
}


def norm_str(s: str) -> str:
    s = urllib.parse.unquote(s)
    s = re.sub(r"[\(\[]\d{4}[\)\]]", "", s)
    s = unicodedata.normalize("NFKD", s).encode("ASCII", "ignore").decode("utf-8").lower()
    return re.sub(r"[^a-z0-9]", "", s)


def pedir_html(url: str, tentativas: int = 3, timeout: int = 12) -> str | None:
    for i in range(tentativas):
        try:
            req = urllib.request.Request(url, headers=NEX_HEADERS)
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return resp.read().decode("utf-8", errors="replace")
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
        except Exception:
            pass
        time.sleep(0.5 * (i + 1))
    return None


def extrair_stream(embed_url: str) -> str | None:
    """Extrai a URL final .m3u8 a partir de uma URL de embed do nexembed."""
    html = pedir_html(embed_url)
    if not html:
        return None
    m = re.search(r'data-src=["\']([^"\']+)["\']', html)
    if not m:
        return None
    player_url = m.group(1)

    player_html = pedir_html(player_url)
    if not player_html:
        return None

    cfg_m = re.search(r'<script id=["\']player-config["\'] type=["\']application/json["\']>(\{.*?\})</script>', player_html)
    if not cfg_m:
        return None

    try:
        cfg = json.loads(cfg_m.group(1))
        urls = cfg.get("urls") or []
        if urls and isinstance(urls, list) and urls[0]:
            return urls[0].strip()
    except Exception:
        pass
    return None


def valida_hls(url: str, timeout: int = 10) -> bool:
    """Verifica se o link HLS responde HTTP 200/206 e contém cabeçalho #EXTM3U."""
    try:
        req = urllib.request.Request(url, headers={"User-Agent": AGENTE, "Range": "bytes=0-1024"})
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            if resp.status not in (200, 206):
                return False
            data = resp.read(512)
            return b"#EXTM3U" in data
    except Exception:
        return False


# MARK: - Catálogo e Mapeamento

def carregar_fichas() -> tuple[dict[str, list[str]], dict[str, list[str]]]:
    """Retorna tmdb_para_titulos_filmes e tmdb_para_titulos_series."""
    fichas_path = VOD / "fichas.txt"
    filmes_map: dict[str, list[str]] = {}
    series_map: dict[str, list[str]] = {}
    if not fichas_path.exists():
        return filmes_map, series_map

    for line in fichas_path.read_text(encoding="utf-8", errors="ignore").splitlines():
        parts = line.split("\t")
        if len(parts) >= 3 and parts[0] in ("f", "s"):
            tipo, tit, tmdb = parts[0], parts[1], parts[2]
            if tipo == "f":
                filmes_map.setdefault(tmdb, []).append(tit)
            else:
                series_map.setdefault(tmdb, []).append(tit)
    return filmes_map, series_map


def carregar_imdb_map() -> dict[str, str]:
    """Mapeia imdb_id -> tmdb_id a partir de arquivos-gerados/imdb.sqlite3."""
    res = {}
    if IMDB_DB.exists():
        con = sqlite3.connect(IMDB_DB)
        cur = con.cursor()
        for tipo, tmdb, imdb in cur.execute("SELECT tipo, tmdb, imdb FROM imdb WHERE imdb != ''"):
            if imdb:
                res[imdb] = str(tmdb)
        con.close()
    return res


# MARK: - Extração de Filmes

def raspar_filmes(limite: int = 0, workers: int = 16) -> dict[str, dict]:
    """Raspa todos os filmes do sitemap do NexEmbed e extrai o stream HLS."""
    print("Obtendo sitemap de filmes do NexEmbed...")
    sm_html = pedir_html("https://nexembed.xyz/sitemap-filmes.xml")
    if not sm_html:
        print("Erro ao obter sitemap-filmes.xml")
        return {}

    root = ET.fromstring(sm_html)
    urls = [loc.text for loc in root.findall(".//{http://www.sitemaps.org/schemas/sitemap/0.9}loc") if loc.text]
    if limite > 0:
        urls = urls[:limite]

    print(f"Total de filmes a processar: {len(urls)}")
    imdb_map = carregar_imdb_map()
    fichas_filmes, _ = carregar_fichas()

    resultados: dict[str, dict] = {}
    lock = threading.Lock()

    def processar_filme(watch_url: str):
        # Ex: https://nexembed.xyz/assistir/filme/tt7286456
        ident = watch_url.split("/")[-1].strip()
        embed_url = f"https://nexembed.xyz/embed/{ident}"
        stream = extrair_stream(embed_url)
        if not stream:
            return

        # Pega título da página de exibição
        page_html = pedir_html(watch_url)
        title = ident
        if page_html:
            m = re.search(r'<h1[^>]*class=["\']watch-title["\'][^>]*>(.*?)</h1>', page_html)
            if m:
                raw_t = m.group(1).strip()
                title = re.sub(r"^Assistir\s+", "", raw_t).strip()

        # Descobre tmdb_id
        tmdb_id = imdb_map.get(ident, "")
        if not tmdb_id and ident.isdigit():
            tmdb_id = ident

        if not valida_hls(stream):
            return

        with lock:
            resultados[ident] = {
                "ident": ident,
                "tmdb_id": tmdb_id,
                "title": title,
                "stream": stream,
                "watch_url": watch_url
            }
            print(f"  [FILME OK] {title} ({ident}) -> {stream}")

    with ThreadPoolExecutor(max_workers=workers) as pool:
        futs = [pool.submit(processar_filme, u) for u in urls]
        for f in as_completed(futs):
            pass

    print(f"Filmes extraídos com sucesso: {len(resultados)}")
    return resultados


# MARK: - Extração de Séries

def raspar_series(limite: int = 0, workers: int = 16) -> dict[str, dict]:
    """Raspa todas as séries do sitemap do NexEmbed e seus episódios."""
    print("Obtendo sitemaps de séries e animes do NexEmbed...")
    urls = []
    for sm_url in ["https://nexembed.xyz/sitemap-series.xml", "https://nexembed.xyz/sitemap-animes.xml"]:
        sm_html = pedir_html(sm_url)
        if sm_html:
            root = ET.fromstring(sm_html)
            urls.extend([loc.text for loc in root.findall(".//{http://www.sitemaps.org/schemas/sitemap/0.9}loc") if loc.text])

    if limite > 0:
        urls = urls[:limite]

    print(f"Total de séries e animes no sitemap: {len(urls)}")
    fichas_filmes, fichas_series = carregar_fichas()

    series_data: dict[str, dict] = {}
    episodes_queue: list[tuple[str, str, int, int]] = []

    # 1. Coleta a grade de episódios de cada série
    for u in urls:
        # Ex: https://nexembed.xyz/assistir/serie/95350/1/1
        parts = u.split("/")
        tmdb_id = parts[5] if len(parts) >= 6 else ""
        if not tmdb_id:
            continue

        html = pedir_html(u)
        if not html:
            continue

        title_m = re.search(r'<h1[^>]*class=["\']watch-title["\'][^>]*>(.*?)</h1>', html)
        raw_t = title_m.group(1).strip() if title_m else tmdb_id
        serie_title = re.sub(r"^Assistir\s+", "", raw_t)
        serie_title = re.sub(r"\s*\[S\d+E\d+\]\s*$", "", serie_title).strip()

        ep_m = re.search(r"const episodesBySeason = (\{.*?\});", html)
        if not ep_m:
            continue

        try:
            seasons_dict = json.loads(ep_m.group(1))
        except Exception:
            continue

        series_data[tmdb_id] = {
            "tmdb_id": tmdb_id,
            "title": serie_title,
            "episodes": {}
        }

        for s_str, eps_list in seasons_dict.items():
            try:
                s_num = int(s_str)
            except ValueError:
                continue
            for ep_obj in eps_list:
                e_num = ep_obj.get("episode")
                if e_num:
                    episodes_queue.append((tmdb_id, serie_title, s_num, int(e_num)))

    print(f"Total de episódios a extrair: {len(episodes_queue)}")

    lock = threading.Lock()

    def processar_episodio(item: tuple[str, str, int, int]):
        tmdb_id, stitle, s, e = item
        embed_url = f"https://nexembed.xyz/embed/{tmdb_id}/{s}/{e}?type=serie"
        stream = extrair_stream(embed_url)
        if not stream:
            return

        if not valida_hls(stream):
            return

        with lock:
            series_data[tmdb_id]["episodes"][(s, e)] = stream
            print(f"  [SÉRIE OK] {stitle} S{s:02d}E{e:02d} -> {stream}")

    with ThreadPoolExecutor(max_workers=workers) as pool:
        futs = [pool.submit(processar_episodio, item) for item in episodes_queue]
        for f in as_completed(futs):
            pass

    total_eps_extraidos = sum(len(v["episodes"]) for v in series_data.values())
    print(f"Séries processadas: {len(series_data)}, total episódios com stream válido: {total_eps_extraidos}")
    return series_data


# MARK: - Injeção nos Arquivos VOD (Como Reserva)

def aplicar_filmes_vod(filmes_data: dict[str, dict], dry_run: bool = False):
    """Aplica as fontes de filmes extraídas aos arquivos vod/filmes-*.txt como reserva."""
    fichas_filmes, _ = carregar_fichas()
    
    # Mapeia títulos para a stream extraída
    # chave: norm_str(titulo) -> stream
    stream_por_titulo: dict[str, str] = {}
    for ident, info in filmes_data.items():
        stream = info["stream"]
        tmdb = info.get("tmdb_id")
        t_direto = info.get("title", "")
        if t_direto:
            stream_por_titulo[norm_str(t_direto)] = stream
        if tmdb and tmdb in fichas_filmes:
            for t in fichas_filmes[tmdb]:
                stream_por_titulo[norm_str(t)] = stream

    print(f"Filmes indexados para injeção: {len(stream_por_titulo)} títulos.")

    modificados = 0
    injetados = 0

    for path in sorted(VOD.glob("filmes-*.txt")):
        linhas = path.read_text(encoding="utf-8", errors="ignore").splitlines()
        novas_linhas = []
        alterado = False

        for linha in linhas:
            if not linha.strip() or linha.startswith("#"):
                novas_linhas.append(linha)
                continue

            partes = linha.split("\t")
            titulo = partes[0].strip()
            norm_t = norm_str(titulo)

            if norm_t in stream_por_titulo:
                stream_nex = stream_por_titulo[norm_t]
                # Encontra o campo dub= ou cria
                dub_idx = -1
                for idx, p in enumerate(partes[1:], 1):
                    if p.startswith("dub="):
                        dub_idx = idx
                        break

                if dub_idx != -1:
                    dub_content = partes[dub_idx][4:]
                    urls = [u.strip() for u in dub_content.split(",") if u.strip()]
                    
                    # REGRA CRÍTICA: Manter o primeiro link (pub-) intacto como primário
                    if stream_nex not in urls:
                        urls.append(stream_nex)
                        partes[dub_idx] = f"dub={','.join(urls)}"
                        alterado = True
                        injetados += 1
                else:
                    partes.append(f"dub={stream_nex}")
                    alterado = True
                    injetados += 1

                novas_linhas.append("\t".join(partes))
            else:
                novas_linhas.append(linha)

        if alterado:
            modificados += 1
            if not dry_run:
                path.write_text("\n".join(novas_linhas) + "\n", encoding="utf-8")

    print(f"Filmes: {injetados} fontes reserva injetadas em {modificados} arquivos. (dry_run={dry_run})")


def aplicar_series_vod(series_data: dict[str, dict], dry_run: bool = False):
    """Aplica as fontes de séries extraídas aos arquivos vod/series-*-*.txt como reserva."""
    _, fichas_series = carregar_fichas()

    # Mapeia: (norm_str(titulo_serie), s, e) -> stream
    streams_por_ep: dict[tuple[str, int, int], str] = {}
    for tmdb_id, sinfo in series_data.items():
        titulos = [sinfo["title"]]
        if tmdb_id in fichas_series:
            titulos.extend(fichas_series[tmdb_id])

        for (s, e), stream in sinfo["episodes"].items():
            for t in titulos:
                streams_por_ep[(norm_str(t), s, e)] = stream

    print(f"Episódios de séries indexados para injeção: {len(streams_por_ep)}")

    modificados = 0
    injetados = 0

    for path in sorted(VOD.glob("series-*-*.txt")):
        linhas = path.read_text(encoding="utf-8", errors="ignore").splitlines()
        novas_linhas = []
        alterado = False
        serie_atual = ""

        for linha in linhas:
            if linha.startswith("@"):
                serie_atual = linha[1:].split("\t")[0].strip()
                novas_linhas.append(linha)
                continue

            if not serie_atual or not linha.strip():
                novas_linhas.append(linha)
                continue

            partes = linha.split("\t")
            if len(partes) >= 4 and partes[2] in ("dub", "leg"):
                try:
                    s_num = int(partes[0])
                    e_num = int(partes[1])
                    audio = partes[2]
                    key = (norm_str(serie_atual), s_num, e_num)

                    if key in streams_por_ep:
                        stream_nex = streams_por_ep[key]
                        urls = [u.strip() for u in partes[3].split(",") if u.strip()]

                        # REGRA CRÍTICA: Manter o primeiro link (pub-) intacto como primário
                        if stream_nex not in urls:
                            urls.append(stream_nex)
                            partes[3] = ",".join(urls)
                            alterado = True
                            injetados += 1
                            novas_linhas.append("\t".join(partes))
                            continue
                except ValueError:
                    pass

            novas_linhas.append(linha)

        if alterado:
            modificados += 1
            if not dry_run:
                path.write_text("\n".join(novas_linhas) + "\n", encoding="utf-8")

    print(f"Séries: {injetados} episódios atualizados com fontes reserva em {modificados} arquivos. (dry_run={dry_run})")


# MARK: - Principal

def main():
    parser = argparse.ArgumentParser(description="Extrator e Injetor de fontes NexEmbed para o SaimoPlayer")
    parser.add_argument("--so-filmes", action="store_true", help="Processar apenas filmes")
    parser.add_argument("--so-series", action="store_true", help="Processar apenas séries")
    parser.add_argument("--limite", type=int, default=0, help="Limite de títulos a processar")
    parser.add_argument("--workers", type=int, default=16, help="Número de threads simultâneas")
    parser.add_argument("--usar-cache", action="store_true", help="Reutiliza dados extraídos salvos em arquivos-gerados/nexembed")
    parser.add_argument("--aplicar", action="store_true", help="Grava as alterações nos arquivos VOD")
    parser.add_argument("--dry-run", action="store_true", help="Apenas simula sem salvar nos arquivos VOD")
    args = parser.parse_args()

    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    cache_filmes_p = CACHE_DIR / "filmes.json"
    cache_series_p = CACHE_DIR / "series.json"

    dry_run = args.dry_run or (not args.aplicar)

    if not args.so_series:
        if args.usar_cache and cache_filmes_p.exists():
            print("Carregando filmes do cache local...")
            filmes = json.loads(cache_filmes_p.read_text(encoding="utf-8"))
        else:
            filmes = raspar_filmes(limite=args.limite, workers=args.workers)
            if filmes:
                cache_filmes_p.write_text(json.dumps(filmes, indent=2, ensure_ascii=False), encoding="utf-8")
        aplicar_filmes_vod(filmes, dry_run=dry_run)

    if not args.so_filmes:
        if args.usar_cache and cache_series_p.exists():
            print("Carregando séries do cache local...")
            raw_s = json.loads(cache_series_p.read_text(encoding="utf-8"))
            series = {}
            for tmdb, sinfo in raw_s.items():
                s_copy = dict(sinfo)
                s_copy["episodes"] = {
                    (int(k.split(":")[0]), int(k.split(":")[1])): u
                    for k, u in sinfo["episodes"].items()
                }
                series[tmdb] = s_copy
        else:
            series = raspar_series(limite=args.limite, workers=args.workers)
            if series:
                serializable = {}
                for tmdb, sinfo in series.items():
                    s_copy = dict(sinfo)
                    s_copy["episodes"] = {f"{s}:{e}": u for (s, e), u in sinfo["episodes"].items()}
                    serializable[tmdb] = s_copy
                cache_series_p.write_text(json.dumps(serializable, indent=2, ensure_ascii=False), encoding="utf-8")
        aplicar_series_vod(series, dry_run=dry_run)

    print("\nProcesso concluído com sucesso!")
    if dry_run:
        print("Modo de simulação (dry-run). Nenhuma modificação foi gravada em disco. Execute com --aplicar para efetivar.")


if __name__ == "__main__":
    main()
