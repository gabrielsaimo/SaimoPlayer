#!/usr/bin/env python3
"""Testa todas as fontes do catálogo de canais e tira as que não funcionam.

Cada fonte é pedida do jeito que o app pede: o mesmo User-Agent (ou o
`agente:` da fonte), o `referer:` quando houver, seguindo redirecionamentos.
Só conta como viva a que entrega o que promete:

    playlist (.m3u8, .txt)   a resposta começa a playlist (#EXTM3U)
    DASH (.mpd)              a resposta traz o manifesto (<MPD)
    o resto (.ts, sem tipo)  chegam bytes de vídeo, e não uma página HTML

Os servidores das listas são contas Xtream e rajada vira bloqueio, então há
limite de conexões por servidor. Toda fonte que falha é testada de novo no
fim, depois de uma pausa e uma por servidor: só a que falha duas vezes é
morta. Servidor que recusa tudo (conexão recusada em todas) é tratado como
fora do ar, e não como engano do teste.

Erro que passa sozinho não mata fonte: servidor sobrecarregado (HTTP 429, 5xx)
e servidor desativado no painel do monitor (que os apps já escondem) ficam.

    python3 limpar_canais.py              só relatório
    python3 limpar_canais.py --aplicar    tira as mortas do catalogo.txt; canal
                                          que fica sem fonte sai da lista

Relatório em arquivos-gerados/limpeza-canais/.
"""
import argparse
import collections
import concurrent.futures as cf
import threading
import subprocess
import time
from pathlib import Path

PASTA = Path(__file__).parent
CATALOGO = PASTA / "catalogo.txt"
SAIDA = PASTA / "arquivos-gerados" / "limpeza-canais"

AGENTE = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
          "(KHTML, like Gecko) Version/18.0 Safari/605.1.15")
ATRIBUTOS = ("qualidade:", "referer:", "agente:", "chave:", "nome:")
POR_SERVIDOR = 6
TEMPO = 12

_travas: dict[str, threading.Semaphore] = collections.defaultdict(lambda: threading.Semaphore(POR_SERVIDOR))
_travas_lock = threading.Lock()


def servidor(url: str) -> str:
    return url.split("://", 1)[-1].split("/", 1)[0].lower()


def trava(host: str) -> threading.Semaphore:
    with _travas_lock:
        return _travas[host]


def testar(url: str, referer: str | None, agente: str | None) -> tuple[bool, str]:
    """(viva, motivo). Pelo curl com --max-time: a biblioteca do Python deixava
    conexão presa em transmissão lenta passar horas sem desistir."""
    caminho = url.split("?", 1)[0].lower()
    playlist = caminho.endswith((".m3u8", ".m3u", ".txt")) or "m3u8" in caminho
    dash = caminho.endswith(".mpd")
    # Cabeçalhos e corpo no mesmo fluxo; lidos 4 KB do corpo, a conexão é
    # fechada. Transmissão ao vivo ignora o pedido de "só o começo" e mandaria
    # vídeo sem fim até o tempo esgotar.
    cmd = ["curl", "-s", "-L", "-D", "-", "--max-time", str(TEMPO),
           "-A", agente or AGENTE, "-H", "Accept: */*", "-o", "-"]
    if referer:
        cmd += ["-e", referer]
    if not playlist and not dash:
        cmd += ["-r", "0-4095"]
    with trava(servidor(url)):
        proc = subprocess.Popen(cmd + [url], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        dados = b""
        limite = time.time() + TEMPO + 2
        try:
            while time.time() < limite:
                pedaco = proc.stdout.read1(65536) if hasattr(proc.stdout, "read1") else proc.stdout.read(4096)
                if not pedaco:
                    break
                dados += pedaco
                # Último bloco de cabeçalhos (depois de redirecionamentos) + 4 KB.
                fim_cab = dados.rfind(b"\r\n\r\nHTTP/")
                inicio = dados.find(b"\r\n\r\n", fim_cab + 4 if fim_cab >= 0 else 0)
                if inicio >= 0 and len(dados) - inicio - 4 >= 4096:
                    break
        finally:
            proc.kill()
            proc.wait()
    blocos = dados.split(b"\r\n\r\n")
    cabecalhos, corpo = b"", b""
    for n, bloco in enumerate(blocos):
        if bloco.startswith(b"HTTP/"):
            cabecalhos = bloco
            corpo = b"\r\n\r\n".join(blocos[n + 1:])
    if not cabecalhos:
        return False, "sem conexão"
    linhas_cab = cabecalhos.decode("latin-1").split("\r\n")
    codigo = linhas_cab[0].split(" ")[1] if len(linhas_cab[0].split(" ")) > 1 else "0"
    tipo = next((l.split(":", 1)[1].strip().lower() for l in linhas_cab
                 if l.lower().startswith("content-type:")), "")
    if not codigo.isdigit() or int(codigo) >= 400 or int(codigo) == 0:
        return False, f"HTTP {codigo}"
    texto = corpo[:4096].decode("utf-8", "replace")
    if playlist:
        return ("#EXTM3U" in texto), ("ok" if "#EXTM3U" in texto else "não é playlist")
    if dash:
        return ("<MPD" in texto), ("ok" if "<MPD" in texto else "não é DASH")
    if "text/html" in tipo or texto.lstrip().lower().startswith(("<!doctype", "<html")):
        return False, "página no lugar do vídeo"
    if "#EXTM3U" in texto:
        return True, "ok"
    return (len(corpo) >= 188), ("ok" if len(corpo) >= 188 else "vazio")


def desativados() -> set[str]:
    """Servidores desligados no painel do monitor: decisão de quem cuida dele."""
    global _desativados
    if _desativados is None:
        try:
            import json, urllib.request
            pedido = urllib.request.Request("https://saimo-monitor.gabrielsaimo68.workers.dev/v1/fontes",
                                            headers={"User-Agent": AGENTE})
            with urllib.request.urlopen(pedido, timeout=15) as r:
                _desativados = {h.lower() for h in json.load(r).get("desativados", [])}
        except Exception:
            _desativados = set()
    return _desativados


_desativados: set[str] | None = None


def ler() -> list[str]:
    return CATALOGO.read_text(encoding="utf-8").split("\n")


def fontes_do_catalogo(linhas: list[str]) -> dict[tuple, list[str]]:
    """(url, referer, agente) -> canais que usam."""
    out: dict[tuple, list[str]] = collections.defaultdict(list)
    canal = ""
    atual = None
    for linha in linhas + ["canal: fim"]:
        if linha.startswith(("canal:", "fonte:")) and atual:
            out[(atual["url"], atual.get("referer"), atual.get("agente"))].append(canal)
            atual = None
        if linha.startswith("canal:"):
            canal = linha[6:].strip()
        elif linha.startswith("fonte:"):
            atual = {"url": linha[6:].strip()}
        elif atual and linha.startswith(("referer:", "agente:")):
            chave, valor = linha.split(":", 1)
            atual[chave] = valor.strip()
    return out


def aplicar(linhas: list[str], mortas: set[str]) -> tuple[list[str], list[str]]:
    """Tira as fontes mortas; canal sem fonte nenhuma sai inteiro."""
    saida, removidos = [], []
    i = 0
    while i < len(linhas):
        if not linhas[i].startswith("canal:"):
            saida.append(linhas[i])
            i += 1
            continue
        j = i + 1
        while j < len(linhas) and not linhas[j].startswith("canal:"):
            j += 1
        bloco = linhas[i:j]
        novo, tinha, sobrou = [], 0, 0
        k = 0
        while k < len(bloco):
            if bloco[k].startswith("fonte:"):
                fonte = [bloco[k]]
                k += 1
                while k < len(bloco) and bloco[k].startswith(ATRIBUTOS):
                    fonte.append(bloco[k])
                    k += 1
                tinha += 1
                if fonte[0][6:].strip() in mortas:
                    continue
                sobrou += 1
                novo += fonte
            else:
                novo.append(bloco[k])
                k += 1
        if tinha and not sobrou:
            removidos.append(bloco[0][6:].strip())
            # As linhas em branco entre canais ficam, para o arquivo não grudar.
            saida += [l for l in bloco if not l.strip()][:1]
        else:
            saida += novo
        i = j
    return saida, removidos


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--aplicar", action="store_true")
    ap.add_argument("--pausa", type=int, default=30)
    args = ap.parse_args()

    linhas = ler()
    fontes = fontes_do_catalogo(linhas)
    print(f"{len(fontes)} fontes em teste")
    resultado: dict[tuple, tuple[bool, str]] = {}
    with cf.ThreadPoolExecutor(64) as ex:
        futuros = {ex.submit(testar, *f): f for f in fontes}
        for n, fut in enumerate(cf.as_completed(futuros), 1):
            resultado[futuros[fut]] = fut.result()
            if n % 500 == 0:
                print(f"  {n}/{len(fontes)}", flush=True)

    falhas = [f for f, (viva, _) in resultado.items() if not viva]
    print(f"primeira passada: {len(falhas)} falharam; confirmando depois de {args.pausa}s")
    time.sleep(args.pausa)
    global POR_SERVIDOR
    POR_SERVIDOR = 2
    _travas.clear()
    with cf.ThreadPoolExecutor(32) as ex:
        for n, (f, r) in enumerate(zip(falhas, ex.map(lambda f: testar(*f), falhas)), 1):
            resultado[f] = r
            if n % 100 == 0:
                print(f"  confirmação: {n}/{len(falhas)}", flush=True)

    # Erro passageiro não mata: a fonte volta quando o servidor se recupera.
    def passageiro(motivo):
        return motivo == "HTTP 429" or motivo.startswith("HTTP 5")
    mortas = {f[0] for f, (viva, motivo) in resultado.items()
              if not viva and not passageiro(motivo) and servidor(f[0]) not in desativados()}
    vivas_por_url = {f[0] for f, (viva, _) in resultado.items() if viva}
    mortas -= vivas_por_url  # a mesma URL viva com outro cabeçalho não morre

    SAIDA.mkdir(parents=True, exist_ok=True)
    por_servidor = collections.Counter(servidor(u) for u in mortas)
    motivos = collections.Counter(r for f, (v, r) in resultado.items() if not v)
    with open(SAIDA / "mortas.tsv", "w", encoding="utf-8") as arq:
        for f, (viva, motivo) in sorted(resultado.items()):
            if not viva and f[0] in mortas:
                arq.write(f"{f[0]}\t{motivo}\t{', '.join(sorted(set(fontes[f])))}\n")

    novas, removidos = aplicar(linhas, mortas)
    relatorio = [
        f"fontes testadas: {len(fontes)}",
        f"mortas (confirmadas duas vezes): {len(mortas)}",
        f"canais que ficariam sem fonte e saem: {len(removidos)}",
        "", "mortas por servidor:",
        *[f"  {n:5d}  {h}" for h, n in por_servidor.most_common()],
        "", "motivos:", *[f"  {n:5d}  {m}" for m, n in motivos.most_common()],
        "", "canais que saem:", *[f"  {c}" for c in removidos],
    ]
    (SAIDA / "relatorio.txt").write_text("\n".join(relatorio) + "\n", encoding="utf-8")
    print("\n".join(relatorio[:12]))
    if args.aplicar:
        texto = "\n".join(novas)
        while "\n\n\n" in texto:  # canal que sai deixa a linha em branco dele
            texto = texto.replace("\n\n\n", "\n\n")
        CATALOGO.write_text(texto, encoding="utf-8")
        print("catalogo.txt atualizado")


if __name__ == "__main__":
    main()
