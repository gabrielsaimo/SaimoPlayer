#!/usr/bin/env python3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PUBLICADO = ROOT

SWIFT = ROOT / "Sources" / "Channels.swift"

HEADER = '''import Foundation

/// Static channel line-up.
///
/// Each channel lists its sources in preference order: the curated HLS link
/// first, the one harvested from the shared list as a fallback. The proxy walks
/// the list and sticks to the first source that answers.
///
/// DASH sources and HLS carrying HEVC-in-TS are repackaged by the ffmpeg
/// gateway before AVFoundation sees them; DASH also carries its CENC ClearKey.
struct Source {
    let url: String
    let referer: String?
    let userAgent: String?
    let clearKey: String?
}

struct CatalogEntry {
    let name: String
    let logo: String?
    let sources: [Source]
}

'''

def quote(value):
    if value is None:
        return "nil"
    escaped = value.replace("\\", "\\\\").replace('"', '\\"').replace("$", "\\$")
    return f'"{escaped}"'

def parse_txt(nome, categoria_padrao=None):
    channels, fonte = [], None
    for raw in (PUBLICADO / nome).read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or ":" not in line:
            continue
        campo, valor = (x.strip() for x in line.split(":", 1))
        campo = campo.lower()
        if not valor:
            continue
        if campo == "canal":
            channels.append({"name": valor, "logo": None, "sources": [],
                             "categoria": categoria_padrao})
        elif not channels:
            continue
        elif campo == "logo":
            channels[-1]["logo"] = valor
        elif campo == "categoria":
            channels[-1]["categoria"] = valor
        elif campo == "fonte":
            fonte = {"url": valor, "referer": None, "userAgent": None, "key": None}
            channels[-1]["sources"].append(fonte)
        elif fonte is not None and campo in ("referer", "agente", "chave", "qualidade"):
            fonte[{"agente": "userAgent", "chave": "key", "qualidade": "quality"}.get(campo, campo)] = valor
    return [c for c in channels if c["sources"]]

def emit_chunk(out, missing, channels, chunk_name):
    out.append(f"private let {chunk_name}: [CatalogEntry] = [")
    for channel in channels:
        out.append("    CatalogEntry(")
        out.append(f'        name: {quote(channel["name"])},')
        out.append(f'        logo: {quote(channel["logo"])},')
        out.append("        sources: [")
        for source in channel["sources"]:
            out.append("            Source(url: " + quote(source["url"]) + ",")
            out.append("                   referer: " + quote(source["referer"]) + ",")
            out.append("                   userAgent: " + quote(source["userAgent"]) + ",")
            out.append("                   clearKey: " + quote(source["key"]) + "),")
        out.append("        ]),")
    out.append("]")
    out.append("")

def emit_list(out, missing, channels, list_name):
    CHUNK_SIZE = 50
    chunks = []
    for i in range(0, len(channels), CHUNK_SIZE):
        chunk_name = f"{list_name}_part_{i//CHUNK_SIZE}"
        emit_chunk(out, missing, channels[i:i+CHUNK_SIZE], chunk_name)
        chunks.append(chunk_name)
    
    if chunks:
        out.append(f"private let {list_name}: [CatalogEntry] = " + " + ".join(chunks))
    else:
        out.append(f"private let {list_name}: [CatalogEntry] = []")
    out.append("")

def main():
    out, missing = [HEADER], []
    catalog = parse_txt("catalogo.txt")
    restricted = parse_txt("restritos.txt", categoria_padrao="Adulto")

    emit_list(out, missing, catalog, "catalog")
    emit_list(out, missing, restricted, "restrictedCatalog")

    FOOTER = '''
private func build(_ entries: [CatalogEntry]) -> [Channel] {
    entries.compactMap { entry in
        let variants = entry.sources.compactMap { s -> Variant? in
            guard let url = URL(string: s.url) else { return nil }
            // A chave é guardada como KID:CHAVE, porque o lado Android precisa
            // dos dois. O AVFoundation só usa a chave, que é a segunda metade.
            let key = s.clearKey.map { $0.split(separator: ":").map(String.init).last ?? $0 }
            return Variant(url: url, referer: s.referer,
                           userAgent: s.userAgent, clearKey: key)
        }
        guard !variants.isEmpty else { return nil }
        return Channel(name: entry.name,
                       variants: variants,
                       logo: entry.logo.flatMap(URL.init(string:)))
    }
}

let defaultChannels: [Channel] = build(catalog)
let restrictedChannels: [Channel] = build(restrictedCatalog)
'''
    out.append(FOOTER)
    SWIFT.write_text("\n".join(out) + "\n", encoding="utf-8")

if __name__ == "__main__":
    main()
