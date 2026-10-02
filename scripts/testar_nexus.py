#!/usr/bin/env python3
"""Testa slugs do catálogo; gera relatório e patch, sem editar o catálogo."""
import concurrent.futures as cf
import json
import re
import subprocess
import unicodedata
from pathlib import Path
from urllib.parse import urljoin, urlparse
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'arquivos-gerados/nexus'
BASE = 'https://nexustvplay.bbroot.com/api/stream/'
PROBE = '/Applications/Saimo TV.app/Contents/Resources/ffprobe'

def get(url, limit=262144):
    with urlopen(Request(url, headers={'User-Agent': 'Mozilla/5.0'}), timeout=12) as r:
        return r.read(limit), r.geturl()

def test(slug):
    url = BASE + slug + '/index.m3u8'
    result = {'slug': slug, 'url': url, 'ok': False}
    try:
        body, current = get(url)
        for _ in range(3):
            text = body.decode('utf-8-sig')
            if not text.lstrip().startswith('#EXTM3U'):
                raise ValueError('Resposta não é HLS')
            links = [s.strip() for s in text.splitlines() if s.strip() and not s.startswith('#')]
            if not links:
                raise ValueError('Playlist vazia')
            if '#EXT-X-STREAM-INF:' in text:
                body, current = get(urljoin(current, links[0]))
                continue
            segment, _ = get(urljoin(current, links[-2] if len(links) > 1 else links[0]), 4096)
            ts = len(segment) >= 377 and segment[0] == segment[188] == segment[376] == 0x47
            mp4 = any(x in segment[:64] for x in (b'ftyp', b'styp', b'moof'))
            if not (ts or mp4):
                raise ValueError('Segmento não reconhecido como vídeo TS/fMP4')
            result.update(ok=True, qualidade='Qualidade não informada')
            try:
                p = subprocess.run([PROBE, '-v', 'error', '-rw_timeout', '7000000', '-analyzeduration', '2000000', '-probesize', '1500000', '-i', url, '-select_streams', 'v', '-show_entries', 'stream=width,height', '-of', 'json'], capture_output=True, timeout=15)
                dims = [(s.get('width', 0), s.get('height', 0)) for s in json.loads(p.stdout or '{}').get('streams', [])]
                dims = [(w, h) for w, h in dims if w and h]
                if dims:
                    w, h = max(dims, key=lambda d:d[0]*d[1])
                    label = '4K' if h >= 2000 else 'FHD' if h >= 1000 else 'HD' if h >= 700 else 'SD'
                    result['qualidade'] = f'{label} · {w}x{h}'
            except (subprocess.TimeoutExpired, OSError, ValueError):
                pass
            return result
        raise ValueError('Playlist aninhada além do limite')
    except Exception as e:
        result['erro'] = str(e)
        return result

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    path = ROOT / 'catalogo.txt'
    original = path.read_text()
    blocks = re.split(r'(?=^canal: )', original, flags=re.M)
    candidates = {}
    for block in blocks[1:]:
        name = block.splitlines()[0][7:]
        slugs = re.findall(r'https://[^\s/]*s23-cloudfront-net\.lat/[^/\s]+/([\w-]+)\.txt', block)
        if not slugs:
            normalized = unicodedata.normalize('NFKD', name).encode('ascii', 'ignore').decode().lower()
            slugs = [re.sub(r'[^a-z0-9]', '', normalized)]
        candidates[name] = list(dict.fromkeys(slugs))
    slugs = sorted({s for values in candidates.values() for s in values})
    results = {}
    print(f'Testando {len(slugs)} nomes, com 6 consultas paralelas', flush=True)
    with (OUT / 'testes.jsonl').open('w') as log, cf.ThreadPoolExecutor(max_workers=6) as pool:
        for i, r in enumerate(pool.map(test, slugs), 1):
            results[r['slug']] = r
            log.write(json.dumps(r, ensure_ascii=False) + '\n'); log.flush()
            print(f"{i}/{len(slugs)} {r['slug']}: {r.get('qualidade') if r['ok'] else r.get('erro')}", flush=True)
    patch = ['*** Begin Patch', '*** Update File: ' + str(path)]
    added, failed = [], []
    for block in blocks[1:]:
        name = block.splitlines()[0][7:]
        valid = next((results[s] for s in candidates[name] if results[s]['ok']), None)
        if not valid:
            failed.append(name); continue
        if valid['url'] in block:
            continue
        lines = block.splitlines()
        idx = next((i for i, line in enumerate(lines) if line.startswith('fonte: ')), None)
        if idx is None:
            continue
        patch.append('@@')
        patch.extend(' ' + line for line in lines[:idx])
        patch.extend(['+fonte: ' + valid['url'], '+qualidade: ' + valid['qualidade'], ' ' + lines[idx]])
        added.append({'canal': name, **valid})
    patch.append('*** End Patch')
    (OUT / 'catalogo.patch').write_text('\n'.join(patch) + '\n')
    (OUT / 'relatorio.json').write_text(json.dumps({'adicionar': added, 'nao_validados': failed}, ensure_ascii=False, indent=2))
    print(f'RESULTADO: {len(added)} principais validadas; {len(failed)} canais sem fonte validada. Patch não aplicado.', flush=True)

if __name__ == '__main__':
    main()
