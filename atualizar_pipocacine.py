#!/usr/bin/env python3
"""Extrator de fontes MP4 direto do PipocaCine para todo o acervo.

Este script obtém as URLs diretas de MP4 do servidor PipocaCine.
1. Utiliza `/api/embed/...` para descobrir se o título existe de forma mais leve.
2. Caso exista, abre a página de embed para extrair o array `videoSources`.
3. Segue o redirecionamento dos arquivos (`/stream.php?t=...` ou `/api/vod_redirect.php...`)
   para capturar o link final do vídeo (`https://cdn99xn...`).

Se o servidor ou Cloudflare bloquear por excesso de requisições (erros 429, 403, 503, 520),
o script para imediatamente e avisa o usuário.
"""

import argparse
import csv
import json
import re
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent
VOD = ROOT / "vod"
SAIDA = VOD / "pipocacine"
RELATORIO = ROOT / "arquivos-gerados" / "pipocacine"

PIPO_BASE = "https://pipocacine.lat"
AGENTE = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
          "(KHTML, like Gecko) Chrome/140.0 Safari/537.36")

# Para evitar seguir redirects infinitos e capturar apenas a Location
class NoRedir(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None

def criar_opener():
    return urllib.request.build_opener(NoRedir())

def sem_ano(titulo: str) -> str:
    return re.sub(r"\s*\(\d{4}\)\s*$", "", titulo).strip()

def ler_fichas() -> dict[tuple[str, str], int]:
    ids = {}
    for linha in (VOD / "fichas.txt").read_text(encoding="utf-8").splitlines():
        campos = linha.split("\t")
        if len(campos) < 3 or campos[0] not in ("f", "s"):
            continue
        try:
            ids[(campos[0], campos[1])] = int(campos[2])
        except ValueError:
            pass
    return ids

def filmes_do_acervo() -> list[str]:
    titulos = []
    for arquivo in sorted(VOD.glob("filmes-*.txt")):
        for linha in arquivo.read_text(encoding="utf-8").splitlines():
            titulo = linha.split("\t", 1)[0]
            if titulo:
                titulos.append(titulo)
    return list(dict.fromkeys(titulos))

def series_do_acervo() -> dict[str, dict]:
    anos = {}
    for indice in VOD.glob("series-*.txt"):
        if re.search(r"series-.+-\d+\.txt$", indice.name):
            continue
        for linha in indice.read_text(encoding="utf-8").splitlines():
            campos = linha.split("\t")
            if campos and campos[0]:
                anos[campos[0]] = campos[1] if len(campos) > 1 else ""
    series: dict[str, dict] = {}
    for pedaco in sorted(VOD.glob("series-*-*.txt")):
        atual = None
        for linha in pedaco.read_text(encoding="utf-8").splitlines():
            if linha.startswith("@"):
                atual = linha[1:].split("\t")[0].strip()
                series.setdefault(atual, {"ano": anos.get(atual, ""), "eps": set()})
                continue
            if atual is None:
                continue
            campos = linha.split("\t")
            try:
                series[atual]["eps"].add((int(campos[0]), int(campos[1])))
            except (ValueError, IndexError):
                pass
    return series

stop_event = threading.Event()

def obter_links_diretos(url_embed: str, opener) -> dict[str, str]:
    # Faz parsing da página do player
    req = urllib.request.Request(url_embed, headers={"User-Agent": AGENTE})
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            html = r.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        if e.code in (429, 403, 503, 520):
            print(f"\n[BLOQUEIO] Servidor ou Cloudflare bloqueou! Erro {e.code} em {url_embed}")
            stop_event.set()
        return {}
    except Exception:
        return {}

    match = re.search(r'var videoSources\s*=\s*(\[.*?\]);', html)
    if not match:
        return {}
    
    try:
        sources = json.loads(match.group(1))
    except json.JSONDecodeError:
        return {}

    resultados = {}
    for s in sources:
        label = str(s.get("label", "")).upper()
        src = str(s.get("src", ""))
        if not src or "Indisponível" in label:
            continue
        
        idioma = "dub" if "DUB" in label else "leg"
        # Pode ter múltiplas qualidades, vamos gravar a primeira que achar de cada tipo
        if idioma in resultados:
            continue
            
        url_redir = src if src.startswith("http") else f"{PIPO_BASE}{src}"
        req_redir = urllib.request.Request(url_redir, headers={"User-Agent": AGENTE, "Referer": url_embed})
        try:
            res = opener.open(req_redir, timeout=10)
        except urllib.error.HTTPError as e:
            if e.code in (301, 302, 303, 307):
                location = e.headers.get("Location")
                if location:
                    resultados[idioma] = location
            elif e.code in (429, 403, 503, 520):
                print(f"\n[BLOQUEIO] Servidor ou Cloudflare bloqueou! Erro {e.code} em {url_redir}")
                stop_event.set()
        except Exception:
            pass

    return resultados

def processar_filme(titulo: str, tmdb: int, opener) -> tuple[str, dict[str, str]]:
    if stop_event.is_set():
        return titulo, {}
        
    api_url = f"{PIPO_BASE}/api/embed/{tmdb}"
    req = urllib.request.Request(api_url, headers={"User-Agent": AGENTE})
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            data = json.loads(r.read())
            if "error" in data:
                return titulo, {}
            embed_url = data.get("embed_url")
    except urllib.error.HTTPError as e:
        if e.code in (429, 403, 503, 520):
            print(f"\n[BLOQUEIO] Servidor ou Cloudflare bloqueou! Erro {e.code} na API do filme {tmdb}")
            stop_event.set()
        return titulo, {}
    except Exception:
        return titulo, {}

    if not embed_url:
        embed_url = f"{PIPO_BASE}/embed/{tmdb}"
        
    links = obter_links_diretos(embed_url, opener)
    return titulo, links

def processar_episodio(titulo: str, tmdb: int, t: int, e: int, opener) -> tuple[str, int, int, dict[str, str]]:
    if stop_event.is_set():
        return titulo, t, e, {}
        
    api_url = f"{PIPO_BASE}/api/embed/{tmdb}/{t}/{e}"
    req = urllib.request.Request(api_url, headers={"User-Agent": AGENTE})
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            data = json.loads(r.read())
            if "error" in data:
                return titulo, t, e, {}
            embed_url = data.get("embed_url")
    except urllib.error.HTTPError as err:
        if err.code in (429, 403, 503, 520):
            print(f"\n[BLOQUEIO] Servidor ou Cloudflare bloqueou! Erro {err.code} na API da série {tmdb}")
            stop_event.set()
        return titulo, t, e, {}
    except Exception:
        return titulo, t, e, {}

    if not embed_url:
        embed_url = f"{PIPO_BASE}/embed/{tmdb}/{t}/{e}"
        
    links = obter_links_diretos(embed_url, opener)
    return titulo, t, e, links

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--so-filmes", action="store_true")
    ap.add_argument("--so-series", action="store_true")
    ap.add_argument("--workers", type=int, default=2, help="Taxa baixa de requests para não bloquear")
    args = ap.parse_args()

    SAIDA.mkdir(parents=True, exist_ok=True)
    RELATORIO.mkdir(parents=True, exist_ok=True)
    fichas = ler_fichas()
    
    opener = criar_opener()

    # == Filmes ==
    if not args.so_series:
        print("Iniciando filmes...")
        achados = []
        with ThreadPoolExecutor(args.workers) as exe:
            futuros = []
            for titulo in filmes_do_acervo():
                tmdb = fichas.get(("f", titulo)) or fichas.get(("f", sem_ano(titulo)))
                if tmdb:
                    futuros.append(exe.submit(processar_filme, titulo, tmdb, opener))
            
            feitas = 0
            for f in futuros:
                if stop_event.is_set():
                    exe.shutdown(wait=False, cancel_futures=True)
                    break
                titulo, links = f.result()
                feitas += 1
                if links:
                    achados.append((titulo, links))
                if feitas % 50 == 0:
                    print(f"Filmes: {feitas}/{len(futuros)} checados, {len(achados)} encontrados", flush=True)

        if achados:
            linhas = []
            csv_linhas = []
            for titulo, links in achados:
                campos = [titulo]
                for lang in ("dub", "leg"):
                    if lang in links:
                        campos.append(f"{lang}={links[lang]}")
                        csv_linhas.append(["filme", titulo, "", "", lang, links[lang]])
                linhas.append("\t".join(campos))
            
            (SAIDA / "links-filmes.txt").write_text("\n".join(linhas) + "\n", encoding="utf-8")
            with (RELATORIO / "pipocacine-filmes.csv").open("w", newline="", encoding="utf-8") as f:
                w = csv.writer(f)
                w.writerow(["tipo", "titulo", "temporada", "episodio", "idioma", "url"])
                w.writerows(csv_linhas)
        print(f"Filmes concluídos. Total achados: {len(achados)}")

    if stop_event.is_set():
        print("Parada solicitada por bloqueio. Finalizando script.")
        return 1

    # == Séries ==
    if not args.so_filmes:
        print("Iniciando séries...")
        series = series_do_acervo()
        achados_eps = {}
        
        with ThreadPoolExecutor(args.workers) as exe:
            futuros = []
            for titulo in sorted(series):
                tmdb = fichas.get(("s", titulo)) or fichas.get(("s", sem_ano(titulo)))
                if tmdb:
                    for t, e in sorted(series[titulo]["eps"]):
                        futuros.append(exe.submit(processar_episodio, titulo, tmdb, t, e, opener))
                        
            feitas = 0
            for f in futuros:
                if stop_event.is_set():
                    exe.shutdown(wait=False, cancel_futures=True)
                    break
                titulo, t, e, links = f.result()
                feitas += 1
                if links:
                    achados_eps.setdefault(titulo, []).append((t, e, links))
                if feitas % 50 == 0:
                    print(f"Episódios: {feitas}/{len(futuros)} checados", flush=True)

        if achados_eps:
            linhas = []
            csv_linhas = []
            for titulo in sorted(achados_eps):
                linhas.append(f"@{titulo}\t{series[titulo]['ano']}")
                for t, e, links in achados_eps[titulo]:
                    for lang in ("dub", "leg"):
                        if lang in links:
                            linhas.append(f"{t}\t{e}\t{lang}\t{links[lang]}")
                            csv_linhas.append(["serie", titulo, t, e, lang, links[lang]])
            (SAIDA / "links-series.txt").write_text("\n".join(linhas) + "\n", encoding="utf-8")
            
            with (RELATORIO / "pipocacine-series.csv").open("w", newline="", encoding="utf-8") as f:
                w = csv.writer(f)
                w.writerow(["tipo", "titulo", "temporada", "episodio", "idioma", "url"])
                w.writerows(csv_linhas)
        print(f"Séries concluídas. Total de séries com eps: {len(achados_eps)}")
        
    if stop_event.is_set():
        print("Parada solicitada por bloqueio. Processo incompleto salvo.")
        return 1

    return 0

if __name__ == "__main__":
    sys.exit(main())
