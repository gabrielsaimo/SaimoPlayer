#!/usr/bin/env python3
"""Mede fontes locais com ffprobe.

    python3 -u medir_fontes_local.py                    todas as fontes
    python3 -u medir_fontes_local.py --sem-qualidade    só as sem qualidade
                                                        ("Qualidade não informada"
                                                        ou sem a linha)

Salva progresso retomável e relatório em arquivos-gerados/resolucoes-local.
Atualiza qualidade no catálogo, sem mudar links nem ordem. Não faz push.

Os servidores das listas são contas Xtream com limite de conexões: no máximo
duas consultas por servidor ao mesmo tempo, e a fonte que não deu medida é
tentada de novo no fim, uma por servidor, antes de ficar sem qualidade.
"""
import argparse
import collections
import concurrent.futures
import datetime
import fcntl
import hashlib
import json
import re
import subprocess
import threading
import time
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parent
OUT = ROOT / 'arquivos-gerados/resolucoes-local'
FILES = [ROOT / 'catalogo.txt', ROOT / 'restritos.txt']
UA = 'Mozilla/5.0'
PROBE = '/Applications/Saimo TV.app/Contents/Resources/ffprobe'
SEM_QUALIDADE = ('', 'Qualidade não informada')

_travas = collections.defaultdict(lambda: threading.Semaphore(2))
_travas_lock = threading.Lock()


def trava(url):
    with _travas_lock:
        return _travas[urlsplit(url).netloc.lower()]


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
        elif current is not None and field == 'qualidade':
            # Fora da chave do cache: medir não depende do rótulo de antes.
            current['_qualidade'] = value


def sem_qualidade(source):
    return source.get('_qualidade', '').strip() in SEM_QUALIDADE


def key(source):
    return hashlib.sha256(json.dumps({k: v for k, v in source.items() if k != 'canal' and not k.startswith('_')}, sort_keys=True).encode()).hexdigest()


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
        with trava(source['url']):
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
    parser = argparse.ArgumentParser()
    parser.add_argument('--sem-qualidade', action='store_true', help='só as fontes sem qualidade')
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    lock = (OUT / 'execucao.lock').open('w')
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    subprocess.run([PROBE, '-version'], check=True, capture_output=True, timeout=10)
    requests = {}
    for path in FILES:
        for item in list(sources(path.read_text(encoding='utf-8'))):
            if args.sem_qualidade and not sem_qualidade(item):
                continue
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
        # Segunda chance: falha por limite de conexões some com calma.
        falhas = [requests[k] for k in requests if cached.get(k, {}).get('estado') != 'medida']
        if falhas:
            print(f'{len(falhas)} sem medida; tentando de novo, uma por servidor', flush=True)
            time.sleep(30)
            _travas.clear()
            _travas.default_factory = lambda: threading.Semaphore(1)
            for item in pool.map(measure, falhas):
                if item.get('estado') == 'medida' or cached.get(item['id'], {}).get('estado') != 'medida':
                    cached[item['id']] = item
                    log.write(json.dumps(item, ensure_ascii=False) + '\n')
            log.flush()
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
