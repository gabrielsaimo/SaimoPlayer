#!/usr/bin/env python3
"""Ordem das fontes de cada canal: o Nexus nunca é a primeira opção.

A primeira fonte é a que o app abre; as outras são reserva, tentadas na
ordem quando ela falha. O fallback1.nexustvplay é estável, mas demora mais
para começar que as fontes das contas Xtream, e não pode ser a primeira:
fica logo depois dela, como segunda opção. Só fica em primeiro no canal que
não tem outra fonte.

A primeira é a primeira fonte de outro servidor que não esteja desligado no
painel do monitor (servidor desligado os apps nem tentam). Com --testar, as
candidatas são testadas na ordem e vai para a frente a primeira que responde
agora (playlist HLS com pedaços, .ts que entrega vídeo, manifesto DASH);
sem nenhuma respondendo, fica a primeira candidata. Nos canais 24 horas o
vivlar.me vem na frente, onde estão as temporadas inteiras.

Cada fonte anda com os atributos dela (qualidade, nome, referer, agente,
chave). Nada é apagado nem duplicado: só a ordem muda. Rodar de novo é seguro
e não desfaz a escolha do --testar: a primeira que já está na frente fica.

    python3 ordenar_fontes.py             só a regra
    python3 ordenar_fontes.py --testar    testa as candidatas antes
"""
import argparse
import collections
import concurrent.futures as cf
import json
import subprocess
import threading
import urllib.request
from pathlib import Path

CATALOGO = Path(__file__).parent / "catalogo.txt"
NEXUS = "nexustvplay.bbroot.com"
# Categorias com uma fonte preferida na frente de todas.
PRIMEIRA_POR_CATEGORIA = {"24 Horas": "vivlar.me"}
MONITOR = "https://saimo-monitor.gabrielsaimo68.workers.dev/v1/fontes"
AGENTE = "Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36"
ATRIBUTOS = ("qualidade:", "referer:", "agente:", "chave:", "nome:")
TENTATIVAS = 4

_travas: dict[str, threading.Semaphore] = collections.defaultdict(lambda: threading.Semaphore(2))
_trava = threading.Lock()


def host(fonte: list[str]) -> str:
    url = fonte[0][len("fonte:"):].strip()
    return url.split("://", 1)[-1].split("/", 1)[0].split(":", 1)[0].lower()


def desligados() -> set[str]:
    """Servidores desligados no painel do monitor; sem resposta, nenhum."""
    try:
        pedido = urllib.request.Request(MONITOR, headers={"User-Agent": AGENTE})
        with urllib.request.urlopen(pedido, timeout=20) as r:
            return {h.lower() for h in json.load(r).get("desativados", [])}
    except Exception:
        return set()


def atributo(fonte: list[str], chave: str) -> str | None:
    return next((l.split(":", 1)[1].strip() for l in fonte[1:] if l.startswith(chave)), None)


def curl(url: str, fonte: list[str], faixa: str | None = None) -> bytes:
    cmd = ["curl", "-s", "-L", "--max-time", "10", "-A", atributo(fonte, "agente:") or AGENTE]
    if referer := atributo(fonte, "referer:"):
        cmd += ["-e", referer]
    if faixa:
        cmd += ["-r", faixa]
    return subprocess.run(cmd + [url], capture_output=True).stdout


def responde(fonte: list[str]) -> bool:
    """A fonte abre agora? Por servidor, no máximo dois testes ao mesmo tempo."""
    url = fonte[0][len("fonte:"):].strip()
    with _trava:
        semaforo = _travas[host(fonte)]
    with semaforo:
        if ".mpd" in url:
            return b"<MPD" in curl(url, fonte)
        if url.split("?")[0].endswith(".ts"):
            return len(curl(url, fonte, "0-65535")) > 1000
        corpo = curl(url, fonte).lstrip()
        # Playlist com pedaços ou mestre com variantes. O pedaço não é pedido:
        # as contas Xtream dão token de uso único e o segundo pedido volta
        # vazio, o que não quer dizer que a fonte caiu.
        return corpo.startswith(b"#EXTM3U") and (b"#EXTINF" in corpo or b"#EXT-X-STREAM-INF" in corpo)


def separar(bloco: list[str]) -> tuple[list[str], list[list[str]], list[str]]:
    cabeca, fontes, resto = [], [], []
    k = 0
    while k < len(bloco) and not bloco[k].startswith("fonte:"):
        cabeca.append(bloco[k])
        k += 1
    while k < len(bloco):
        if bloco[k].startswith("fonte:"):
            fonte = [bloco[k]]
            k += 1
            while k < len(bloco) and bloco[k].startswith(ATRIBUTOS):
                fonte.append(bloco[k])
                k += 1
            fontes.append(fonte)
        else:
            resto.append(bloco[k])
            k += 1
    return cabeca, fontes, resto


def ordenar(bloco: list[str], fora: set[str], testar: bool) -> list[str]:
    cabeca, fontes, resto = separar(bloco)
    categoria = next((l.split(":", 1)[1].strip() for l in cabeca if l.startswith("categoria:")), "")
    nexus = [f for f in fontes if NEXUS in f[0]]
    outras = [f for f in fontes if NEXUS not in f[0]]
    preferida = PRIMEIRA_POR_CATEGORIA.get(categoria)
    # Canal sem Nexus e sem preferida fica como está; sem outra fonte, também.
    if not outras or (not nexus and not preferida):
        return bloco
    if preferida:
        # sort é estável: entre as outras, a ordem de antes fica.
        outras.sort(key=lambda f: 0 if preferida in f[0] else 1)
    ligadas = [f for f in outras if host(f) not in fora] or outras
    primeira = ligadas[0]
    if testar:
        primeira = next((f for f in ligadas[:TENTATIVAS] if responde(f)), primeira)
    resto_das_outras = [f for f in outras if f is not primeira]
    nova = [primeira, *nexus, *resto_das_outras]
    return cabeca + [linha for fonte in nova for linha in fonte] + resto


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--testar", action="store_true", help="testa as candidatas e põe na frente a que responde")
    args = ap.parse_args()

    fora = desligados()
    linhas = CATALOGO.read_text(encoding="utf-8").split("\n")
    blocos: list[tuple[int, int]] = []
    i = 0
    while i < len(linhas):
        if linhas[i].startswith("canal:"):
            j = i + 1
            while j < len(linhas) and not linhas[j].startswith("canal:"):
                j += 1
            blocos.append((i, j))
            i = j
        else:
            i += 1

    with cf.ThreadPoolExecutor(16) as ex:
        novos = list(ex.map(lambda b: ordenar(linhas[b[0]:b[1]], fora, args.testar), blocos))

    saida: list[str] = []
    ultimo = 0
    for (i, j), novo in zip(blocos, novos):
        saida += linhas[ultimo:i] + novo
        ultimo = j
    saida += linhas[ultimo:]

    novo = "\n".join(saida)
    if novo != "\n".join(linhas):
        CATALOGO.write_text(novo, encoding="utf-8")
        print("ordem das fontes atualizada")
    else:
        print("já estava em ordem")


if __name__ == "__main__":
    main()
