#!/usr/bin/env python3
"""Publica o id do IMDb de cada título do acervo, para as legendas.

O serviço de legendas (OpenSubtitles, pelo addon público do Stremio) só entende
IMDb, e o acervo só conhece o id do TMDB (vod/fichas.txt). Aqui se faz a ponte,
uma vez por título:

    TMDB /movie/ID/external_ids  e  /tv/ID/external_ids  ->  imdb_id

O resultado sai em vod/imdb/, em fragmentos pequenos — os apps abrem um filme e
só precisam de UMA linha, então baixam só o fragmento dele (uns 8 KB) em vez de
um arquivo de 1,5 MB:

    vod/imdb/f-NN.txt   filmes,  NN = id do TMDB % 100
    vod/imdb/s-NN.txt   séries
    linha: "id do TMDB<TAB>tt1234567"

O cache (arquivos-gerados/imdb.sqlite3) faz a rodada diária perguntar só pelos
títulos novos; o TMDB não muda de IMDb, então quem já tem não é consultado de
novo. Quem o TMDB não tem (404 ou sem imdb_id) é repescado depois de 30 dias.

    python3 gerar_imdb.py              o que falta
    python3 gerar_imdb.py --limite 200 só para conferir
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
from pathlib import Path

RAIZ = Path(__file__).resolve().parent
VOD = RAIZ / "vod"
SAIDA = VOD / "imdb"
CACHE = RAIZ / "arquivos-gerados" / "imdb.sqlite3"
CHAVE = "15d2ea6d0dc1d476efbca3eba2b9bbfb"
TMDB = "https://api.themoviedb.org/3"
FRAGMENTOS = 100
REPESCAGEM = 30 * 86400
IMDB = re.compile(r"tt\d{7,10}")

trava_ritmo = threading.Lock()
proximo = 0.0


def espaciar(intervalo: float = 0.03) -> None:
    """O TMDB aceita paralelismo mas corta rajada com 429."""
    global proximo
    with trava_ritmo:
        espera = proximo - time.monotonic()
        if espera > 0:
            time.sleep(espera)
        proximo = time.monotonic() + intervalo


def perguntar(tipo: str, tmdb: int) -> tuple[str, str]:
    """(estado, imdb): estado 'ok', 'nao_tem' ou 'erro'."""
    caminho = "movie" if tipo == "f" else "tv"
    url = f"{TMDB}/{caminho}/{tmdb}/external_ids?api_key={CHAVE}"
    for tentativa in range(4):
        espaciar()
        try:
            with urllib.request.urlopen(url, timeout=20) as r:
                imdb = str(json.loads(r.read().decode()).get("imdb_id") or "")
                return ("ok", imdb) if IMDB.fullmatch(imdb) else ("nao_tem", "")
        except urllib.error.HTTPError as erro:
            if erro.code == 404:
                return "nao_tem", ""
            time.sleep(2 * (tentativa + 1) if erro.code == 429 else 1 + tentativa)
        except Exception:
            time.sleep(1 + tentativa)
    return "erro", ""


def ids_do_acervo() -> set[tuple[str, int]]:
    saida: set[tuple[str, int]] = set()
    for linha in (VOD / "fichas.txt").read_text(encoding="utf-8").splitlines():
        campos = linha.split("\t")
        if len(campos) >= 3 and campos[0] in ("f", "s") and campos[2].isdigit():
            saida.add((campos[0], int(campos[2])))
    return saida


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("--workers", type=int, default=24)
    parser.add_argument("--limite", type=int, default=0)
    args = parser.parse_args()

    CACHE.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(CACHE, check_same_thread=False)
    db.execute("CREATE TABLE IF NOT EXISTS imdb (tipo TEXT NOT NULL, tmdb INTEGER NOT NULL, "
               "imdb TEXT NOT NULL DEFAULT '', quando INTEGER NOT NULL, PRIMARY KEY (tipo, tmdb))")
    conhecidos = {(t, i): (im, q) for t, i, im, q in db.execute("SELECT tipo,tmdb,imdb,quando FROM imdb")}
    acervo = ids_do_acervo()
    agora = int(time.time())
    faltam = sorted(k for k in acervo
                    if k not in conhecidos
                    or (not conhecidos[k][0] and agora - conhecidos[k][1] > REPESCAGEM))
    if args.limite:
        faltam = faltam[: args.limite]
    print(f"acervo: {len(acervo)} títulos com id do TMDB | já sabidos: {len(conhecidos)} | "
          f"a perguntar: {len(faltam)}", flush=True)

    trava = threading.Lock()
    comeco = time.monotonic()
    erros = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as piscina:
        futuros = {piscina.submit(perguntar, t, i): (t, i) for t, i in faltam}
        for feitos, futuro in enumerate(concurrent.futures.as_completed(futuros), 1):
            tipo, tmdb = futuros[futuro]
            estado, imdb = futuro.result()
            if estado == "erro":
                erros += 1  # não grava: a próxima rodada tenta de novo
            else:
                with trava:
                    db.execute("INSERT OR REPLACE INTO imdb (tipo,tmdb,imdb,quando) VALUES (?,?,?,?)",
                               (tipo, tmdb, imdb, agora))
                    conhecidos[(tipo, tmdb)] = (imdb, agora)
            if feitos % 500 == 0 or feitos == len(futuros):
                with trava:
                    db.commit()
                ritmo = feitos / max(time.monotonic() - comeco, 0.001)
                print(f"  [{feitos}/{len(futuros)}] {ritmo:.0f}/s · faltam "
                      f"{(len(futuros) - feitos) / max(ritmo, 0.001) / 60:.1f} min · erros {erros}", flush=True)
    db.commit()

    fragmentos: dict[str, list[tuple[int, str]]] = {}
    for (tipo, tmdb), (imdb, _) in conhecidos.items():
        if imdb and (tipo, tmdb) in acervo:
            fragmentos.setdefault(f"{tipo}-{tmdb % FRAGMENTOS:02d}", []).append((tmdb, imdb))
    SAIDA.mkdir(parents=True, exist_ok=True)
    escritos = set()
    for nome, linhas in fragmentos.items():
        corpo = "".join(f"{i}\t{im}\n" for i, im in sorted(linhas))
        caminho = SAIDA / f"{nome}.txt"
        if not caminho.exists() or caminho.read_text(encoding="utf-8") != corpo:
            caminho.write_text(corpo, encoding="utf-8")
        escritos.add(caminho.name)
    for velho in SAIDA.glob("*.txt"):
        if velho.name not in escritos:
            velho.unlink()
    total = sum(len(v) for v in fragmentos.values())
    print(f"vod/imdb: {total} títulos com IMDb em {len(escritos)} fragmentos "
          f"({sum(f.stat().st_size for f in SAIDA.glob('*.txt')) / 1e6:.2f} MB no total)", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
