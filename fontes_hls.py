#!/usr/bin/env python3
"""Troca as fontes `.ts` das contas Xtream pela versão HLS do mesmo canal.

Uma conta Xtream entrega o canal de dois jeitos:

    http://servidor/usuario/senha/152014.ts            fluxo contínuo
    http://servidor/live/usuario/senha/152014.m3u8     HLS, em pedaços

O fluxo contínuo é cortado pelo servidor a cada poucos segundos (medido em
10/10/2026: 11 de 16 fontes de quatro servidores fecharam a conexão antes de
25 s), e cada corte faz o app reconectar — o canal "recarregando toda hora",
como o das Câmeras Escondidas. O HLS do mesmo canal veio inteiro nas 16: são
pedaços de dois ou três segundos pedidos um a um, e não há conexão longa
para o servidor derrubar.

Só troca a fonte cujo HLS responde com uma playlist de verdade agora; a que
não responde fica como estava. Os atributos da fonte (qualidade, nome,
referer...) ficam junto dela. Rodar de novo é seguro.

    python3 fontes_hls.py              só relatório
    python3 fontes_hls.py --aplicar    grava no catalogo.txt
"""
import argparse
import collections
import concurrent.futures as cf
import re
import subprocess
import threading
from pathlib import Path

CATALOGO = Path(__file__).parent / "catalogo.txt"
XTREAM_TS = re.compile(r"^(http://[^/]+)/([^/]+)/([^/]+)/(\d+)\.ts$")
AGENTE = "Mozilla/5.0"
POR_SERVIDOR = 2

_travas: dict[str, threading.Semaphore] = collections.defaultdict(lambda: threading.Semaphore(POR_SERVIDOR))
_trava = threading.Lock()


def hls_de(url: str) -> str | None:
    achado = XTREAM_TS.match(url)
    if not achado:
        return None
    base, usuario, senha, canal = achado.groups()
    return f"{base}/live/{usuario}/{senha}/{canal}.m3u8"


def responde(url: str) -> bool:
    """A playlist chega e tem pedaços: não basta o 200."""
    servidor = url.split("/")[2]
    with _trava:
        semaforo = _travas[servidor]
    with semaforo:
        corpo = subprocess.run(
            ["curl", "-s", "-L", "--max-time", "15", "-A", AGENTE, url],
            capture_output=True, text=True, errors="replace").stdout
    return corpo.startswith("#EXTM3U") and "#EXTINF" in corpo


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--aplicar", action="store_true")
    args = ap.parse_args()

    linhas = CATALOGO.read_text(encoding="utf-8").split("\n")
    candidatas = {l[6:].strip() for l in linhas if l.startswith("fonte:") and hls_de(l[6:].strip())}
    print(f"{len(candidatas)} fontes .ts de conta Xtream")
    with cf.ThreadPoolExecutor(24) as ex:
        resultado = dict(zip(candidatas, ex.map(lambda u: responde(hls_de(u)), candidatas)))

    trocadas = {u: hls_de(u) for u, ok in resultado.items() if ok}
    por_servidor = collections.Counter(u.split("/")[2] for u in trocadas)
    print(f"HLS respondeu em {len(trocadas)}; ficam como estão {len(candidatas) - len(trocadas)}")
    for servidor, n in por_servidor.most_common():
        print(f"  {n:5d}  {servidor}")
    if args.aplicar:
        saida = [f"fonte: {trocadas[l[6:].strip()]}" if l.startswith("fonte:") and l[6:].strip() in trocadas else l
                 for l in linhas]
        CATALOGO.write_text("\n".join(saida), encoding="utf-8")
        print("catalogo.txt atualizado")


if __name__ == "__main__":
    main()
