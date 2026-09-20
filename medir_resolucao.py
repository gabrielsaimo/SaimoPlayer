#!/usr/bin/env python3
"""Descobre a resolução de cada fonte de cada canal e publica a lista.

O nome da fonte quase nunca diz a qualidade — "FHD" aparece em cinco entradas
do acervo inteiro. Mas uma playlist HLS mestre declara, em `EXT-X-STREAM-INF`,
a resolução de cada variante que ela oferece. Isso é medido, não anunciado: é o
próprio servidor dizendo o que entrega.

Então a conta é feita aqui, uma vez, e o resultado publicado em
`resolucoes.txt`. Os aplicativos leem um arquivo pequeno e mostram FHD, HD ou
SD ao lado de cada fonte, sem baixar playlist nenhuma na hora de desenhar a
lista.

Fonte que não é HLS — um `.ts` cru, um MP4 — não declara nada, e nenhuma
conta aqui inventa o que ela não diz: fica de fora, e o app não mostra selo.

    ./medir_resolucao.py                 todos os canais do catálogo
    ./medir_resolucao.py --canal Globo   só um, para conferir
    ./medir_resolucao.py --linhas 40     limita, para uma passada rápida
"""
from __future__ import annotations

import argparse
import concurrent.futures
import re
import ssl
import sys
import urllib.error
import urllib.request
from pathlib import Path
from urllib.parse import urljoin

RAIZ = Path(__file__).resolve().parent
CATALOGO = RAIZ / "catalogo.txt"
RESTRITOS = RAIZ / "restritos.txt"
SAIDA = RAIZ / "resolucoes.txt"

AGENTE = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
          "(KHTML, like Gecko) Version/18.0 Safari/605.1.15")
TEMPO = 12
RESOLUCAO = re.compile(r"RESOLUTION=(\d+)x(\d+)", re.I)

# Sem verificar certificado: metade desses CDNs usa cadeia quebrada, e aqui só
# se lê o texto da playlist — não há segredo nenhum trafegando.
SEM_CONFERIR = ssl.create_default_context()
SEM_CONFERIR.check_hostname = False
SEM_CONFERIR.verify_mode = ssl.CERT_NONE


def rotulo(altura: int) -> str:
    """O nome que quem assiste reconhece."""
    if altura >= 2000:
        return "4K"
    if altura >= 1000:
        return "FHD"
    if altura >= 700:
        return "HD"
    return "SD"


def baixar(url: str, referer: str | None = None) -> str | None:
    pedido = urllib.request.Request(url, headers={
        "User-Agent": AGENTE,
        "Accept": "*/*",
        **({"Referer": referer} if referer else {}),
    })
    try:
        with urllib.request.urlopen(pedido, timeout=TEMPO, context=SEM_CONFERIR) as r:
            if r.status != 200:
                return None
            return r.read(400_000).decode("utf-8", "replace")
    except (urllib.error.URLError, OSError, ValueError, TimeoutError):
        return None


def medir(url: str, referer: str | None = None, fundo: int = 0) -> tuple[int, int] | None:
    """A maior resolução que esta fonte declara, ou nada.

    A playlist mestre lista as variantes com a resolução de cada uma; é a maior
    delas que o aplicativo vai abrir, então é ela que vale como resposta. Uma
    playlist de mídia não declara resolução nenhuma — aí não há o que dizer.

    Há CDN que responde com uma mestre que aponta para outra mestre; duas
    voltas bastam, e mais que isso costuma ser laço.
    """
    texto = baixar(url, referer)
    if not texto or "#EXTM3U" not in texto:
        return None

    achados = RESOLUCAO.findall(texto)
    if achados:
        return max(((int(w), int(h)) for w, h in achados), key=lambda wh: wh[1])

    # Sem resolução declarada: se esta mestre aponta para outra playlist, vale
    # seguir uma vez. Se aponta para segmentos, é playlist de mídia e acabou.
    if fundo >= 2:
        return None
    for linha in texto.splitlines():
        linha = linha.strip()
        if not linha or linha.startswith("#"):
            continue
        if ".m3u8" in linha.lower() or linha.lower().endswith(".txt"):
            return medir(urljoin(url, linha), referer, fundo + 1)
        break
    return None


def canais(caminho: Path) -> list[tuple[str, list[tuple[str, str | None]]]]:
    """Canal -> suas fontes, com o referer quando o catálogo declara um."""
    if not caminho.exists():
        return []
    out: list[tuple[str, list[tuple[str, str | None]]]] = []
    nome: str | None = None
    fontes: list[tuple[str, str | None]] = []
    referer: str | None = None
    for linha in caminho.read_text(encoding="utf-8").splitlines():
        if linha.startswith("canal: "):
            if nome and fontes:
                out.append((nome, fontes))
            nome, fontes, referer = linha[7:].strip(), [], None
        elif linha.startswith("referer: "):
            referer = linha[9:].strip()
        elif linha.startswith("fonte: ") and nome:
            fontes.append((linha[7:].strip(), referer))
    if nome and fontes:
        out.append((nome, fontes))
    return out


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--canal", default="", help="mede só o canal com este nome")
    parser.add_argument("--linhas", type=int, default=0, help="limita quantas fontes medir")
    parser.add_argument("--workers", type=int, default=24)
    args = parser.parse_args()

    lista = canais(CATALOGO) + canais(RESTRITOS)
    if args.canal:
        alvo = args.canal.lower()
        lista = [c for c in lista if alvo in c[0].lower()]

    # A mesma URL aparece em canais diferentes; medir uma vez basta.
    pedidos: dict[str, str | None] = {}
    for _, fontes in lista:
        for url, referer in fontes:
            pedidos.setdefault(url, referer)
    if args.linhas:
        pedidos = dict(list(pedidos.items())[: args.linhas])

    total = len(pedidos)
    print(f"{len(lista)} canais, {total} fontes distintas", flush=True)

    medidas: dict[str, tuple[int, int]] = {}
    feitos = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as piscina:
        futuros = {piscina.submit(medir, u, r): u for u, r in pedidos.items()}
        for futuro in concurrent.futures.as_completed(futuros):
            url = futuros[futuro]
            feitos += 1
            try:
                wh = futuro.result()
            except Exception:
                wh = None
            if wh:
                medidas[url] = wh
            if feitos % 25 == 0 or feitos == total:
                print(f"  [{feitos}/{total}] {len(medidas)} com resolução", flush=True)

    linhas = [
        "# Resolução declarada por cada fonte, medida em " +
        __import__("datetime").date.today().isoformat() + " por medir_resolucao.py.",
        "# url\tlargura x altura\trótulo",
    ]
    for url in sorted(medidas):
        w, h = medidas[url]
        linhas.append(f"{url}\t{w}x{h}\t{rotulo(h)}")
    SAIDA.write_text("\n".join(linhas) + "\n", encoding="utf-8")

    contagem: dict[str, int] = {}
    for w, h in medidas.values():
        contagem[rotulo(h)] = contagem.get(rotulo(h), 0) + 1
    resumo = " · ".join(f"{k} {v}" for k, v in sorted(contagem.items()))
    print(f"\n{SAIDA.name}: {len(medidas)} de {total} fontes ({resumo})")
    print(f"sem resolução declarada: {total - len(medidas)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
