#!/usr/bin/env python3
"""Gera patch compatível com TV Box antigo; não grava nem publica arquivos."""
import json
import re
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

ROOT = Path(__file__).resolve().parents[1]

def corrigir_linha(line):
    fields = line.split('\t')
    out, metadata = [fields[0]], {}
    for field in fields[1:]:
        key, sep, value = field.partition('=')
        if sep and key in ('tmdb', 'imdb'):
            metadata[key] = value
            continue
        if sep and key in ('dub', 'leg'):
            urls = []
            for url in value.split(','):
                # A API Nexus também devolve caminhos relativos do proxy web.
                # Os apps recebem a URL interna, como no resolvedor da Nexus.
                if url.startswith('/api/proxy-video?'):
                    target = parse_qs(urlsplit(url).query).get('url', [''])[0]
                    if target.startswith(('https://', 'http://')):
                        url = target.replace(',', '%2C')
                urls.append(url)
            field = key + '=' + ','.join(urls)
        out.append(field)
    return '\t'.join(out), metadata

def main():
    meta_file = ROOT / 'vod/metadados-filmes.json'
    metadata = json.loads(meta_file.read_text()) if meta_file.exists() else {}
    patch = ['*** Begin Patch']
    for file in sorted((ROOT / 'vod').glob('filmes-*.txt')):
        edits = []
        for line in file.read_text().splitlines():
            fixed, info = corrigir_linha(line)
            if info:
                metadata.setdefault(file.name, {})[line.split('\t')[0]] = info
            if fixed != line:
                edits.extend(['@@', '-' + line, '+' + fixed])
        if edits:
            patch.extend(['*** Update File: ' + str(file), *edits])
    if metadata and not meta_file.exists():
        patch.extend(['*** Add File: ' + str(meta_file), *('+' + l for l in json.dumps(metadata, ensure_ascii=False, indent=2).splitlines())])
    patch.append('*** End Patch')
    print('\n'.join(patch))

if __name__ == '__main__':
    main()
