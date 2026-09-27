#!/usr/bin/env python3
"""Fontes a mais do FenixFlix para os filmes e séries que o acervo já tem.

O FenixFlix responde por id do IMDb:

    /stream/movie/tt0068646.json
    /stream/series/tt0903747:1:1.json

O acervo guarda o id do TMDB (em vod/fichas.txt), não o do IMDb. O id do IMDb
de cada título é perguntado uma vez ao TMDB e fica guardado; a resposta do
Fenix também fica guardada, com data, e só é refeita quando envelhece. Assim a
primeira passada é longa e as seguintes só olham o que é novo ou velho.

O que sai daqui vai para vod/fenix/, no mesmo formato do Redeflix, e o
gerar_vod.py junta essas fontes **depois** das que o título já tinha: são
opções a mais, não substitutas.

Fica de fora:

- link com token de tempo no endereço (".../t/1790471865.abc.../..."): o Fenix
  guarda a resposta por uma hora e o token vence antes, então ele entrega links
  já mortos. Foi assim com todos os filmes "Hypex" testados em 27/09/2026.
- link que exige cabeçalho próprio (Referer, Cookie…): o acervo é uma lista de
  endereços e não tem onde guardar isso.

Numa série, o primeiro episódio que o acervo tem é perguntado antes: se o Fenix
não tem nada dele, a série é pulada sem perguntar episódio por episódio.

    python3 atualizar_fenix.py                # o que falta ou envelheceu
    python3 atualizar_fenix.py --limite 3000  # no máximo N perguntas ao Fenix
    python3 atualizar_fenix.py --so-filmes | --so-series
"""

from __future__ import annotations

import argparse
import json
import re
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

ROOT = Path(__file__).resolve().parent
VOD = ROOT / "vod"
SAIDA = VOD / "fenix"
CACHE = ROOT / "arquivos-gerados" / "fenix"

FENIX = "https://fenixflix.fenixhub.online"
TMDB = "https://api.themoviedb.org/3"
TMDB_CHAVE = "15d2ea6d0dc1d476efbca3eba2b9bbfb"
AGENTE = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
          "(KHTML, like Gecko) Chrome/140.0 Safari/537.36")

# Quanto uma resposta do Fenix vale antes de ser perguntada de novo. O que ele
# tem muda pouco; o que ele não tem, menos ainda.
VALIDADE_ACHADO = 3 * 24 * 3600
VALIDADE_VAZIO = 14 * 24 * 3600

TOKEN_DE_TEMPO = re.compile(r"/t/\d{9,11}\.[0-9a-f]{16,}/", re.I)
# O mesmo problema em outra forma: "?md5=...&expires=1790468146". O embedplayer
# que o Fenix devolve vem assim, e já vencido na hora da consulta.
VENCIMENTO = re.compile(r"[?&](?:expires|exp|e|expiry|validto|until)=\d{9,11}(?:&|$)", re.I)


def vence(url: str) -> bool:
    """Link com prazo escrito no endereço: não serve para uma lista publicada."""
    return bool(TOKEN_DE_TEMPO.search(url) or VENCIMENTO.search(url))
IMDB = re.compile(r"^tt\d{5,10}$")


# MARK: - Rede

def pedir_json(url: str, tentativas: int = 3):
    """GET com algumas tentativas: o Fenix às vezes responde vazio."""
    for tentativa in range(tentativas):
        try:
            pedido = urllib.request.Request(url, headers={"User-Agent": AGENTE, "Accept": "application/json"})
            with urllib.request.urlopen(pedido, timeout=25) as resposta:
                corpo = resposta.read(2_000_000)
            if corpo.strip():
                return json.loads(corpo)
        except urllib.error.HTTPError as erro:
            if erro.code == 404:
                return None
        except Exception:
            pass
        time.sleep(1.5 * (tentativa + 1))
    raise RuntimeError("sem resposta")


def toca(url: str) -> bool:
    """Pede o começo do arquivo e confere que é vídeo de verdade.

    Não basta o código 200: um link vencido costuma responder 200 com um texto
    de erro. Playlist tem de começar por #EXTM3U; o resto tem de se declarar
    vídeo (ou binário genérico, que é como muito servidor manda MKV e MP4).
    """
    try:
        pedido = urllib.request.Request(url, headers={"User-Agent": AGENTE, "Range": "bytes=0-2047"})
        with urllib.request.urlopen(pedido, timeout=25) as resposta:
            if resposta.status not in (200, 206):
                return False
            tipo = (resposta.headers.get("Content-Type") or "").lower().split(";")[0].strip()
            inicio = resposta.read(2048)
    except Exception:
        return False
    if b"#EXTM3U" in inicio[:64] or "mpegurl" in tipo:
        return inicio.lstrip().startswith(b"#EXTM3U")
    return tipo.startswith("video/") or tipo in (
        "application/octet-stream", "binary/octet-stream", "application/mp4",
        "application/x-matroska", "")


# MARK: - Cache em disco

class Guardado:
    """Um dicionário gravado em JSON, seguro entre threads."""

    def __init__(self, nome: str):
        self.caminho = CACHE / nome
        self.trava = threading.Lock()
        try:
            self.dados = json.loads(self.caminho.read_text(encoding="utf-8"))
        except Exception:
            self.dados = {}

    def get(self, chave, padrao=None):
        with self.trava:
            return self.dados.get(chave, padrao)

    def put(self, chave, valor):
        with self.trava:
            self.dados[chave] = valor

    def gravar(self):
        with self.trava:
            CACHE.mkdir(parents=True, exist_ok=True)
            temporario = self.caminho.with_suffix(".tmp")
            temporario.write_text(json.dumps(self.dados, ensure_ascii=False), encoding="utf-8")
            temporario.replace(self.caminho)


# MARK: - O acervo

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


def ler_imdb_do_redeflix() -> dict[str, str]:
    """O Redeflix já traz o IMDb de parte dos filmes: não precisa perguntar."""
    achados = {}
    arquivo = VOD / "redeflix" / "links-filmes.txt"
    if not arquivo.exists():
        return achados
    for linha in arquivo.read_text(encoding="utf-8").splitlines():
        campos = linha.split("\t")
        imdb = next((c[5:] for c in campos if c.startswith("imdb=")), "")
        if campos and IMDB.match(imdb):
            achados[campos[0]] = imdb
    return achados


def filmes_do_acervo() -> list[str]:
    titulos = []
    for arquivo in sorted(VOD.glob("filmes-*.txt")):
        for linha in arquivo.read_text(encoding="utf-8").splitlines():
            titulo = linha.split("\t", 1)[0]
            if titulo:
                titulos.append(titulo)
    return list(dict.fromkeys(titulos))


def series_do_acervo() -> dict[str, dict]:
    """Título -> {ano, episódios [(temporada, número)]}, dos pedaços publicados."""
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


# MARK: - Ids do IMDb

def imdb_de(tmdb_id: int, serie: bool, ids: Guardado) -> str:
    """O id do IMDb pelo TMDB, perguntado uma vez só por título."""
    chave = f"{'s' if serie else 'f'}:{tmdb_id}"
    guardado = ids.get(chave)
    if guardado is not None:
        return guardado
    tipo = "tv" if serie else "movie"
    try:
        dados = pedir_json(f"{TMDB}/{tipo}/{tmdb_id}/external_ids?api_key={TMDB_CHAVE}") or {}
        imdb = dados.get("imdb_id") or ""
    except Exception:
        return ""  # sem guardar: tenta de novo na próxima
    imdb = imdb if IMDB.match(imdb) else ""
    ids.put(chave, imdb)
    return imdb


# MARK: - Fenix

def idioma(texto: str) -> str:
    t = texto.lower()
    if "legendado" in t and "dual" not in t and "dublado" not in t:
        return "leg"
    return "dub"


def consultar(caminho: str, respostas: Guardado, contador: dict) -> list[list[str]]:
    """As fontes aproveitáveis de um filme ou episódio: [[idioma, url], ...]."""
    agora = time.time()
    guardada = respostas.get(caminho)
    if guardada:
        validade = VALIDADE_ACHADO if guardada["f"] else VALIDADE_VAZIO
        if agora - guardada["t"] < validade:
            return [f for f in guardada["f"] if not vence(f[1])]
    with contador["trava"]:
        if contador["feitas"] >= contador["limite"]:
            return guardada["f"] if guardada else []
        contador["feitas"] += 1
    try:
        dados = pedir_json(f"{FENIX}/stream/{caminho}.json") or {}
    except Exception:
        return guardada["f"] if guardada else []

    fontes: list[list[str]] = []
    vistos = set()
    antigas = {url for _, url in (guardada or {}).get("f", [])}
    for bruto in dados.get("streams") or []:
        if not isinstance(bruto, dict):
            continue
        url = str(bruto.get("url") or "")
        if not url.startswith("http") or url in vistos:
            continue
        vistos.add(url)
        if vence(url):
            continue
        dicas = bruto.get("behaviorHints") or {}
        if isinstance(dicas, dict) and (dicas.get("proxyHeaders") or {}).get("request"):
            continue
        # Um link novo só entra depois de responder com vídeo; o que já estava
        # guardado e voltou igual não precisa ser testado de novo.
        if url not in antigas and not toca(url):
            continue
        texto = " ".join(str(bruto.get(k) or "") for k in ("name", "title", "description"))
        fontes.append([idioma(texto), url])
    respostas.put(caminho, {"t": agora, "f": fontes})
    return fontes


# MARK: - Principal

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--limite", type=int, default=12000, help="perguntas ao Fenix nesta rodada")
    parser.add_argument("--workers", type=int, default=32)
    parser.add_argument("--so-filmes", action="store_true")
    parser.add_argument("--so-series", action="store_true")
    parser.add_argument("--amostra", type=int, default=0,
                        help="só os N primeiros títulos de cada tipo (para testar)")
    args = parser.parse_args()

    fichas = ler_fichas()
    imdb_redeflix = ler_imdb_do_redeflix()
    ids = Guardado("imdb.json")
    respostas = Guardado("respostas.json")
    contador = {"feitas": 0, "limite": args.limite, "trava": threading.Lock()}
    SAIDA.mkdir(parents=True, exist_ok=True)

    def gravar_caches():
        ids.gravar()
        respostas.gravar()

    # ── Filmes ──────────────────────────────────────────────────────────
    if not args.so_series:
        titulos = filmes_do_acervo()
        if args.amostra:
            titulos = titulos[:args.amostra]
        print(f"filmes no acervo: {len(titulos)}", flush=True)

        def fontes_do_filme(titulo: str):
            # Com o limite atingido não adianta nem descobrir o IMDb: a
            # pergunta ao Fenix não sairia, e o TMDB é que tomaria o tempo.
            if contador["feitas"] >= contador["limite"] and not respostas.get(f"movie/{imdb_redeflix.get(titulo, '')}"):
                return titulo, []
            imdb = imdb_redeflix.get(titulo)
            if not imdb:
                tmdb = fichas.get(("f", titulo)) or fichas.get(("f", sem_ano(titulo)))
                imdb = imdb_de(tmdb, False, ids) if tmdb else ""
            if not imdb:
                return titulo, []
            return titulo, consultar(f"movie/{imdb}", respostas, contador)

        achados: dict[str, list[list[str]]] = {}
        with ThreadPoolExecutor(args.workers) as grupo:
            for n, futuro in enumerate(as_completed(grupo.submit(fontes_do_filme, t) for t in titulos), 1):
                titulo, fontes = futuro.result()
                if fontes:
                    achados[titulo] = fontes
                if n % 2000 == 0:
                    print(f"  filmes: {n}/{len(titulos)} · com fonte: {len(achados)} · perguntas: {contador['feitas']}", flush=True)
                    gravar_caches()
        linhas = []
        for titulo in sorted(achados):
            por_idioma: dict[str, list[str]] = {}
            for lingua, url in achados[titulo]:
                por_idioma.setdefault(lingua, []).append(url)
            campos = [titulo] + [f"{l}={','.join(u)}" for l, u in sorted(por_idioma.items())]
            linhas.append("\t".join(campos))
        (SAIDA / "links-filmes.txt").write_text("\n".join(linhas) + ("\n" if linhas else ""), encoding="utf-8")
        print(f"filmes com fonte do Fenix: {len(achados)}", flush=True)
        gravar_caches()

    # ── Séries ──────────────────────────────────────────────────────────
    if not args.so_filmes:
        series = series_do_acervo()
        if args.amostra:
            series = dict(list(series.items())[:args.amostra])
        print(f"séries no acervo: {len(series)}", flush=True)

        def imdb_da_serie(titulo: str) -> str:
            tmdb = fichas.get(("s", titulo)) or fichas.get(("s", sem_ano(titulo)))
            return imdb_de(tmdb, True, ids) if tmdb else ""

        # 1ª etapa: o primeiro episódio de cada série, todas em paralelo. Sem
        # nada nele, a série sai daqui sem custar mais nenhuma pergunta.
        def sondar(titulo: str):
            eps = sorted(series[titulo]["eps"])
            if not eps or contador["feitas"] >= contador["limite"]:
                return titulo, "", []
            imdb = imdb_da_serie(titulo)
            if not imdb:
                return titulo, "", []
            t, e = eps[0]
            return titulo, imdb, consultar(f"series/{imdb}:{t}:{e}", respostas, contador)

        com_fonte: dict[str, str] = {}
        resultado: dict[str, dict] = {}
        with ThreadPoolExecutor(args.workers) as grupo:
            futuros = [grupo.submit(sondar, t) for t in series]
            for n, futuro in enumerate(as_completed(futuros), 1):
                titulo, imdb, fontes = futuro.result()
                if fontes:
                    com_fonte[titulo] = imdb
                    primeiro = sorted(series[titulo]["eps"])[0]
                    resultado.setdefault(titulo, {})[primeiro] = fontes
                if n % 1000 == 0:
                    print(f"  séries sondadas: {n}/{len(series)} · o Fenix tem: {len(com_fonte)} · perguntas: {contador['feitas']}", flush=True)
                    gravar_caches()
        print(f"séries que o Fenix tem: {len(com_fonte)}", flush=True)

        # 2ª etapa: os outros episódios dessas séries, cada um uma tarefa —
        # e não uma série por tarefa, que prendia um worker por minutos.
        def episodio(titulo: str, imdb: str, t: int, e: int):
            return titulo, (t, e), consultar(f"series/{imdb}:{t}:{e}", respostas, contador)

        tarefas = [(titulo, imdb, t, e) for titulo, imdb in com_fonte.items()
                   for (t, e) in sorted(series[titulo]["eps"])[1:]]
        with ThreadPoolExecutor(args.workers) as grupo:
            futuros = [grupo.submit(episodio, *tarefa) for tarefa in tarefas]
            for n, futuro in enumerate(as_completed(futuros), 1):
                titulo, alvo, fontes = futuro.result()
                if fontes:
                    resultado.setdefault(titulo, {})[alvo] = fontes
                if n % 2000 == 0:
                    print(f"  episódios: {n}/{len(tarefas)} · perguntas: {contador['feitas']}", flush=True)
                    gravar_caches()

        linhas = []
        for titulo in sorted(resultado):
            linhas.append(f"@{titulo}\t{series[titulo]['ano']}")
            for (temporada, numero), fontes in sorted(resultado[titulo].items()):
                por_idioma: dict[str, list[str]] = {}
                for lingua, url in fontes:
                    por_idioma.setdefault(lingua, []).append(url)
                for lingua, urls in sorted(por_idioma.items()):
                    linhas.append(f"{temporada}\t{numero}\t{lingua}\t{','.join(urls)}")
        (SAIDA / "links-series.txt").write_text("\n".join(linhas) + ("\n" if linhas else ""), encoding="utf-8")
        eps = sum(len(v) for v in resultado.values())
        print(f"séries com fonte do Fenix: {len(resultado)} ({eps} episódios)", flush=True)
        gravar_caches()

    print(f"perguntas ao Fenix nesta rodada: {contador['feitas']}"
          + (" (limite atingido: a próxima rodada continua)" if contador["feitas"] >= contador["limite"] else ""))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
