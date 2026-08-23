#!/usr/bin/env python3
"""Testa toda fonte de todo canal e diz quais canais não têm nenhuma viva.

Testa a lista que os apps realmente tocam: o catalogo.txt somado aos extras do
canais.txt, casados por nome. Testar só o catálogo daria uma lista errada — o
Adult Swim, por exemplo, está morto no catálogo e vivo pelo extra.

Um canal com várias fontes só está realmente quebrado quando todas falham — é
essa lista que interessa para trocar link. As demais o failover resolve sozinho.

Alcançável não é o mesmo que tocável: uma fonte DASH pode responder e ainda não
tocar por causa da chave. Mas uma que não responde está morta com certeza, e é
disso que trata o relatório.
"""
import json
import re
import socket
import subprocess
import concurrent.futures as cf
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parent
SWIFT = ROOT / "Sources" / "Channels.swift"
OUT = ROOT / "build" / "fontes-mortas.txt"

STRING = r'(?:nil|"(?:[^"\\]|\\.)*")'


def unquote(text):
    return None if text == "nil" else text[1:-1]


def catalog(declaration):
    text = SWIFT.read_text(encoding="utf-8")
    start = text.index(declaration) + len(declaration)
    text = text[start:text.index("\n]", start)]
    entry = re.compile(
        r'CatalogEntry\(\s*name:\s*(' + STRING + r'),\s*'
        r'logo:\s*(' + STRING + r'),\s*sources:\s*\[(.*?)\n        \]\)', re.S)
    source = re.compile(
        r'Source\(url:\s*(' + STRING + r'),\s*'
        r'(?:referer:\s*(' + STRING + r'),\s*)?'
        r'(?:userAgent:\s*(' + STRING + r'),\s*)?'
        r'(?:clearKey:\s*(' + STRING + r'))?\s*\)', re.S)
    out = []
    for match in entry.finditer(text):
        out.append((unquote(match.group(1)), [{
            "url": unquote(s.group(1)),
            "referer": unquote(s.group(2) or "nil"),
            "agente": unquote(s.group(3) or "nil"),
        } for s in source.finditer(match.group(3))]))
    return out


def resolver(host):
    """IP do host, pelo resolvedor do sistema e, se ele falhar, por DoH.

    O resolvedor desta rede bloqueia o host das fontes assinadas — foi o que
    obrigou o app a falar DoH. Sem repetir isso aqui, o teste marcaria como
    morto o que é só DNS filtrado.
    """
    try:
        return socket.gethostbyname(host)
    except OSError:
        pass
    try:
        out = subprocess.run(
            ["curl", "-s", "--max-time", "15", "-H", "accept: application/dns-json",
             f"https://1.1.1.1/dns-query?name={host}&type=A"],
            capture_output=True, text=True, timeout=25).stdout
        for resposta in json.loads(out).get("Answer", []):
            if resposta.get("type") == 1:
                return resposta["data"]
    except Exception:
        pass
    return None


def testar(item):
    nome, indice, fonte, enderecos = item
    cmd = ["curl", "-s", "-o", "/dev/null", "--max-time", "25", "-L",
           "-r", "0-4096", "-w", "%{http_code}"]
    alvo = urlparse(fonte["url"])
    ip = enderecos.get(alvo.hostname)
    if ip:
        porta = alvo.port or (443 if alvo.scheme == "https" else 80)
        cmd += ["--resolve", f"{alvo.hostname}:{porta}:{ip}"]
    if fonte["agente"]:
        cmd += ["-A", fonte["agente"]]
    if fonte["referer"]:
        cmd += ["-e", fonte["referer"]]
    cmd += [fonte["url"]]
    try:
        code = subprocess.run(cmd, capture_output=True, text=True, timeout=40).stdout.strip()
    except Exception:
        code = "000"
    return nome, indice, fonte["url"], code


def normalizar(nome):
    import unicodedata
    texto = unicodedata.normalize("NFKD", nome).encode("ascii", "ignore").decode().lower()
    return re.sub(r"[^a-z0-9]", "", texto)


def extras():
    """Canais do canais.txt publicado, que é um M3U."""
    caminho = ROOT / "canais.txt"
    if not caminho.exists():
        return {}
    out, nome, logo = {}, None, None
    for linha in caminho.read_text(encoding="utf-8").splitlines():
        linha = linha.strip()
        if linha.startswith("#EXTINF:"):
            marca = re.search(r'tvg-id="([^"]+)"', linha)
            bruto = linha.split(",", 1)[-1].strip()
            nome = marca.group(1) if marca else re.sub(r"\s*\([^)]+\)$", "", bruto).strip()
        elif linha and not linha.startswith("#") and nome:
            out.setdefault(normalizar(nome), []).append(
                {"url": linha, "referer": None, "agente": None})
    return out


def main():
    canais = catalog("private let catalog: [CatalogEntry] = [")
    canais += catalog("private let restrictedCatalog: [CatalogEntry] = [")

    # Mesma junção que os apps fazem: extras entram atrás, por nome.
    publicados = extras()
    usados = set()
    juntos = []
    for nome, fontes in canais:
        chave = normalizar(nome)
        vindas = publicados.get(chave, [])
        usados.add(chave)
        conhecidas = {f["url"] for f in fontes}
        juntos.append((nome, fontes + [f for f in vindas if f["url"] not in conhecidas]))
    for chave, fontes in publicados.items():
        if chave not in usados:
            juntos.append((chave, fontes))
    canais = juntos
    hosts = {urlparse(f["url"]).hostname for _, fontes in canais for f in fontes}
    hosts.discard(None)
    print(f"resolvendo {len(hosts)} servidores…")
    with cf.ThreadPoolExecutor(max_workers=16) as pool:
        enderecos = {h: ip for h, ip in zip(hosts, pool.map(resolver, hosts)) if ip}
    sem_dns = sorted(hosts - set(enderecos))
    if sem_dns:
        print(f"  sem DNS: {', '.join(sem_dns)}")

    tarefas = [(nome, i, f, enderecos) for nome, fontes in canais for i, f in enumerate(fontes)]
    print(f"testando {len(tarefas)} fontes de {len(canais)} canais…")

    resultados = {}
    with cf.ThreadPoolExecutor(max_workers=16) as pool:
        for nome, indice, url, code in pool.map(testar, tarefas):
            resultados.setdefault(nome, []).append((indice, url, code))

    mortos, mancos, ok = [], [], []
    for nome, fontes in canais:
        linhas = sorted(resultados.get(nome, []))
        vivas = [l for l in linhas if l[2].startswith("2")]
        if not vivas:
            mortos.append((nome, linhas))
        elif len(vivas) < len(linhas):
            mancos.append((nome, len(vivas), len(linhas)))
        else:
            ok.append(nome)

    texto = [
        "SAIMO TV — FONTES QUE NÃO RESPONDEM",
        f"{len(canais)} canais · {len(tarefas)} fontes testadas",
        "",
        "Alcançável não é o mesmo que tocável: uma fonte DASH pode responder e",
        "ainda assim não tocar por causa da chave. Mas a que não responde está",
        "morta com certeza.",
        "",
        "=" * 72,
        "",
        f"SEM NENHUMA FONTE VIVA — {len(mortos)} canais, estes precisam de link novo",
        "",
    ]
    for nome, linhas in mortos:
        texto.append(f"  {nome}")
        for indice, url, code in linhas:
            texto.append(f"      [{code}] fonte {indice + 1}: {url}")
        texto.append("")

    texto += ["", f"COM ALGUMA FONTE MORTA, MAS FUNCIONANDO — {len(mancos)} canais", ""]
    for nome, vivas, total in mancos:
        texto.append(f"  {nome}: {vivas} de {total} fontes respondem")

    texto += ["", f"TODAS AS FONTES RESPONDEM — {len(ok)} canais", "",
              "  " + ", ".join(ok)]

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(texto), encoding="utf-8")
    print(f"sem nenhuma fonte viva: {len(mortos)}")
    for nome, _ in mortos:
        print(f"  {nome}")
    print(f"relatório: {OUT}")


if __name__ == "__main__":
    main()
