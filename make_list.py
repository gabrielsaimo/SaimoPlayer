#!/usr/bin/env python3
"""Escreve canais.txt, a lista que os dois apps baixam ao abrir.

Gerar do catálogo em vez de manter à mão é o que garante que a lista publicada e
a que os apps tocam sejam a mesma coisa. O formato é de uma linha por campo, para
continuar legível a olho e ainda assim carregar tudo o que um player precisa:
sem o referer, o agente e a chave, um terço do catálogo não toca.

O KID do ClearKey só existe no lado Android — o AVFoundation não o pede — então
ele é lido de lá para o arquivo publicado ter o par completo.
"""
import re
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SWIFT = ROOT / "Sources" / "Channels.swift"
KOTLIN = ROOT.parent / "SaimoTV-Android" / "app" / "src" / "main" / "java" / "br" / "com" / "saimo" / "tv" / "Catalog.kt"
OUT = ROOT / "canais.txt"

STRING = r'(?:nil|"(?:[^"\\]|\\.)*")'

CABECALHO = """# SAIMO TV — LISTA DE CANAIS
# {contagem} canais · {data}
#
# Os apps baixam este arquivo ao abrir, então trocar um link aqui basta: nada
# precisa ser recompilado nem reinstalado.
#
# Uma linha por campo, no formato "chave: valor".
#
#   canal:    começa um canal novo
#   logo:     imagem do canal (opcional)
#   fonte:    acrescenta uma fonte; a primeira é a preferida e o player desce
#             para a seguinte quando ela falha
#   referer:  cabeçalho Referer exigido por alguns CDNs
#   agente:   User-Agent exigido por alguns CDNs
#   chave:    ClearKey das fontes DASH, no formato KID:CHAVE em hexadecimal
#
# referer, agente e chave pertencem à fonte imediatamente acima delas.
# Linhas em branco e linhas começadas por # são ignoradas.
"""


def unquote(text):
    if text == "nil":
        return None
    return text[1:-1].replace('\\"', '"').replace("\\\\", "\\")


def key_ids():
    """URL -> KID, que só o catálogo Android guarda."""
    if not KOTLIN.exists():
        return {}
    text = KOTLIN.read_text(encoding="utf-8")
    pairs = {}
    for block in re.finditer(
            r'url = "((?:[^"\\]|\\.)*)",(.*?)\n            \)', text, re.S):
        found = re.search(r'keyId = "([0-9a-fA-F]+)"', block.group(2))
        if found:
            url = block.group(1).replace('\\"', '"').replace("\\$", "$")
            pairs[url] = found.group(1)
    return pairs


def channels(declaration):
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
        sources = []
        for item in source.finditer(match.group(3)):
            sources.append({
                "url": unquote(item.group(1)),
                "referer": unquote(item.group(2) or "nil"),
                "agente": unquote(item.group(3) or "nil"),
                "chave": unquote(item.group(4) or "nil"),
            })
        out.append({
            "nome": unquote(match.group(1)),
            "logo": unquote(match.group(2)),
            "fontes": sources,
        })
    return out


def main():
    listing = channels("private let catalog: [CatalogEntry] = [")
    kids = key_ids()
    faltando = []

    lines = [CABECALHO.format(contagem=len(listing),
                              data=date.today().strftime("%d/%m/%Y")), ""]
    for channel in listing:
        lines.append(f'canal: {channel["nome"]}')
        if channel["logo"]:
            lines.append(f'logo: {channel["logo"]}')
        for source in channel["fontes"]:
            lines.append(f'fonte: {source["url"]}')
            if source["referer"]:
                lines.append(f'referer: {source["referer"]}')
            if source["agente"]:
                lines.append(f'agente: {source["agente"]}')
            if source["chave"]:
                kid = kids.get(source["url"])
                if kid:
                    lines.append(f'chave: {kid}:{source["chave"]}')
                else:
                    faltando.append(f'{channel["nome"]}: {source["url"][:60]}')
        lines.append("")

    OUT.write_text("\n".join(lines), encoding="utf-8")
    fontes = sum(len(c["fontes"]) for c in listing)
    print(f"{OUT.name}: {len(listing)} canais, {fontes} fontes, "
          f"{sum(1 for c in listing for s in c['fontes'] if s['chave'])} com ClearKey")
    for item in faltando:
        print(f"  SEM KID (o canal não vai tocar no Android): {item}")


if __name__ == "__main__":
    main()
