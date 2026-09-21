#!/usr/bin/env python3
"""Descobre o gênero de cada título do acervo e publica a lista.

O catálogo não tem gênero: as listas de origem trazem nome e endereço, nada
mais. Quem quiser filtrar por Ação, Terror ou Animação precisa que alguém
pergunte ao TMDB — e perguntar por trinta e quatro mil títulos, em cada
aparelho, a cada abertura, é uma tela que nunca abre.

Então a pergunta é feita aqui, uma vez, e o resultado publicado em
`vod/generos.txt`. Os aplicativos leem um arquivo e filtram na memória.

O cache é o que torna isto repetível: a primeira passada demora, as seguintes
só perguntam pelos títulos que entraram. Ele fica em `arquivos-gerados/`, fora
do Git, como o do resolvedor de fontes.

    ./gerar_generos.py                  tudo o que falta
    ./gerar_generos.py --limite 200     uma amostra, para conferir
"""
from __future__ import annotations

import argparse
import concurrent.futures
import json
import re
import sqlite3
import sys
import threading
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

RAIZ = Path(__file__).resolve().parent
VOD = RAIZ / "vod"
SAIDA = VOD / "generos.txt"
FICHAS = VOD / "fichas.txt"
CAPA_BASE = "https://image.tmdb.org/t/p/w342"
CACHE = RAIZ / "arquivos-gerados" / "generos.sqlite3"

CHAVE = "15d2ea6d0dc1d476efbca3eba2b9bbfb"
TMDB = "https://api.themoviedb.org/3"

# Os nomes que o TMDB usa em português, por id. Fixos aqui de propósito: são
# dezenove e não mudam, e assim o gerador não gasta uma chamada para buscá-los.
NOMES = {
    28: "Ação", 12: "Aventura", 16: "Animação", 35: "Comédia", 80: "Crime",
    99: "Documentário", 18: "Drama", 10751: "Família", 14: "Fantasia",
    36: "História", 27: "Terror", 10402: "Música", 9648: "Mistério",
    10749: "Romance", 878: "Ficção científica", 10770: "TV", 53: "Suspense",
    10752: "Guerra", 37: "Faroeste",
    10759: "Ação e aventura", 10762: "Infantil", 10763: "Notícias",
    10764: "Reality", 10765: "Ficção e fantasia", 10766: "Novela",
    10767: "Talk show", 10768: "Guerra e política",
}

trava = threading.Lock()


def limpo(titulo: str) -> tuple[str, str]:
    """Nome sem o ano, e o ano, que é o que desfaz refilmagem."""
    achado = re.search(r"\((\d{4})\)\s*$", titulo)
    ano = achado.group(1) if achado else ""
    nome = re.sub(r"\s*\(\d{4}\)\s*$", "", titulo).strip()
    return nome, ano


def pedir(url: str, tentativas: int = 3):
    for tentativa in range(tentativas):
        try:
            with urllib.request.urlopen(url, timeout=20) as r:
                return json.loads(r.read().decode())
        except urllib.error.HTTPError as erro:
            # 429 é o TMDB pedindo calma; o resto não melhora tentando de novo.
            if erro.code != 429:
                return None
            time.sleep(2 + tentativa)
        except Exception:
            time.sleep(1 + tentativa)
    return None


def ficha_de(titulo: str, serie: bool) -> dict | None:
    """O que o TMDB sabe deste título: id, pôster e gêneros.

    Buscar a capa pelo nome, em cada aparelho, é lento e erra: nomes iguais
    devolvem o filme errado, e o acervo tem trinta mil deles. Guardando o id e
    o caminho do pôster aqui, o aplicativo pede a imagem direto pelo endereço,
    sem procurar nada — e quem não tem id fica sem, com um lugar marcado na
    tela em vez de uma busca que nunca acerta.
    """
    nome, ano = limpo(titulo)
    if not nome:
        return None
    tipo = "tv" if serie else "movie"
    campo = "first_air_date_year" if serie else "year"
    url = (f"{TMDB}/search/{tipo}?api_key={CHAVE}&language=pt-BR"
           f"&query={urllib.parse.quote(nome)}")
    if ano:
        url += f"&{campo}={ano}"
    dados = pedir(url)
    if not dados:
        return None
    resultados = dados.get("results") or []
    if not resultados and ano:
        # Ano errado na lista de origem é comum; sem ele ainda se acha.
        dados = pedir(f"{TMDB}/search/{tipo}?api_key={CHAVE}&language=pt-BR"
                      f"&query={urllib.parse.quote(nome)}")
        resultados = (dados or {}).get("results") or []
    if not resultados:
        return {}
    melhor = resultados[0]
    ids = melhor.get("genre_ids") or []
    return {
        "id": melhor.get("id") or 0,
        "capa": melhor.get("poster_path") or "",
        "generos": [NOMES[i] for i in ids if i in NOMES],
    }


def banco() -> sqlite3.Connection:
    CACHE.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(CACHE, check_same_thread=False)
    db.execute("CREATE TABLE IF NOT EXISTS generos ("
               "chave TEXT PRIMARY KEY, valor TEXT NOT NULL)")
    # A ficha traz id e pôster além dos gêneros; a tabela antiga fica como
    # está para não perder o que já foi perguntado se esta execução parar.
    db.execute("CREATE TABLE IF NOT EXISTS fichas ("
               "chave TEXT PRIMARY KEY, tmdb INTEGER NOT NULL DEFAULT 0, "
               "capa TEXT NOT NULL DEFAULT '', generos TEXT NOT NULL DEFAULT '')")
    db.commit()
    return db


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--limite", type=int, default=0)
    parser.add_argument("--workers", type=int, default=32)
    args = parser.parse_args()

    linhas = (VOD / "busca.txt").read_text(encoding="utf-8").splitlines()
    titulos: list[tuple[str, bool]] = []
    vistos = set()
    for linha in linhas:
        campos = linha.split("\t")
        if len(campos) < 2 or not campos[0]:
            continue
        chave = (campos[0], campos[1] == "s")
        if chave in vistos:
            continue
        vistos.add(chave)
        titulos.append(chave)

    db = banco()
    prontos = {c for (c,) in db.execute("SELECT chave FROM fichas")}
    faltam = [(t, s) for t, s in titulos
              if f"{'s' if s else 'f'}|{t}" not in prontos]
    if args.limite:
        faltam = faltam[: args.limite]

    print(f"acervo: {len(titulos)} títulos | já sabidos: {len(prontos)} | "
          f"a perguntar: {len(faltam)}", flush=True)

    feitos = 0
    comeco = time.time()
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as piscina:
        futuros = {piscina.submit(ficha_de, t, s): (t, s) for t, s in faltam}
        for futuro in concurrent.futures.as_completed(futuros):
            titulo, serie = futuros[futuro]
            feitos += 1
            try:
                ficha = futuro.result()
            except Exception:
                ficha = None
            if ficha is None:
                continue
            chave = f"{'s' if serie else 'f'}|{titulo}"
            generos = "\t".join(ficha.get("generos") or [])
            with trava:
                db.execute("INSERT OR REPLACE INTO fichas (chave, tmdb, capa, generos) "
                           "VALUES (?, ?, ?, ?)",
                           (chave, ficha.get("id") or 0, ficha.get("capa") or "", generos))
                db.execute("INSERT OR REPLACE INTO generos (chave, valor) VALUES (?, ?)",
                           (chave, generos))
                if feitos % 200 == 0:
                    db.commit()
            if feitos % 250 == 0 or feitos == len(faltam):
                ritmo = feitos / max(1e-6, time.time() - comeco)
                resta = (len(faltam) - feitos) / max(ritmo, 1e-6) / 60
                print(f"  [{feitos}/{len(faltam)}] {ritmo:.0f}/s · faltam {resta:.1f} min",
                      flush=True)
    db.commit()

    saida = ["# Gênero de cada título, do TMDB. Gerado por gerar_generos.py — não editar à mão.",
             "# tipo\ttítulo\tgêneros separados por vírgula"]
    fichas = ["# Ficha de cada título: id do TMDB, pôster e gêneros.",
              "# Gerado por gerar_generos.py — não editar à mão.",
              f"capa: {CAPA_BASE}",
              "# tipo\ttítulo\tid\tpôster\tgêneros"]
    quantos = 0
    com_capa = 0
    contagem: dict[str, int] = {}
    for chave, tmdb, capa, valor in db.execute(
            "SELECT chave, tmdb, capa, generos FROM fichas ORDER BY chave"):
        tipo, titulo = chave.split("|", 1)
        generos = [g for g in (valor or "").split("\t") if g]
        if not generos and not capa and not tmdb:
            continue
        fichas.append(f"{tipo}\t{titulo}\t{tmdb or ''}\t{capa or ''}\t{','.join(generos)}")
        if capa:
            com_capa += 1
        if generos:
            saida.append(f"{tipo}\t{titulo}\t{','.join(generos)}")
            quantos += 1
            for g in generos:
                contagem[g] = contagem.get(g, 0) + 1
    SAIDA.write_text("\n".join(saida) + "\n", encoding="utf-8")
    FICHAS.write_text("\n".join(fichas) + "\n", encoding="utf-8")
    print(f"{FICHAS.name}: {len(fichas) - 4} títulos, {com_capa} com pôster, "
          f"{FICHAS.stat().st_size / 1024 / 1024:.1f} MB")

    top = " · ".join(f"{g} {n}" for g, n in
                     sorted(contagem.items(), key=lambda x: -x[1])[:6])
    print(f"\n{SAIDA.name}: {quantos} títulos com gênero, "
          f"{SAIDA.stat().st_size / 1024:.0f} KB")
    print(f"mais comuns: {top}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
