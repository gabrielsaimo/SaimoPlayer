#!/usr/bin/env python3
"""Fontes de embed (MGEB dublado / NHD legendado) para todo o acervo.

Os dois servidores respondem por id do TMDB, que o acervo já guarda em
vod/fichas.txt. Por isso nada é perguntado a ninguém: cada link é montado
direto do id, sem busca por título.

    filme dublado     https://mgeb.top/embed/<tmdb>
    filme legendado   https://nhdapi.com/embed/movie/<tmdb>
    série dublada     https://mgeb.top/embed/<tmdb>/<temporada>/<episódio>
    série legendada   https://nhdapi.com/embed/tv/<tmdb>/<temporada>/<episódio>

A saída segue o formato das outras fontes (vod/fenix, vod/redeflix):

    vod/mgeb/links-filmes.txt   título<TAB>dub=url<TAB>leg=url
    vod/mgeb/links-series.txt   @título<TAB>ano  e depois  T<TAB>E<TAB>dub|leg<TAB>url

Também grava um CSV com tudo em arquivos-gerados/mgeb/ para conferência.

    python3 atualizar_mgeb.py                  # tudo
    python3 atualizar_mgeb.py --so-filmes | --so-series
    python3 atualizar_mgeb.py --verificar      # testa cada link (lento)
"""

from __future__ import annotations

import argparse
import csv
import re
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent
VOD = ROOT / "vod"
SAIDA = VOD / "mgeb"
RELATORIO = ROOT / "arquivos-gerados" / "mgeb"

MGEB = "https://mgeb.top/embed"
NHD = "https://nhdapi.com/embed"
AGENTE = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
          "(KHTML, like Gecko) Chrome/140.0 Safari/537.36")


def url_filme(tmdb: int) -> tuple[str, str]:
    return f"{MGEB}/{tmdb}", f"{NHD}/movie/{tmdb}"


def url_episodio(tmdb: int, temporada: int, episodio: int) -> tuple[str, str]:
    return f"{MGEB}/{tmdb}/{temporada}/{episodio}", f"{NHD}/tv/{tmdb}/{temporada}/{episodio}"


def sem_ano(titulo: str) -> str:
    return re.sub(r"\s*\(\d{4}\)\s*$", "", titulo).strip()


def ler_fichas() -> dict[tuple[str, str], int]:
    """(tipo, título) -> id do TMDB, do arquivo que os apps já leem."""
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
    """Título -> {ano, eps {(temporada, número)}}, dos pedaços publicados."""
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


def responde(url: str) -> bool:
    for tentativa in range(5):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": AGENTE})
            with urllib.request.urlopen(req, timeout=6) as r:
                return 200 <= r.status < 400
        except urllib.error.HTTPError as erro:
            if erro.code == 429:  # limite do servidor: espera e tenta de novo
                time.sleep(2 * (tentativa + 1))
                continue
            return False
        except Exception:
            return False
    return False


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--so-filmes", action="store_true")
    ap.add_argument("--so-series", action="store_true")
    ap.add_argument("--verificar", action="store_true", help="descarta links que não respondem")
    ap.add_argument("--workers", type=int, default=6)
    args = ap.parse_args()

    SAIDA.mkdir(parents=True, exist_ok=True)
    RELATORIO.mkdir(parents=True, exist_ok=True)
    fichas = ler_fichas()
    csv_linhas: list[list] = []

    cache: dict[str, bool] = {}

    def sondar(urls: list[str], rotulo: str) -> None:
        """Testa as URLs em paralelo, mostrando o andamento ao vivo."""
        urls = [u for u in dict.fromkeys(urls) if u not in cache]
        feitas = ok = 0
        with ThreadPoolExecutor(args.workers) as grupo:
            for url, bom in zip(urls, grupo.map(responde, urls)):
                cache[url] = bom
                feitas += 1
                ok += bom
                if feitas % 200 == 0 or feitas == len(urls):
                    print(f"[{rotulo}] {feitas}/{len(urls)} testados · {ok} respondem", flush=True)

    def vale(url: str) -> bool:
        return cache.get(url, False) if args.verificar else True

    if not args.so_series:
        if args.verificar:
            alvo = []
            for titulo in filmes_do_acervo():
                tmdb = fichas.get(("f", titulo)) or fichas.get(("f", sem_ano(titulo)))
                if tmdb:
                    alvo += list(url_filme(tmdb))
            sondar(alvo, "filmes")
        linhas, sem_id = [], 0
        for titulo in filmes_do_acervo():
            tmdb = fichas.get(("f", titulo)) or fichas.get(("f", sem_ano(titulo)))
            if not tmdb:
                sem_id += 1
                continue
            dub, leg = url_filme(tmdb)
            campos = [titulo]
            if vale(dub):
                campos.append(f"dub={dub}")
                csv_linhas.append(["filme", titulo, tmdb, "", "", "dub", dub])
            if vale(leg):
                campos.append(f"leg={leg}")
                csv_linhas.append(["filme", titulo, tmdb, "", "", "leg", leg])
            if len(campos) > 1:
                linhas.append("\t".join(campos))
        (SAIDA / "links-filmes.txt").write_text("\n".join(linhas) + "\n", encoding="utf-8")
        print(f"filmes: {len(linhas)} com fonte · {sem_id} sem id do TMDB")

    if not args.so_filmes:
        series = series_do_acervo()
        # Com --verificar, só o primeiro episódio de cada série é testado: se o
        # servidor tem a série, vale para os demais episódios.
        sonda: dict[tuple[int, str], bool] = {}
        if args.verificar:
            alvo = []
            for titulo in series:
                tmdb = fichas.get(("s", titulo)) or fichas.get(("s", sem_ano(titulo)))
                if tmdb and series[titulo]["eps"]:
                    t0, e0 = sorted(series[titulo]["eps"])[0]
                    alvo += list(url_episodio(tmdb, t0, e0))
            sondar(alvo, "séries")
            for titulo in series:
                tmdb = fichas.get(("s", titulo)) or fichas.get(("s", sem_ano(titulo)))
                if tmdb and series[titulo]["eps"]:
                    t0, e0 = sorted(series[titulo]["eps"])[0]
                    d0, l0 = url_episodio(tmdb, t0, e0)
                    sonda[(tmdb, "dub")] = cache.get(d0, False)
                    sonda[(tmdb, "leg")] = cache.get(l0, False)
        linhas, sem_id, total_eps = [], 0, 0
        for titulo in sorted(series):
            tmdb = fichas.get(("s", titulo)) or fichas.get(("s", sem_ano(titulo)))
            if not tmdb:
                sem_id += 1
                continue
            bloco = []
            for t, e in sorted(series[titulo]["eps"]):
                dub, leg = url_episodio(tmdb, t, e)
                for lingua, url in (("dub", dub), ("leg", leg)):
                    if not args.verificar or sonda.get((tmdb, lingua)):
                        bloco.append(f"{t}\t{e}\t{lingua}\t{url}")
                        csv_linhas.append(["serie", titulo, tmdb, t, e, lingua, url])
                total_eps += 1
            if bloco:
                linhas.append(f"@{titulo}\t{series[titulo]['ano']}")
                linhas.extend(bloco)
        (SAIDA / "links-series.txt").write_text("\n".join(linhas) + "\n", encoding="utf-8")
        print(f"séries: {total_eps} episódios · {sem_id} séries sem id do TMDB")

    with (RELATORIO / "mgeb.csv").open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["tipo", "titulo", "tmdb_id", "temporada", "episodio", "idioma", "url"])
        w.writerows(csv_linhas)
    print(f"saída: {SAIDA} · relatório: {RELATORIO / 'mgeb.csv'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
