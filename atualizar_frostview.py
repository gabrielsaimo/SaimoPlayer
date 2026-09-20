#!/usr/bin/env python3
"""Descobre canais FrostView, informa qualidade e prioriza suas fontes FHD.

Uso: python3 atualizar_frostview.py --aplicar
Sem --aplicar, somente gera o inventário e o relatório em arquivos-gerados/frostview.
Os URLs são mantidos como retornados pela API, sem decodificar o relay.
As demais fontes são preservadas; resolução não anunciada fica como desconhecida.
"""
import argparse
import concurrent.futures
import json
import re
import time
import unicodedata
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent
BASE = 'https://frostview.cloutteam.com'


def fetch(path):
    for attempt in range(3):
        try:
            request = urllib.request.Request(BASE + path, headers={'User-Agent': 'SaimoTV-Catalog/1.0'})
            with urllib.request.urlopen(request, timeout=30) as response:
                return json.load(response)
        except Exception:
            if attempt == 2:
                raise
            time.sleep(attempt + 1)


def normalized(name):
    return re.sub(r'[^a-z0-9]', '', unicodedata.normalize('NFKD', name).encode('ascii', 'ignore').decode().lower())


def atomic(path, content):
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(content, encoding='utf-8')
    temporary.replace(path)


def quality(text):
    match = re.search(r'(?i)(?<![a-z0-9])(4K|UHD|FHD|1080[pi]?|HD|720p?|SD|480p?)(?![a-z0-9])', text)
    if not match:
        return 'Qualidade não informada'
    value = match.group(1).upper()
    if value in ('4K', 'UHD'):
        return '4K'
    if value.startswith('1080') or value == 'FHD':
        return 'FHD'
    if value.startswith('720') or value == 'HD':
        return 'HD'
    return 'SD'


def label_and_prioritize(block, streams):
    """Move blocos completos, mantendo cabeçalhos/DRM junto à respectiva fonte."""
    qualities = {s['url']: quality(s.get('name', '')) for s in streams}
    pieces = re.split(r'(?m)(?=^fonte: )', block)
    sources = []
    for piece in pieces[1:]:
        url = piece.splitlines()[0][7:].strip()
        previous = re.search(r'^qualidade: (.+)$', piece, re.M)
        label = qualities.get(url) or (previous.group(1) if previous else quality(urllib.parse.urlsplit(url).path))
        if previous and re.search(r'\d+x\d+', previous.group(1)):
            label = previous.group(1)
        piece = re.sub(r'(?m)^qualidade: .*\n?', '', piece).rstrip()
        first, _, rest = piece.partition('\n')
        piece = first + '\nqualidade: ' + label + '\n' + (rest + '\n' if rest else '')
        sources.append((url in qualities and label.split(' · ')[0] == 'FHD', piece))
    sources.sort(key=lambda item: not item[0])
    return pieces[0] + ''.join(piece for _, piece in sources) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--aplicar', action='store_true')
    parser.add_argument('--usar-cache', action='store_true', help='usa o inventário já coletado para reordenar e rotular')
    parser.add_argument('--workers', type=int, choices=range(1, 17), default=8, metavar='1..16')
    args = parser.parse_args()
    output = ROOT / 'arquivos-gerados/frostview'
    output.mkdir(parents=True, exist_ok=True)
    manifest = {'catalogs': []} if args.usar_cache else fetch('/manifest.json')
    channels = {}
    for catalog in manifest.get('catalogs', []):
        if catalog.get('type') != 'channel':
            continue
        offset = 0
        for _ in range(1000):
            path = '/catalog/channel/' + urllib.parse.quote(catalog['id'], safe='')
            path += (f'/skip={offset}' if offset else '') + '.json'
            page = fetch(path).get('metas', [])
            if not page:
                break
            new = [item for item in page if item['id'] not in channels]
            if not new:
                raise RuntimeError('Paginação repetida: inventário incompleto; catálogo não alterado.')
            channels.update((item['id'], item) for item in page)
            offset += len(page)
            print(f'Catálogo: {len(channels)} canais', flush=True)
        else:
            raise RuntimeError('Limite de paginação atingido; catálogo não alterado.')

    def resolve(item):
        item = dict(item)
        try:
            data = fetch('/stream/channel/' + urllib.parse.quote(item['id'], safe='') + '.json')
            item['streams'] = [s for s in data.get('streams', []) if str(s.get('url', '')).startswith(('https://', 'http://'))]
        except Exception as exc:
            item['streams'] = []
            item['error'] = type(exc).__name__
        return item

    results = json.loads((output / 'canais.json').read_text(encoding='utf-8')) if args.usar_cache else []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        for item in pool.map(resolve, channels.values()):
            results.append(item)
            if len(results) % 50 == 0:
                print(f'Fontes: {len(results)}/{len(channels)} canais consultados', flush=True)
    atomic(output / 'canais.json', json.dumps(results, ensure_ascii=False, indent=2) + '\n')
    by_name = {}
    for item in results:
        by_name.setdefault(normalized(item['name']), []).append(item)
    catalog_path = ROOT / 'catalogo.txt'
    original = catalog_path.read_text(encoding='utf-8')
    blocks = re.split(r'(?m)(?=^canal: )', original)
    matched, updated, added = set(), [], 0
    for index, block in enumerate(blocks):
        if not block.startswith('canal: '):
            continue
        name = block.splitlines()[0][7:].strip()
        candidates = by_name.get(normalized(name), [])
        if len(candidates) != 1:
            continue
        item = candidates[0]
        matched.add(item['id'])
        existing = set(re.findall(r'^fonte: (.+)$', block, re.M))
        urls = list(dict.fromkeys(s['url'] for s in item['streams']))
        fresh = [url for url in urls if url not in existing and '\n' not in url and '\r' not in url]
        if fresh:
            blocks[index] = block.rstrip() + '\n' + ''.join('fonte: ' + url + '\n' for url in fresh) + '\n'
            updated.append({'canal': name, 'reservas_adicionadas': len(fresh)})
            added += len(fresh)
    all_streams = [stream for item in results for stream in item['streams']]
    blocks = [label_and_prioritize(block, all_streams) if block.startswith('canal: ') else block for block in blocks]
    report = {
        'canais_descobertos': len(results),
        'fontes_retornadas': sum(len(item['streams']) for item in results),
        'canais_atualizados': updated,
        'reservas_adicionadas': added,
        'sem_correspondencia': [{'id': i['id'], 'nome': i['name']} for i in results if i['id'] not in matched],
        'sem_fontes': [i['name'] for i in results if not i['streams']],
        'erros': [i['name'] for i in results if i.get('error')],
        'aplicado': args.aplicar,
        'observacao': 'Fontes retornadas pela API; reprodução não validada. Associação somente por nome exato normalizado.',
    }
    if args.aplicar:
        atomic(output / 'catalogo-antes.txt', original)
        atomic(catalog_path, ''.join(blocks).rstrip() + '\n')
    atomic(output / 'relatorio.json', json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(f'Concluído: {len(results)} canais, {len(updated)} correspondências com novas reservas, {added} reservas. Aplicado: {args.aplicar}', flush=True)
    print(f'Relatório: {output / "relatorio.json"}', flush=True)


if __name__ == '__main__':
    main()
