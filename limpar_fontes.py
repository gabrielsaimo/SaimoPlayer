#!/usr/bin/env python3
"""Acrescenta fontes novas e tira do catálogo as que não respondem mais.

Fonte morta não é inofensiva: ela é tentada primeiro, atrasa a abertura do canal
em segundos e ainda esconde a que funciona atrás dela. Sai do catálogo.

O corte é por resposta agora, com a mesma resolução por DoH que o app usa —
senão o que é DNS filtrado passaria por link morto. Um canal nunca fica sem
nenhuma fonte: se todas caírem, a primeira é mantida para o canal continuar na
lista e voltar sozinho quando o servidor voltar.

Uso:
    python3 limpar_fontes.py [arquivo-com-links-novos]

O arquivo é opcional, uma linha por fonte nova, no formato NOME|URL.
"""
import json
import re
import socket
import subprocess
import sys
import concurrent.futures as cf
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parent
SWIFT = ROOT / "Sources" / "Channels.swift"

STRING = r'(?:nil|"(?:[^"\\]|\\.)*")'
CATALOGO = "private let catalog: [CatalogEntry] = ["
RESERVADO = "private let restrictedCatalog: [CatalogEntry] = ["


def unquote(text):
    return None if text == "nil" else text[1:-1]


def swift_string(value):
    if value is None:
        return "nil"
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def secao(text, declaration):
    inicio = text.index(declaration) + len(declaration)
    return inicio, text.index("\n]", inicio)


def ler(text, declaration):
    inicio, fim = secao(text, declaration)
    entrada = re.compile(
        r'CatalogEntry\(\s*name:\s*(' + STRING + r'),\s*'
        r'logo:\s*(' + STRING + r'),\s*sources:\s*\[(.*?)\n        \]\)', re.S)
    fonte = re.compile(
        r'Source\(url:\s*(' + STRING + r'),\s*'
        r'(?:referer:\s*(' + STRING + r'),\s*)?'
        r'(?:userAgent:\s*(' + STRING + r'),\s*)?'
        r'(?:clearKey:\s*(' + STRING + r'))?\s*\)', re.S)
    out = []
    for match in entrada.finditer(text[inicio:fim]):
        out.append({
            "nome": unquote(match.group(1)),
            "logo": unquote(match.group(2)),
            "fontes": [{
                "url": unquote(f.group(1)),
                "referer": unquote(f.group(2) or "nil"),
                "agente": unquote(f.group(3) or "nil"),
                "chave": unquote(f.group(4) or "nil"),
            } for f in fonte.finditer(match.group(3))],
        })
    return out


def render(canal):
    linhas = ["    CatalogEntry(",
              f'        name: {swift_string(canal["nome"])},',
              f'        logo: {swift_string(canal["logo"])},',
              "        sources: ["]
    for f in canal["fontes"]:
        linhas.append(f'            Source(url: {swift_string(f["url"])},')
        linhas.append(f'                   referer: {swift_string(f["referer"])},')
        linhas.append(f'                   userAgent: {swift_string(f["agente"])},')
        linhas.append(f'                   clearKey: {swift_string(f["chave"])}),')
    linhas.append("        ]),")
    return "\n".join(linhas)


def resolver(host):
    try:
        return socket.gethostbyname(host)
    except OSError:
        pass
    try:
        saida = subprocess.run(
            ["curl", "-s", "--max-time", "15", "-H", "accept: application/dns-json",
             f"https://1.1.1.1/dns-query?name={host}&type=A"],
            capture_output=True, text=True, timeout=25).stdout
        for resposta in json.loads(saida).get("Answer", []):
            if resposta.get("type") == 1:
                return resposta["data"]
    except Exception:
        pass
    return None


def responde(item):
    fonte, enderecos = item
    alvo = urlparse(fonte["url"])
    ip = enderecos.get(alvo.hostname)
    if not ip:
        return fonte["url"], "000"
    porta = alvo.port or (443 if alvo.scheme == "https" else 80)
    cmd = ["curl", "-s", "-o", "/dev/null", "--max-time", "25", "-L",
           "--resolve", f"{alvo.hostname}:{porta}:{ip}", "-r", "0-4096",
           "-w", "%{http_code}"]
    if fonte["agente"]:
        cmd += ["-A", fonte["agente"]]
    if fonte["referer"]:
        cmd += ["-e", fonte["referer"]]
    cmd += [fonte["url"]]
    try:
        return fonte["url"], subprocess.run(cmd, capture_output=True, text=True,
                                            timeout=40).stdout.strip()
    except Exception:
        return fonte["url"], "000"


def main():
    texto = SWIFT.read_text(encoding="utf-8")
    catalogo = ler(texto, CATALOGO)
    reservado = ler(texto, RESERVADO)
    por_nome = {c["nome"]: c for c in catalogo + reservado}

    # 1. As fontes novas entram na frente, que é onde se quer que sejam tentadas.
    novos = []
    if len(sys.argv) > 1:
        for linha in Path(sys.argv[1]).read_text(encoding="utf-8").splitlines():
            if not linha.strip():
                continue
            nome, url = linha.split("|", 1)
            canal = por_nome.get(nome.strip())
            if canal is None:
                print(f"  canal desconhecido, ignorado: {nome}")
                continue
            url = url.strip()
            canal["fontes"] = [{"url": url, "referer": None, "agente": None, "chave": None}] \
                + [f for f in canal["fontes"] if f["url"] != url]
            novos.append(nome.strip())
    if novos:
        print(f"fontes novas na frente: {len(novos)}")

    # 2. Testar tudo o que restou.
    todas = [f for c in catalogo + reservado for f in c["fontes"]]
    hosts = {urlparse(f["url"]).hostname for f in todas} - {None}
    print(f"resolvendo {len(hosts)} servidores…")
    with cf.ThreadPoolExecutor(max_workers=16) as pool:
        enderecos = {h: ip for h, ip in zip(hosts, pool.map(resolver, hosts)) if ip}

    print(f"testando {len(todas)} fontes…")
    with cf.ThreadPoolExecutor(max_workers=16) as pool:
        codigos = dict(pool.map(responde, [(f, enderecos) for f in todas]))

    # 3. Podar. Um canal nunca fica sem nenhuma fonte.
    removidas, orfaos = 0, []
    for canal in catalogo + reservado:
        vivas = [f for f in canal["fontes"] if codigos.get(f["url"], "000").startswith("2")]
        if vivas:
            removidas += len(canal["fontes"]) - len(vivas)
            canal["fontes"] = vivas
        else:
            removidas += len(canal["fontes"]) - 1
            canal["fontes"] = canal["fontes"][:1]
            orfaos.append(canal["nome"])

    inicio_c, fim_c = secao(texto, CATALOGO)
    inicio_r, fim_r = secao(texto, RESERVADO)
    corpo_c = "\n" + "\n".join(render(c) for c in catalogo)
    corpo_r = "\n" + "\n".join(render(c) for c in reservado) if reservado else ""
    # De trás para a frente, senão o segundo recorte usaria índices deslocados.
    texto = texto[:inicio_r] + corpo_r + texto[fim_r:]
    texto = texto[:inicio_c] + corpo_c + texto[fim_c:]
    SWIFT.write_text(texto, encoding="utf-8")

    restantes = sum(len(c["fontes"]) for c in catalogo + reservado)
    print(f"fontes removidas: {removidas} | restantes: {restantes}")
    print(f"canais sem nenhuma fonte viva ({len(orfaos)}), ficaram com a primeira:")
    for nome in orfaos:
        print(f"  {nome}")


if __name__ == "__main__":
    main()
