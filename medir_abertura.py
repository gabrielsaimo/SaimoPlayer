#!/usr/bin/env python3
"""Mede quanto cada fonte dos canais leva para começar a tocar.

"Abrir" é o que o player faz antes do primeiro quadro: baixar a playlist
(e a variante, quando a primeira é uma playlist mestre) e o primeiro pedaço
de vídeo. Fonte .ts direta: os primeiros 64 KB. DASH: só o manifesto, porque
os pedaços dependem da chave.

Só mede os canais que têm fonte do nexustvplay e, neles, o próprio Nexus e
as fontes dos servidores adicionados por último (RECENTES), que são as
candidatas a ir na frente dele em ordenar_fontes.py. Grava em
arquivos-gerados/abertura.json ({url: milissegundos, ou null se não abriu}).

    python3 medir_abertura.py
"""
import collections
import concurrent.futures as cf
import json
import subprocess
import threading
import time
from pathlib import Path
from urllib.parse import urljoin

RAIZ = Path(__file__).parent
CATALOGO = RAIZ / "catalogo.txt"
SAIDA = RAIZ / "arquivos-gerados" / "abertura.json"
AGENTE = "Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36"
NEXUS = "nexustvplay.bbroot.com"
RECENTES = ("vivlar.me", "vaiagora.vip", "corruptx.org", "332nr7hbfu.xyz")
LIMITE_S = 8
POR_SERVIDOR = 2

_travas: dict[str, threading.Semaphore] = collections.defaultdict(lambda: threading.Semaphore(POR_SERVIDOR))
_trava = threading.Lock()


def fontes_dos_canais() -> list[dict]:
    """Fontes de cada canal com Nexus, com referer e agente."""
    canais, atual, fonte = [], None, None
    for linha in CATALOGO.read_text(encoding="utf-8").split("\n"):
        if linha.startswith("canal:"):
            atual = {"nome": linha[6:].strip(), "fontes": []}
            canais.append(atual)
        elif linha.startswith("fonte:") and atual is not None:
            fonte = {"url": linha[6:].strip()}
            atual["fontes"].append(fonte)
        elif fonte is not None and linha.startswith(("referer:", "agente:")):
            chave, valor = linha.split(":", 1)
            fonte[chave] = valor.strip()
    return [c for c in canais if any(NEXUS in f["url"] for f in c["fontes"])]


def baixar(url: str, fonte: dict, restante: float, faixa: str | None = None) -> bytes | None:
    cmd = ["curl", "-s", "-L", "-f", "--max-time", f"{max(restante, 1):.1f}",
           "-A", fonte.get("agente", AGENTE)]
    if fonte.get("referer"):
        cmd += ["-e", fonte["referer"]]
    if faixa:
        cmd += ["-r", faixa]
    r = subprocess.run(cmd + [url], capture_output=True)
    return r.stdout if r.returncode == 0 else None


def abrir(fonte: dict) -> int | None:
    url = fonte["url"]
    inicio = time.monotonic()
    resta = lambda: LIMITE_S - (time.monotonic() - inicio)
    if ".mpd" in url:
        corpo = baixar(url, fonte, resta())
        ok = bool(corpo) and b"<MPD" in corpo
    elif url.split("?")[0].endswith(".ts"):
        corpo = baixar(url, fonte, resta(), "0-65535")
        ok = bool(corpo) and len(corpo) > 1000
    else:
        ok = False
        alvo = url
        for _ in range(3):
            corpo = baixar(alvo, fonte, resta())
            if not corpo or not corpo.lstrip().startswith(b"#EXTM3U"):
                break
            linhas = [l.strip() for l in corpo.decode("utf-8", "replace").split("\n")]
            uris = [l for l in linhas if l and not l.startswith("#")]
            if not uris:
                break
            proxima = urljoin(alvo, uris[0])
            if "#EXT-X-STREAM-INF" in corpo.decode("utf-8", "replace"):
                alvo = proxima  # mestre: desce para a variante
                continue
            pedaco = baixar(proxima, fonte, resta(), "0-65535")
            # Servidor com token entrega o pedaço vazio a quem pede o mesmo
            # endereço duas vezes; responder 200 é o que conta para o tempo.
            ok = pedaco is not None
            break
    gasto = time.monotonic() - inicio
    return int(gasto * 1000) if ok and gasto <= LIMITE_S else None


def medir(fonte: dict) -> tuple[str, int | None]:
    servidor = fonte["url"].split("/")[2]
    with _trava:
        semaforo = _travas[servidor]
    with semaforo:
        try:
            return fonte["url"], abrir(fonte)
        except Exception:
            return fonte["url"], None


def main() -> None:
    canais = fontes_dos_canais()
    # O Nexus e, de cada servidor recente, a primeira fonte de cada canal:
    # a ordem entre servidores é o que se decide, não a de cada temporada.
    unicas: dict[str, dict] = {}
    for c in canais:
        vistos = set()
        for f in c["fontes"]:
            host = next((h for h in (NEXUS, *RECENTES) if h in f["url"]), None)
            if host and host not in vistos:
                vistos.add(host)
                unicas[f["url"]] = f
    print(f"{len(canais)} canais com Nexus, {len(unicas)} fontes para medir")
    resultado: dict[str, int | None] = {}
    with cf.ThreadPoolExecutor(32) as ex:
        for n, (url, ms) in enumerate(ex.map(medir, unicas.values()), 1):
            resultado[url] = ms
            if n % 100 == 0:
                print(f"  {n}/{len(unicas)}", flush=True)
    SAIDA.parent.mkdir(exist_ok=True)
    SAIDA.write_text(json.dumps(resultado, indent=0, ensure_ascii=False), encoding="utf-8")
    abriram = [v for v in resultado.values() if v is not None]
    print(f"abriram {len(abriram)} de {len(resultado)}; gravado em {SAIDA.relative_to(RAIZ)}")


if __name__ == "__main__":
    main()
