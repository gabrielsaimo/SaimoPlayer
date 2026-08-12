#!/usr/bin/env python3
"""Escreve a lista de canais em texto puro, a partir do próprio catálogo.

Gerar do código em vez de manter à mão é o que garante que a lista entregue e a
que o app toca sejam a mesma coisa.
"""
import re
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SWIFT = ROOT / "Sources" / "Channels.swift"
OUT = ROOT / "build" / "canais.txt"

STRING = r'(?:nil|"(?:[^"\\]|\\.)*")'


def unquote(text):
    return None if text == "nil" else text[1:-1]


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
        sources = [(unquote(s.group(1)), unquote(s.group(4) or "nil"))
                   for s in source.finditer(match.group(3))]
        out.append((unquote(match.group(1)), sources))
    return out


def main():
    listing = channels("private let catalog: [CatalogEntry] = [")
    lines = [
        "SAIMO TV — LISTA DE CANAIS",
        f"{len(listing)} canais · gerado em {date.today().strftime('%d/%m/%Y')}",
        "",
        "Cada canal traz suas fontes em ordem de preferência: o player desce",
        "para a seguinte quando a primeira falha. As marcadas com [DRM] são",
        "DASH com ClearKey e não tocam em player comum sem a chave.",
        "",
        "=" * 72,
        "",
    ]
    for number, (name, sources) in enumerate(listing, start=1):
        lines.append(f"{number:>3}. {name}")
        for url, key in sources:
            tag = " [DRM]" if key else ""
            lines.append(f"     {url}{tag}")
        lines.append("")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(lines), encoding="utf-8")
    print(f"{OUT} — {len(listing)} canais")


if __name__ == "__main__":
    main()
