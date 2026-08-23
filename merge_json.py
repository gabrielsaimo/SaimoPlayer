#!/usr/bin/env python3
"""Põe as fontes do offline.json na frente, quando elas respondem.

O arquivo é a lista de referência, então cada canal passa a tentar a fonte dele
primeiro. Mas metade dos links de lá está fora do ar, e um primeiro salto morto
custa segundos em toda troca de canal — então só sobe para a frente o que
responde agora. O que não responde vai para o fim da fila, onde o failover ainda
o alcança se voltar, sem atrapalhar quem está assistindo.

Rodar de novo é seguro: fontes repetidas são descartadas por URL.
"""
import json
import re
import subprocess
import unicodedata
import concurrent.futures as cf
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SWIFT = ROOT / "Sources" / "Channels.swift"
JSON = ROOT.parent / "SaimoTV-Android" / "scripts" / "offline.json"

# Nomes que diferem entre o nosso catálogo e o arquivo.
ALIAS = {
    "globorj": "globorio",
    "globosp": "globosaopaulo",
    "record": "recordtvsaopaulo",
}

STRING = r'(?:nil|"(?:[^"\\]|\\.)*")'


def norm(text):
    text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode().lower()
    return re.sub(r"[^a-z0-9]", "", text)


def unquote(text):
    return None if text == "nil" else text[1:-1]


def swift_string(value):
    if value is None:
        return "nil"
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def parse_catalog(text, declaration):
    start = text.index(declaration) + len(declaration)
    end = text.index("\n]", start)
    entry = re.compile(
        r'CatalogEntry\(\s*name:\s*(' + STRING + r'),\s*'
        r'logo:\s*(' + STRING + r'),\s*sources:\s*\[(.*?)\n        \]\)', re.S)
    source = re.compile(
        r'Source\(url:\s*(' + STRING + r'),\s*'
        r'(?:referer:\s*(' + STRING + r'),\s*)?'
        r'(?:userAgent:\s*(' + STRING + r'),\s*)?'
        r'(?:clearKey:\s*(' + STRING + r'))?\s*\)', re.S)
    out = []
    for match in entry.finditer(text[start:end]):
        out.append({
            "nome": unquote(match.group(1)),
            "logo": unquote(match.group(2)),
            "fontes": [{
                "url": unquote(s.group(1)),
                "referer": unquote(s.group(2) or "nil"),
                "agente": unquote(s.group(3) or "nil"),
                "chave": unquote(s.group(4) or "nil"),
            } for s in source.finditer(match.group(3))],
        })
    return out, start, end


def json_source(channel):
    stream = channel["streams"][0]
    headers = stream.get("headers") or {}
    raw = (channel.get("drm_system") or {}).get("clearKey") or ""
    chave = None
    if raw:
        try:
            pair = json.loads(raw)
            kid, key = next(iter(pair.items()))
            chave = f"{kid}:{key}"
        except Exception:
            chave = None
    return {
        "url": stream["url"],
        "referer": headers.get("referer") or None,
        "agente": headers.get("user-agent") or None,
        "chave": chave,
    }


def alive(source):
    cmd = ["curl", "-s", "-o", "/dev/null", "--max-time", "25", "-L",
           "--doh-url", "https://1.1.1.1/dns-query", "-w", "%{http_code}"]
    if source["agente"]:
        cmd += ["-A", source["agente"]]
    if source["referer"]:
        cmd += ["-e", source["referer"]]
    cmd += [source["url"]]
    try:
        code = subprocess.run(cmd, capture_output=True, text=True, timeout=40).stdout.strip()
    except Exception:
        code = "000"
    return code.startswith("2")


def render(channel):
    lines = ["    CatalogEntry(",
             f'        name: {swift_string(channel["nome"])},',
             f'        logo: {swift_string(channel["logo"])},',
             "        sources: ["]
    for source in channel["fontes"]:
        lines.append(f'            Source(url: {swift_string(source["url"])},')
        lines.append(f'                   referer: {swift_string(source["referer"])},')
        lines.append(f'                   userAgent: {swift_string(source["agente"])},')
        lines.append(f'                   clearKey: {swift_string(source["chave"])}),')
    lines.append("        ]),")
    return "\n".join(lines)


def main():
    text = SWIFT.read_text(encoding="utf-8")
    catalog, start, end = parse_catalog(text, "private let catalog: [CatalogEntry] = [")
    reference = {norm(c["name"]): c for c in json.load(JSON.open(encoding="utf-8"))["data"]}

    candidatos = {}
    for channel in catalog:
        key = ALIAS.get(norm(channel["nome"]), norm(channel["nome"]))
        found = reference.get(key)
        if found:
            candidatos[channel["nome"]] = json_source(found)

    print(f"testando {len(candidatos)} fontes do offline.json…")
    with cf.ThreadPoolExecutor(max_workers=12) as pool:
        vivos = dict(zip(candidatos, pool.map(alive, candidatos.values())))

    promovidos, adiados, sem_referencia = [], [], []
    for channel in catalog:
        nova = candidatos.get(channel["nome"])
        if not nova:
            sem_referencia.append(channel["nome"])
            continue
        restantes = [s for s in channel["fontes"] if s["url"] != nova["url"]]
        if vivos[channel["nome"]]:
            channel["fontes"] = [nova] + restantes
            promovidos.append(channel["nome"])
        else:
            channel["fontes"] = restantes + [nova]
            adiados.append(channel["nome"])

    corpo = "\n".join(render(c) for c in catalog)
    SWIFT.write_text(text[:start] + "\n" + corpo + text[end:], encoding="utf-8")

    print(f"json na frente: {len(promovidos)}")
    print(f"json no fim (não respondeu agora): {len(adiados)} — {', '.join(adiados)}")
    print(f"sem entrada no json: {len(sem_referencia)} — {', '.join(sem_referencia)}")
    print(f"fontes no total: {sum(len(c['fontes']) for c in catalog)}")


if __name__ == "__main__":
    main()
