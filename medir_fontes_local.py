#!/usr/bin/env python3
"""Mede fontes locais com ffprobe. Uso: python3 -u medir_fontes_local.py

Salva progresso retomável e relatório em arquivos-gerados/resolucoes-local.
Atualiza qualidade no catálogo, sem mudar links nem ordem. Não faz push.
"""
import concurrent.futures
import datetime
import fcntl
import hashlib
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OUT = ROOT / 'arquivos-gerados/resolucoes-local'
FILES = [ROOT / 'catalogo.txt', ROOT / 'restritos.txt']
UA = 'Mozilla/5.0'
PROBE = '/Applications/Saimo TV.app/Contents/Resources/ffprobe'


def atomic(path, value):
    temp = path.with_suffix(path.suffix + '.tmp')
    temp.write_text(value, encoding='utf-8')
    temp.replace(path)


def sources(text):
    channel = ''
    current = None
    for line in text.splitlines():
        field, sep, value = line.partition(': ')
        if not sep:
            continue
        if field == 'canal':
            channel, current = value, None
        elif field == 'fonte':
            current = {'canal': channel, 'url': value}
            yield current
        elif current is not None and field in ('referer', 'agente', 'chave'):
            current[field] = value


def key(source):
    return hashlib.sha256(json.dumps({k: v for k, v in source.items() if k != 'canal'}, sort_keys=True).encode()).hexdigest()


def measure(source):
    command = [PROBE, '-v', 'error', '-rw_timeout', '10000000',
               '-analyzeduration', '7000000', '-probesize', '4000000',
               '-user_agent', source.get('agente', UA)]
    if source.get('referer'):
        command += ['-referer', source['referer']]
    command += ['-i', source['url'], '-select_streams', 'v',
                '-show_entries', 'stream=width,height,codec_name', '-of', 'json']
    result = {'motor': PROBE, 'id': key(source), 'canal': source['canal'], 'url': source['url'],
              'data': datetime.datetime.now().isoformat(timespec='seconds')}
    try:
        process = subprocess.run(command, capture_output=True, timeout=25)
        streams = json.loads(process.stdout or b'{}').get('streams', [])
        dimensions = sorted({(s.get('width', 0), s.get('height', 0)) for s in streams if s.get('width', 0) > 0 and s.get('height', 0) > 0}, key=lambda wh: wh[0]*wh[1])
        if dimensions:
            result['resolucoes'] = [f'{w}x{h}' for w, h in dimensions]
            w, h = dimensions[-1]
            result.update(largura=w, altura=h, qualidade='4K' if h >= 2000 else 'FHD' if h >= 1000 else 'HD' if h >= 700 else 'SD', estado='medida')
        else:
            result['estado'] = 'sem_medida'
    except subprocess.TimeoutExpired:
        result['estado'] = 'tempo_esgotado'
    except (OSError, ValueError):
        result['estado'] = 'erro_de_consulta'
    return result


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    lock = (OUT / 'execucao.lock').open('w')
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    subprocess.run([PROBE, '-version'], check=True, capture_output=True, timeout=10)
    requests = {}
    for path in FILES:
        for item in list(sources(path.read_text(encoding='utf-8'))):
            requests.setdefault(key(item), item)
    cached = {}
    progress = OUT / 'progresso.jsonl'
    if progress.exists():
        for line in progress.read_text().splitlines():
            try:
                item = json.loads(line)
                if item.get('motor') == PROBE and item['data'][:10] == datetime.date.today().isoformat():
                    cached[item['id']] = item
            except (ValueError, KeyError):
                pass
    pending = [s for k, s in requests.items() if k not in cached]
    print(f'{len(requests)} fontes; {len(pending)} pendentes. 16 consultas paralelas, limite de 25 segundos por fonte.', flush=True)
    with progress.open('a', encoding='utf-8') as log, concurrent.futures.ThreadPoolExecutor(max_workers=16) as pool:
        futures = [pool.submit(measure, s) for s in pending]
        for future in concurrent.futures.as_completed(futures):
            item = future.result()
            cached[item['id']] = item
            log.write(json.dumps(item, ensure_ascii=False) + '\n')
            log.flush()
            done = sum(k in cached for k in requests)
            if done % 10 == 0 or done == len(requests):
                measured = sum(cached[k]['estado'] == 'medida' for k in requests if k in cached)
                print(f'[{done}/{len(requests)}] {measured} fontes com resolução medida', flush=True)
    for path in FILES:
        # Relê para preservar alterações feitas durante a medição.
        original = path.read_text(encoding='utf-8')
        atomic(OUT / (path.name + '.backup'), original)
        items = iter(list(sources(original)))
        chunks = re.split(r'(?m)(?=^fonte: )', original)
        for i in range(1, len(chunks)):
            item = next(items)
            result = cached.get(key(item), {})
            if result.get('estado') != 'medida':
                continue
            label = f"{result['qualidade']} · {result['largura']}x{result['altura']}"
            # Só altera o bloco da fonte, nunca metadados do canal seguinte.
            chunk = chunks[i]
            if re.search(r'(?m)^qualidade: ', chunk):
                chunk = re.sub(r'(?m)^qualidade: .*$', 'qualidade: ' + label, chunk, count=1)
            else:
                first, sep, rest = chunk.partition('\n')
                chunk = first + '\nqualidade: ' + label + '\n' + rest
            chunks[i] = chunk
        atomic(path, ''.join(chunks))
    results = [cached[k] for k in requests]
    atomic(OUT / 'relatorio.json', json.dumps(results, ensure_ascii=False, indent=2) + '\n')
    measured = sum(r['estado'] == 'medida' for r in results)
    print(f'CONCLUÍDO: {measured}/{len(results)} fontes medidas. Catálogos atualizados; demais fontes preservadas. Relatório: {OUT / "relatorio.json"}', flush=True)


if __name__ == '__main__':
    main()
