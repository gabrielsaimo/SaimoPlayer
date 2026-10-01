#!/usr/bin/env python3
"""Testa as fontes do acervo (filmes e séries): qual está no ar e em que qualidade.

Rápido porque não baixa vídeo nenhum. Para cada fonte:

    MP4   lê só o cabeçalho (a caixa moov) com um pedido parcial — um ou dois
          pedidos por fonte — e tira largura e altura do tkhd do vídeo
    HLS   lê a playlist mestre e pega a maior RESOLUTION declarada
    resto (mkv, avi…) pergunta ao ffprobe, se houver um instalado

Muitas ao mesmo tempo, mas com limite por servidor: os servidores das listas são
contas Xtream, e rajada vira bloqueio — com 24 conexões por servidor o tvonhdbr
fechou a porta 80 para o IP inteiro (os apps desta rede junto). Então:

  - cada servidor começa em --por-servidor (6) e cai pela metade, com pausa,
    a cada sinal de freio (403/429/5xx, conexão recusada, página no lugar do
    vídeo); volta a subir sozinho com respostas limpas
  - 12 falhas seguidas sem nenhum acerto: o servidor barrou o teste, e ele
    para de ser testado (fica "recusada", nunca "morta")
  - toda não-viva é testada de novo no fim, 2 por servidor, após uma pausa;
    só o que falhar outra vez é morta

Nada no acervo é mudado: o resultado é relatório.

    python3 testar_fontes_vod.py                      filmes
    python3 testar_fontes_vod.py --series             episódios (muito mais)
    python3 testar_fontes_vod.py --series --amostra   1º episódio de cada temporada,
                                                      por servidor — rápido, diz qual
                                                      série/servidor caiu
    python3 testar_fontes_vod.py --tudo               filmes e episódios
    python3 testar_fontes_vod.py --do-zero            ignora o progresso guardado

Opções de ritmo: --workers (total, 256) e --por-servidor (8). Parar no meio não
perde nada: o progresso fica em arquivos-gerados/fontes-vod/ e a próxima
execução continua de onde parou (vale por --horas, 24).

Saída em arquivos-gerados/fontes-vod/:
    relatorio-<tipo>.txt    resumo por servidor, títulos sem nenhuma fonte viva
    qualidades-<tipo>.tsv   fonte (como no acervo) -> 4k/fhd/hd/sd e LxA
    mortas-<tipo>.tsv       fonte -> motivo -> título
"""
from __future__ import annotations

import argparse
import collections
import concurrent.futures
import http.client
import json
import os
import re
import shutil
import socket
import ssl
import struct
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

RAIZ = Path(__file__).resolve().parent
VOD = RAIZ / "vod"
SAIDA = RAIZ / "arquivos-gerados" / "fontes-vod"
AGENTE = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
          "(KHTML, like Gecko) Version/18.0 Safari/605.1.15")
TEMPO = 15
PRIMEIRO_PEDACO = 64 * 1024
# O tkhd do vídeo fica no começo do moov; o resto dele são tabelas de amostras
# que não interessam. Lê-se aos pedaços e para assim que achar.
PEDACO_MOOV = 256 * 1024
MOOV_MAXIMO = 4 * 1024 * 1024
RESOLUCAO = re.compile(r"RESOLUTION=(\d+)x(\d+)", re.I)
RECUSA = {403, 429, 456, 458, 503, 509, 520, 521, 522, 524}

# Sem conferir certificado: parte desses CDNs tem cadeia quebrada, e aqui só se
# lê cabeçalho de arquivo público — não trafega segredo nenhum.
SEM_CONFERIR = ssl.create_default_context()
SEM_CONFERIR.check_hostname = False
SEM_CONFERIR.verify_mode = ssl.CERT_NONE
ABRIDOR = urllib.request.build_opener(urllib.request.HTTPSHandler(context=SEM_CONFERIR))
FFPROBE = next((p for p in (shutil.which("ffprobe"),
                            "/Applications/Saimo TV.app/Contents/Resources/ffprobe")
                if p and os.path.exists(p)), None)
FFPROBE_VAGAS = threading.BoundedSemaphore(12)
TELA = threading.Lock()
MEDIR_QUALIDADE = True


# --------------------------------------------------------------------- acervo
def bases() -> dict[int, str]:
    saida = {}
    for linha in (VOD / "indice.txt").read_text(encoding="utf-8").splitlines():
        achado = re.fullmatch(r"base:\s*(\d+)\s+(.+)", linha)
        if achado:
            saida[int(achado.group(1))] = achado.group(2).strip()
    return saida


def montar(curta: str, tabela: dict[int, str]) -> str:
    """Mesma regra dos apps (Vod.swift): "N:resto" vira base + resto, e resto
    sem extensão é .mp4. Base desativada devolve vazio."""
    if curta.startswith("http"):
        return curta
    achado = re.fullmatch(r"(\d+):(.+)", curta)
    if not achado:
        return ""
    base = tabela.get(int(achado.group(1)), "")
    if not base or "desativado.invalid" in base:
        return ""
    resto = achado.group(2)
    return base + resto if "." in resto else f"{base}{resto}.mp4"


def fontes_de_filmes() -> dict[str, list[str]]:
    """fonte (como está no acervo) -> títulos que a usam."""
    saida: dict[str, list[str]] = collections.defaultdict(list)
    for caminho in sorted(VOD.glob("filmes-*.txt")):
        if not re.fullmatch(r"filmes-(?:#|[A-Z])\.txt", caminho.name):
            continue
        for linha in caminho.read_text(encoding="utf-8").splitlines():
            campos = linha.split("\t")
            for campo in campos[1:]:
                versao, _, urls = campo.partition("=")
                for url in urls.split(","):
                    if url:
                        saida[url].append(f"{campos[0]} [{versao}]")
    return saida


def fontes_de_series(amostra: bool) -> dict[str, list[str]]:
    saida: dict[str, list[str]] = collections.defaultdict(list)
    tabela = bases()
    for caminho in sorted(VOD.glob("series-*-*.txt")):
        titulo = ""
        ja_amostrado: set[tuple] = set()
        for linha in caminho.read_text(encoding="utf-8").splitlines():
            if linha.startswith("@"):
                titulo = " ".join(linha[1:].split("\t")[:2]).strip()
                continue
            campos = linha.split("\t")
            if len(campos) < 4 or not titulo:
                continue
            rotulo = f"{titulo} T{campos[0]}E{campos[1]} [{campos[2]}]"
            for url in campos[3].split(","):
                if not url:
                    continue
                if amostra:
                    # Um por temporada, versão e servidor: basta para saber se
                    # aquele servidor ainda entrega aquela série.
                    servidor = urllib.parse.urlsplit(montar(url, tabela)).hostname
                    chave = (titulo, campos[0], campos[2], servidor)
                    if chave in ja_amostrado:
                        continue
                    ja_amostrado.add(chave)
                saida[url].append(rotulo)
    return saida


# --------------------------------------------------------------------- rede
class Resposta:
    def __init__(self, codigo: int, corpo: bytes, cabecalhos, total: int | None, final: str = ""):
        self.codigo, self.corpo, self.cabecalhos, self.total = codigo, corpo, cabecalhos, total
        # Endereço depois dos redirecionamentos: o servidor Xtream manda para
        # um CDN, e repetir essa volta a cada pedido custa um segundo.
        self.final = final


def pedir(url: str, inicio: int = 0, tamanho: int = PRIMEIRO_PEDACO) -> Resposta:
    pedido = urllib.request.Request(url, headers={
        "User-Agent": AGENTE,
        # Sem Accept o EmbedPlayer responde 200 com "security error".
        "Accept": "*/*",
        "Range": f"bytes={inicio}-{inicio + tamanho - 1}",
    })
    try:
        with ABRIDOR.open(pedido, timeout=TEMPO) as r:
            corpo = r.read(tamanho)
            total = None
            faixa = r.headers.get("Content-Range", "")
            if "/" in faixa and faixa.rsplit("/", 1)[1].isdigit():
                total = int(faixa.rsplit("/", 1)[1])
            elif r.status == 200 and r.headers.get("Content-Length", "").isdigit():
                total = int(r.headers["Content-Length"])
            return Resposta(r.status, corpo, r.headers, total, r.geturl())
    except urllib.error.HTTPError as erro:
        return Resposta(erro.code, b"", erro.headers, None, url)


def caixas(dados: bytes, inicio: int = 0, fim: int | None = None):
    """(tipo, posição, tamanho, tamanho do cabeçalho) de cada caixa MP4."""
    fim = len(dados) if fim is None else fim
    pos = inicio
    while pos + 8 <= fim:
        tamanho, tipo = struct.unpack(">I4s", dados[pos:pos + 8])
        cabecalho = 8
        if tamanho == 1:
            if pos + 16 > fim:
                return
            tamanho = struct.unpack(">Q", dados[pos + 8:pos + 16])[0]
            cabecalho = 16
        elif tamanho == 0:
            tamanho = fim - pos
        if tamanho < cabecalho:
            return
        yield tipo, pos, tamanho, cabecalho
        pos += tamanho


def dimensoes_do_moov(moov: bytes) -> tuple[int, int] | None:
    maior = None
    for tipo, pos, tamanho, cab in caixas(moov, 0):
        if tipo != b"trak":
            continue
        for sub, spos, stam, scab in caixas(moov, pos + cab, min(pos + tamanho, len(moov))):
            if sub == b"tkhd" and spos + stam <= len(moov) and stam >= 84:
                # Largura e altura são os dois últimos campos do tkhd, em 16.16.
                w, h = struct.unpack(">II", moov[spos + stam - 8:spos + stam])
                w, h = w >> 16, h >> 16
                if w and h and (maior is None or w * h > maior[0] * maior[1]):
                    maior = (w, h)
    return maior


def ler_moov(url: str, inicio: int, ja_lido: bytes) -> tuple[int, int] | None:
    """Dimensões de um moov que começa em `inicio`, lendo só o necessário.

    `ja_lido` é o que já se tem a partir de `inicio`. Tenta com isso; se o tkhd
    do vídeo não estiver ali (o trak de áudio pode vir antes, com tabelas
    grandes), lê mais um pedaço, até o limite.
    """
    dados = ja_lido
    while True:
        if len(dados) >= 8 and dados[4:8] != b"moov":
            return None
        cab = 16 if dados[:4] == b"\0\0\0\1" else 8
        tamanho = struct.unpack(">I", dados[:4])[0] if len(dados) >= 4 else 0
        if cab == 16 and len(dados) >= 16:
            tamanho = struct.unpack(">Q", dados[8:16])[0]
        if len(dados) > cab:
            achado = dimensoes_do_moov(dados[cab:tamanho] if tamanho else dados[cab:])
            if achado:
                return achado
        if (tamanho and len(dados) >= tamanho) or len(dados) >= MOOV_MAXIMO:
            return None
        mais = pedir(url, inicio + len(dados), PEDACO_MOOV)
        if mais.codigo not in (200, 206) or not mais.corpo:
            return None
        if mais.codigo == 200:  # servidor ignorou a faixa: não dá para seguir
            return None
        dados += mais.corpo


def medir_mp4(url: str, primeira: Resposta) -> tuple[int, int] | None:
    url = primeira.final or url
    dados = primeira.corpo
    for tipo, pos, tamanho, cab in caixas(dados):
        if tipo == b"moov":
            return ler_moov(url, pos, dados[pos:])
        if pos + tamanho > len(dados):
            # A caixa (quase sempre o mdat) passa do pedaço lido: o moov, se não
            # veio antes, está depois dela — no fim do arquivo.
            depois = pos + tamanho
            if primeira.total and depois >= primeira.total:
                return None
            fim = pedir(url, depois, PEDACO_MOOV)
            if fim.codigo != 206:
                return None
            return ler_moov(url, depois, fim.corpo)
    return None


def medir_hls(url: str, texto: str, fundo: int = 0) -> tuple[int, int] | None:
    achados = RESOLUCAO.findall(texto)
    if achados:
        return max(((int(w), int(h)) for w, h in achados), key=lambda wh: wh[0] * wh[1])
    if fundo >= 2:
        return None
    for linha in texto.splitlines():
        linha = linha.strip()
        if linha and not linha.startswith("#"):
            if ".m3u8" in linha.lower() or linha.lower().endswith(".txt"):
                proxima = urllib.parse.urljoin(url, linha)
                r = pedir(proxima, 0, 256 * 1024)
                corpo = r.corpo.decode("utf-8", "replace")
                if r.codigo in (200, 206) and "#EXTM3U" in corpo:
                    return medir_hls(proxima, corpo, fundo + 1)
            return None
    return None


def medir_ffprobe(url: str) -> tuple[int, int] | None:
    if not FFPROBE:
        return None
    with FFPROBE_VAGAS:
        try:
            saida = subprocess.run(
                [FFPROBE, "-v", "error", "-rw_timeout", "12000000", "-user_agent", AGENTE,
                 "-select_streams", "v", "-show_entries", "stream=width,height", "-of", "json", url],
                capture_output=True, timeout=25).stdout
            fluxos = json.loads(saida or b"{}").get("streams", [])
        except Exception:
            return None
    dims = [(s.get("width", 0), s.get("height", 0)) for s in fluxos if s.get("width") and s.get("height")]
    return max(dims, key=lambda wh: wh[0] * wh[1]) if dims else None


def rotulo(w: int, h: int) -> str:
    # Largura também conta: 1920x800 (cinemascope) é FHD, não HD.
    if w >= 3200 or h >= 2000:
        return "4k"
    if w >= 1800 or h >= 1000:
        return "fhd"
    if w >= 1200 or h >= 700:
        return "hd"
    return "sd"


def testar(url: str) -> dict:
    """{"estado": viva|morta|recusada|sem_resposta, "motivo", "q", "wh"}"""
    espera = 1.0
    ultimo = {"estado": "sem_resposta", "motivo": "sem resposta"}
    for tentativa in range(4):
        try:
            r = pedir(url)
        except (socket.gaierror,) as erro:
            return {"estado": "sem_resposta", "motivo": "DNS: falha de resolução; conexão inconclusiva"}
        except urllib.error.URLError as erro:
            razao = erro.reason
            if isinstance(razao, socket.gaierror):
                return {"estado": "sem_resposta", "motivo": "DNS: falha de resolução; conexão inconclusiva"}
            if isinstance(razao, ConnectionRefusedError):
                return {"estado": "recusada", "motivo": "conexão recusada"}
            ultimo = {"estado": "sem_resposta", "motivo": f"{type(razao).__name__}"}
        except (TimeoutError, socket.timeout):
            ultimo = {"estado": "sem_resposta", "motivo": "tempo esgotado"}
        except (http.client.HTTPException, ConnectionError, OSError) as erro:
            ultimo = {"estado": "sem_resposta", "motivo": type(erro).__name__}
        else:
            if r.codigo in RECUSA or r.codigo >= 500:
                ultimo = {"estado": "recusada", "motivo": f"HTTP {r.codigo}"}
            elif r.codigo not in (200, 206):
                return {"estado": "morta" if r.codigo in (404, 410) else "recusada", "motivo": f"HTTP {r.codigo}"}
            elif not r.corpo:
                ultimo = {"estado": "sem_resposta", "motivo": "resposta vazia"}
            else:
                return analisar(url, r)
        if tentativa < 3:
            time.sleep(espera)
            espera *= 2.5
    return ultimo


def seguro(medida, *args):
    """A fonte já respondeu com vídeo: falhar ao medir não a torna morta."""
    try:
        return medida(*args)
    except Exception:
        return None


def analisar(url: str, r: Resposta) -> dict:
    inicio = r.corpo[:4096]
    texto = inicio.decode("utf-8", "replace").lstrip("﻿ \r\n")
    if texto.startswith("#EXTM3U"):
        if not MEDIR_QUALIDADE:
            return viva(None, "hls")
        return viva(seguro(medir_hls, url, r.corpo.decode("utf-8", "replace")), "hls")
    if texto[:1] == "<" or "security error" in texto.lower():
        return {"estado": "recusada", "motivo": "responde página, não vídeo"}
    if inicio[4:8] in (b"ftyp", b"moov", b"mdat", b"free", b"skip", b"wide"):
        if not MEDIR_QUALIDADE:
            return viva(None, "mp4")
        return viva(seguro(medir_mp4, url, r) or seguro(medir_ffprobe, url), "mp4")
    if not MEDIR_QUALIDADE:
        return viva(None, "outro")
    return viva(seguro(medir_ffprobe, url), "outro")


def viva(wh, tipo: str) -> dict:
    saida = {"estado": "viva", "tipo": tipo}
    if wh:
        saida["wh"] = f"{wh[0]}x{wh[1]}"
        saida["q"] = rotulo(*wh)
    return saida


# --------------------------------------------------------------------- ritmo
# Sobrecarga não vem como 403: medido em 28/09/2026, com 24 conexões o tjtor
# passou a responder a página "Welcome to nginx" (com status 206) e o tvonhdbr a
# recusar conexão — 169 de 400 fontes vivas pareceram mortas. Esses sinais
# freiam o servidor em vez de condenar a fonte.
SUSPEITOS = {"conexão recusada", "responde página, não vídeo", "resposta vazia"}
BARROU = "servidor barrou o teste (bloqueio por excesso?) — rode de novo mais tarde"


def suspeito(item: dict) -> bool:
    return item["estado"] in ("recusada", "sem_resposta") or item.get("motivo") in SUSPEITOS


def falha_confirmada(item: dict) -> bool:
    return (item.get("estado") == "morta" and bool(item.get("conf"))
            and item.get("motivo") in ("HTTP 404", "HTTP 410"))


class Servidor:
    """Quantas conexões ao mesmo tempo um servidor aguenta, ajustado no caminho.

    Começa no máximo pedido; a cada sinal de bloqueio cai pela metade e pausa
    alguns segundos; a cada leva de respostas limpas sobe um.
    """

    # Tantas falhas seguidas sem uma resposta limpa no meio: o servidor não está
    # freando, está barrando este IP (em 28/09/2026 o tvonhdbr fechou a porta 80
    # depois de uma rajada). Insistir só prolonga o bloqueio — e ele vale também
    # para os apps nesta rede. Desiste do servidor e avisa no relatório.
    DISJUNTOR = 12

    def __init__(self, maximo: int):
        self.maximo = maximo
        self.limite = float(min(2, maximo))
        self.ativos = 0
        self.limpas = 0
        self.seguidas = 0
        self.barrado = False
        self.pausa_ate = 0.0
        self.cond = threading.Condition()

    def entrar(self) -> bool:
        with self.cond:
            while True:
                if self.barrado:
                    return False
                espera = self.pausa_ate - time.monotonic()
                if espera <= 0 and self.ativos < int(self.limite):
                    self.ativos += 1
                    return True
                self.cond.wait(timeout=max(espera, 0.2))

    def sair(self, item: dict) -> None:
        with self.cond:
            self.ativos -= 1
            if suspeito(item):
                self.seguidas += 1
                if self.seguidas >= self.DISJUNTOR:
                    self.barrado = True
                self.limite = max(1.0, self.limite / 2)
                self.limpas = 0
                self.pausa_ate = max(self.pausa_ate, time.monotonic() + 3)
            else:
                self.seguidas = 0
                self.limpas += 1
                if self.limpas >= 4 * self.limite and self.limite < self.maximo:
                    self.limite += 1
                    self.limpas = 0
            self.cond.notify_all()


# --------------------------------------------------------------------- rodada
def rodar(tipo: str, fontes: dict[str, list[str]], args) -> None:
    tabela = bases()
    SAIDA.mkdir(parents=True, exist_ok=True)
    progresso = SAIDA / f"progresso-{tipo}.jsonl"
    feitos: dict[str, dict] = {}
    if progresso.exists() and not args.do_zero:
        validade = time.time() - args.horas * 3600
        for linha in progresso.read_text(encoding="utf-8").splitlines():
            try:
                item = json.loads(linha)
            except ValueError:
                continue
            # Reaproveita viva e morta confirmada; o resto pode ter sido de
            # passagem e é testado de novo. Linha mais nova vale mais.
            if item.get("t", 0) >= validade and (
                    item.get("estado") == "viva" or falha_confirmada(item)):
                feitos[item["u"]] = item
            else:
                feitos.pop(item.get("u"), None)
    elif progresso.exists():
        progresso.unlink()

    desativadas = [u for u in fontes if not montar(u, tabela)]
    pendentes = [u for u in fontes if u not in feitos and montar(u, tabela)]
    if args.limite:
        pendentes = pendentes[: args.limite]

    # Intercala os servidores: com a fila em ordem, os primeiros 256 seriam todos
    # do mesmo servidor, esperando a vez dele, e os outros ficariam parados.
    por_servidor: dict[str, list[str]] = collections.defaultdict(list)
    for u in pendentes:
        por_servidor[urllib.parse.urlsplit(montar(u, tabela)).hostname or "?"].append(u)
    fila = []
    filas = [collections.deque(v) for v in por_servidor.values()]
    while filas:
        for f in list(filas):
            fila.append(f.popleft())
            if not f:
                filas.remove(f)

    ritmo_lock = threading.Lock()

    def uma(u: str, servidores: dict[str, Servidor], maximo: int) -> dict:
        url = montar(u, tabela)
        nome = urllib.parse.urlsplit(url).hostname or "?"
        with ritmo_lock:
            servidor = servidores.setdefault(nome, Servidor(maximo))
        if not servidor.entrar():
            return {"estado": "recusada", "motivo": BARROU, "u": u, "s": nome, "ms": 0, "t": int(time.time())}
        comeco = time.monotonic()
        resultado: dict = {"estado": "sem_resposta", "motivo": "erro interno"}
        try:
            resultado = testar(url)
        finally:
            servidor.sair(resultado)
        resultado.update(u=u, s=nome, ms=int((time.monotonic() - comeco) * 1000), t=int(time.time()))
        return resultado

    def limites(servidores: dict[str, Servidor]) -> str:
        barrados = [n.split(".")[0] for n, s in servidores.items() if s.barrado]
        freados = [f"{n.split('.')[0]} {int(s.limite)}" for n, s in servidores.items()
                   if s.limite < s.maximo and not s.barrado]
        return ((" · freados: " + ", ".join(freados)) if freados else "") + \
               ((" · BARRARAM O TESTE: " + ", ".join(barrados)) if barrados else "")

    print(f"\n== {tipo}: {len(fontes)} fontes · {len(feitos)} já testadas nas últimas {args.horas}h · "
          f"{len(desativadas)} em servidor desativado · {len(fila)} a testar em "
          f"{len(por_servidor)} servidores ({args.workers} ao mesmo tempo, até {args.por_servidor} por servidor)"
          + ("" if FFPROBE else " · sem ffprobe: mkv/avi ficam sem qualidade"), flush=True)
    def passada(rotulo: str, lista: list[str], maximo: int, confirmar: bool) -> collections.Counter:
        servidores: dict[str, Servidor] = {}
        contagem: collections.Counter = collections.Counter()
        comeco = time.monotonic()
        with progresso.open("a", encoding="utf-8") as registro, \
                concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
            futuros = [pool.submit(uma, u, servidores, maximo) for u in lista]
            try:
                for n, futuro in enumerate(concurrent.futures.as_completed(futuros), 1):
                    item = futuro.result()
                    if confirmar:
                        item["conf"] = 1
                    feitos[item["u"]] = item
                    contagem[item["estado"]] += 1
                    registro.write(json.dumps(item, ensure_ascii=False) + "\n")
                    if n % 200 == 0 or n == len(futuros):
                        registro.flush()
                        ritmo = n / max(time.monotonic() - comeco, 0.001)
                        falta = (len(futuros) - n) / max(ritmo, 0.001) / 60
                        with TELA:
                            print(f"[{rotulo} {n}/{len(futuros)}] {ritmo:.0f}/s · ETA {falta:.1f} min · "
                                  f"vivas {contagem['viva']} · mortas {contagem['morta']} · "
                                  f"recusadas {contagem['recusada']} · sem resposta {contagem['sem_resposta']}"
                                  + limites(servidores), flush=True)
            except KeyboardInterrupt:
                print("\nparando: o que já foi testado está guardado; rode de novo para continuar.", flush=True)
                for f in futuros:
                    f.cancel()
                pool.shutdown(wait=False, cancel_futures=True)
                registro.flush()
                raise SystemExit(130)
        return contagem

    passada(tipo, fila, args.por_servidor, confirmar=False)

    # Confirmação: toda não-viva de novo, devagar e depois de uma pausa. Só o
    # que falhar outra vez fica como morta — o resto era servidor freando.
    # Servidor que barrou o teste fica de fora: confirmar ali seria insistir.
    duvidosas = [u for u in fila if feitos.get(u, {}).get("estado") != "viva"
                 and feitos.get(u, {}).get("motivo") != BARROU]
    if duvidosas:
        print(f"\nconfirmando {len(duvidosas)} não-vivas, 2 por servidor, depois de {args.pausa}s…", flush=True)
        time.sleep(args.pausa)
        c = passada(f"{tipo} · confirmação", duvidosas, 2, confirmar=True)
        print(f"confirmação: {c['viva']} estavam vivas (era bloqueio) · {c['morta']} mortas de verdade", flush=True)

    relatorio(tipo, fontes, feitos, desativadas)


def relatorio(tipo: str, fontes: dict[str, list[str]], feitos: dict[str, dict], desativadas: list[str]) -> None:
    testadas = {u: feitos[u] for u in fontes if u in feitos}
    # Qualidades: a fonte como está no acervo, para cruzar com marcas.txt.
    qual = [f"{u}\t{i['q']}\t{i['wh']}" for u, i in sorted(testadas.items()) if i.get("q")]
    (SAIDA / f"qualidades-{tipo}.tsv").write_text(
        "# fonte\tqualidade\tlarguraxaltura\n" + "\n".join(qual) + "\n", encoding="utf-8")
    mortas = [(u, i) for u, i in sorted(testadas.items()) if falha_confirmada(i)]
    inconclusivas = [(u,i) for u,i in sorted(testadas.items())
                    if i["estado"] != "viva" and not falha_confirmada(i)]
    (SAIDA / f"inconclusivas-{tipo}.tsv").write_text(
        "# fonte\testado\tmotivo\tservidor\ttítulos\n" + "\n".join(
            f"{u}\t{i['estado']}\t{i.get('motivo','')}\t{i.get('s','')}\t{' | '.join(fontes[u][:3])}"
            for u,i in inconclusivas) + "\n", encoding="utf-8")
    (SAIDA / f"mortas-{tipo}.tsv").write_text(
        "# fonte\testado\tmotivo\tservidor\ttítulos\n" + "\n".join(
            f"{u}\t{i['estado']}\t{i.get('motivo', '')}\t{i.get('s', '')}\t{' | '.join(fontes[u][:3])}"
            for u, i in mortas) + "\n", encoding="utf-8")

    servidores: dict[str, collections.Counter] = collections.defaultdict(collections.Counter)
    for i in testadas.values():
        servidores[i.get("s", "?")][i["estado"]] += 1
        if i.get("motivo") == BARROU:
            servidores[i.get("s", "?")]["barrou"] += 1
        if i.get("q"):
            servidores[i.get("s", "?")]["q_" + i["q"]] += 1

    # Título sem nenhuma fonte viva: é o que a pessoa vê quebrado no app.
    titulos: dict[str, list[str]] = collections.defaultdict(list)
    for u, nomes in fontes.items():
        for nome in nomes:
            titulos[nome].append(u)
    # Só morta de verdade conta; recusa e silêncio podem ser o servidor barrando.
    sem_viva = sorted(t for t, us in titulos.items()
                      if all(u in testadas and falha_confirmada(testadas[u]) for u in us))
    so_desativada = sorted(t for t, us in titulos.items() if all(u in desativadas for u in us))

    total = collections.Counter(i["estado"] for i in testadas.values())
    quals = collections.Counter(i["q"] for i in testadas.values() if i.get("q"))
    linhas = [
        f"FONTES DO ACERVO — {tipo.upper()} — {time.strftime('%d/%m/%Y %H:%M')}",
        f"{len(testadas)} fontes testadas: {total['viva']} vivas · {total['morta']} mortas · "
        f"{total['recusada']} recusadas (servidor barrou, inconclusivo) · "
        f"{total['sem_resposta']} sem resposta",
        "qualidade medida: " + " · ".join(f"{k.upper()} {v}" for k, v in quals.most_common())
        + f" · sem medida {total['viva'] - sum(quals.values())}",
        "",
        "POR SERVIDOR",
    ]
    for servidor, c in sorted(servidores.items(), key=lambda kv: -sum(kv[1][e] for e in ("viva", "morta", "recusada", "sem_resposta"))):
        n = sum(c[e] for e in ("viva", "morta", "recusada", "sem_resposta"))
        vivas = c["viva"]
        if c["barrou"]:
            alerta = f"   <<< BARROU O TESTE ({c['barrou']} não testadas) — rode de novo mais tarde"
        elif n >= 20 and vivas == 0:
            alerta = "   <<< NENHUMA RESPOSTA VÁLIDA — não comprova queda do servidor"
        elif n >= 20 and vivas < n / 2:
            alerta = "   <<< maioria sem resposta válida; conferir motivos"
        else:
            alerta = ""
        linhas.append(f"  {servidor:32} {n:7} fontes · {vivas / max(n, 1):6.1%} vivas · mortas {c['morta']} · "
                      f"recusadas {c['recusada']} · sem resposta {c['sem_resposta']} · "
                      f"4K {c['q_4k']} FHD {c['q_fhd']} HD {c['q_hd']} SD {c['q_sd']}{alerta}")
    linhas += ["", f"SEM NENHUMA FONTE VIVA — {len(sem_viva)} (é o que aparece quebrado no app)"]
    linhas += [f"  {t}" for t in sem_viva]
    if so_desativada:
        linhas += ["", f"SÓ TÊM FONTE EM SERVIDOR DESATIVADO (indice.txt) — {len(so_desativada)}"]
        linhas += [f"  {t}" for t in so_desativada]
    caminho = SAIDA / f"relatorio-{tipo}.txt"
    caminho.write_text("\n".join(linhas) + "\n", encoding="utf-8")

    print("\n".join(linhas[:5 + len(servidores) + 1]), flush=True)
    print(f"\nsem nenhuma fonte viva: {len(sem_viva)} · relatório: {caminho}", flush=True)
    print(f"qualidades: {SAIDA / f'qualidades-{tipo}.tsv'} · mortas: {SAIDA / f'mortas-{tipo}.tsv'}", flush=True)


def main() -> int:
    global MEDIR_QUALIDADE
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0],
                                     formatter_class=argparse.RawDescriptionHelpFormatter, epilog=__doc__)
    parser.add_argument("--series", action="store_true", help="testa os episódios em vez dos filmes")
    parser.add_argument("--tudo", action="store_true", help="filmes e episódios")
    parser.add_argument("--amostra", action="store_true",
                        help="séries: 1º episódio de cada temporada, versão e servidor")
    parser.add_argument("--workers", type=int, default=256)
    parser.add_argument("--por-servidor", type=int, default=6,
                        help="máximo por servidor; cai sozinho quando o servidor freia")
    parser.add_argument("--pausa", type=int, default=20, help="segundos antes de confirmar as mortas")
    parser.add_argument("--horas", type=int, default=24, help="reaproveita testes mais novos que isso")
    parser.add_argument("--do-zero", action="store_true")
    parser.add_argument("--somente-disponibilidade", action="store_true",
                        help="testa a resposta sem medir resolução nem executar ffprobe")
    parser.add_argument("--limite", type=int, default=0, help="testa só N fontes (para conferir)")
    args = parser.parse_args()
    MEDIR_QUALIDADE = not args.somente_disponibilidade
    if not 1 <= args.workers <= 1024 or not 1 <= args.por_servidor <= 128:
        raise SystemExit("--workers entre 1 e 1024, --por-servidor entre 1 e 128")
    socket.setdefaulttimeout(TEMPO)

    if args.tudo or not args.series:
        rodar("filmes", fontes_de_filmes(), args)
    if args.tudo or args.series:
        rodar("series-amostra" if args.amostra else "series", fontes_de_series(args.amostra), args)
    return 0


if __name__ == "__main__":
    sys.exit(main())
