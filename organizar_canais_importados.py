#!/usr/bin/env python3
"""Consolida aliases novos sem apagar canais anteriores à importação.

Sem --aplicar, apenas apresenta a revisão. Faz backup antes de escrever.
Não usa similaridade aproximada: canais regionais e eventos distintos
não devem ser unidos apenas porque seus nomes são parecidos.
"""
import argparse
import datetime
import json
from pathlib import Path
import re
import subprocess
import unicodedata

ROOT = Path(__file__).resolve().parent
BASELINE = '81f7108'
ALIASES = {
    'Warner Channel': 'Warner',
    'Canal Sony': 'Sony Channel',
    'Discovery H&H': 'Discovery Home & Health',
    'H2': 'History 2',
    'ID': 'Discovery ID',
    'OFF': 'Canal OFF',
    'Cultura': 'TV Cultura',
    'Pai Eterno': 'TV Pai Eterno',
    'TV Cancao Nova': 'Canção Nova',
    'RecordTV RJ': 'Record RJ',
    'RecordTV SP': 'Record SP',
    'RecordTV Goias': 'Record GO',
    'SBT TV Alterosa': 'SBT Alterosa',
    'Globo Brasilia': 'Globo DF',
    'Globo Minas': 'Globo MG',
    'Caze TV': 'CazeTV 1',
    'DAZN 1': 'DAZN (Jogo 1)',
    'DAZN 2': 'DAZN (Jogo 2)',
    'Paramount + 1': 'Paramount+ (Jogo 1)',
    'Paramount + 2': 'Paramount+ (Jogo 2)',
    'Paramount + 3': 'Paramount+ (Jogo 3)',
    'Canal Goat 2': 'Canal GOAT (Jogo 2)',
    'Todo Mundo Odeia o Chris': '24H Todo Mundo Odeia o Cris',
}


def normalized(name):
    text = unicodedata.normalize('NFKD', name).encode('ascii', 'ignore').decode().lower()
    text = re.sub(r'^24\s*h\s*', '', text)
    text = re.sub(r'\b0+(\d+)\b', r'\1', text)
    # Preserve +: SportyNet e SportyNet+ são canais diferentes.
    return re.sub(r'[^a-z0-9+]', '', text)


def canonical_name(name):
    aliases = {normalized(k):v for k,v in ALIASES.items()}
    return aliases.get(normalized(name), name)


def is_open_channel(name, category):
    cat = normalized(category)
    n = normalized(name)
    return (cat == 'tvaberta' or any(w in cat for w in ('abertos', 'globos', 'recordtv', 'religiosos'))
            or (n.startswith('globo') and n != 'globonews' and not n.startswith('globoplay'))
            or n.startswith(('recordtv', 'sbtvtv', 'sbtthathi'))
            or n in {'megatv', 'idealtv', 'tvuniao', 'tvuniaofortaleza'})


def blocks(text):
    parts = re.split(r'(?m)(?=^canal: )', text)
    return parts[0] if not parts[0].startswith('canal: ') else '', [b for b in parts if b.startswith('canal: ')]


def name(block):
    return block.splitlines()[0][7:].strip()


def sources(block):
    return re.findall(r'(?ms)^fonte: .*?(?=^fonte: |\Z)', block)


def consolidate(current, baseline):
    header, current_blocks = blocks(current)
    old_blocks = blocks(baseline)[1]
    old_names = {name(b) for b in old_blocks}
    by_name = {name(b):i for i,b in enumerate(current_blocks)}
    assert old_names <= set(by_name), 'Há canais antigos ausentes antes da revisão.'
    canonical = {}
    for n in old_names:
        canonical.setdefault(normalized(n), []).append(n)
    merged, removed, dropped = [], [], set()
    for i,b in enumerate(current_blocks):
        n = name(b)
        if n in old_names:
            continue
        candidates = canonical.get(normalized(canonical_name(n)), [])
        if len(candidates) == 1:
            target = candidates[0]
            j = by_name[target]
            existing = {s.splitlines()[0] for s in sources(current_blocks[j])}
            additions = []
            for s in sources(b):
                key = s.splitlines()[0]
                if key not in existing:
                    additions.append(s.rstrip()); existing.add(key)
            if additions:
                current_blocks[j] = current_blocks[j].rstrip()+'\n'+'\n'.join(additions)+'\n\n'
            merged.append({'de':n, 'para':target, 'fontes_transferidas':len(additions)})
            dropped.add(i)
        else:
            category = re.search(r'^categoria: (.*)$', b, re.M)
            if is_open_channel(n, category[1] if category else ''):
                removed.append(n); dropped.add(i)
    result = header + ''.join(b for i,b in enumerate(current_blocks) if i not in dropped)
    result = result.rstrip()+'\n'
    final = {name(b):b for b in blocks(result)[1]}
    assert old_names <= set(final)
    old_open = {name(b) for b in old_blocks if 'categoria: TV Aberta' in b}
    final_open = {name(b) for b in final.values() if 'categoria: TV Aberta' in b}
    assert old_open == final_open, 'A lista de abertos não corresponde à anterior.'
    for b in blocks(current)[1]:
        n = name(b)
        if n in old_names:
            assert {s.splitlines()[0] for s in sources(b)} <= {s.splitlines()[0] for s in sources(final[n])}
    assert all(sources(b) for b in final.values())
    return result, {'canais_antes':len(current_blocks), 'canais_depois':len(final),
                    'abertos_anteriores_preservados':len(old_open), 'duplicados_unificados':merged,
                    'abertos_novos_removidos':removed}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--aplicar', action='store_true')
    args = parser.parse_args()
    path = ROOT/'catalogo.txt'
    current = path.read_text()
    baseline = subprocess.check_output(['git','show',BASELINE+':catalogo.txt'],cwd=ROOT,text=True)
    result,report = consolidate(current,baseline)
    print(json.dumps(report,ensure_ascii=False,indent=2))
    if args.aplicar:
        out = ROOT/'arquivos-gerados'/('organizacao-canais-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S'))
        out.mkdir(parents=True)
        (out/'catalogo-antes.txt').write_text(current)
        (out/'relatorio.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
        path.write_text(result)
        print('Backup e relatório:',out)


if __name__ == '__main__':
    main()
