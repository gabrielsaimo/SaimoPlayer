#!/usr/bin/env python3
"""Escreve catalogo.txt, o catálogo inteiro em texto.

É separado do canais.txt publicado de propósito: aquele é a lista de extras, em
M3U, e um M3U não tem onde guardar chave de ClearKey, Referer nem User-Agent.
Este aqui carrega tudo, e é o que vale publicar quando essas fontes precisarem
viajar sem recompilar nada. O formato é de uma linha por campo, para
continuar legível a olho e ainda assim carregar tudo o que um player precisa:
sem o referer, o agente e a chave, um terço do catálogo não toca.

O catálogo guarda o ClearKey como KID:CHAVE, que é o que este arquivo publica:
o AVFoundation usa só a chave, o ExoPlayer precisa das duas metades.
"""
import re
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SWIFT = ROOT / "Sources" / "Channels.swift"
OUT = ROOT / "catalogo.txt"

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
                if source["chave"].count(":") == 1:
                    lines.append(f'chave: {source["chave"]}')
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
