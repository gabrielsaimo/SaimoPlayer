#!/usr/bin/env python3
"""Substitui somente reservas premiumsh.pro pela lista M3U informada.
Uso: python3 substituir_reservas_m3u.py /caminho/lista.m3u [--aplicar]
Associa por tipo, ID e nome; usa nome exato normalizado quando é único.
"""
import argparse
import collections
import datetime
import json
import re
import shutil
import unicodedata
from pathlib import Path
from urllib.parse import urlsplit
from gerar_vod import nome_do_extinf, limpar, separar_ano, chave, letra, EPISODIO

ROOT = Path(__file__).resolve().parent
EPISODIO = re.compile(r'^(.*?)\s*S(\d{1,3})\s*E(\d{1,5})\s*$', re.I)


def norm(name):
    return re.sub(r'\s+', ' ', unicodedata.normalize('NFKD', name).encode('ascii', 'ignore').decode().casefold()).strip()


def parse(path):
    entries = []
    name = ''
    group = logo = ''
    for raw in path.open(encoding='utf-8-sig'):
        line = raw.strip()
        if line.startswith('#EXTINF:'):
            name = nome_do_extinf(line)
            attrs = dict(re.findall(r'([\w-]+)="([^"]*)"',line))
            group,logo=attrs.get('group-title',''),attrs.get('tvg-logo','')
        elif line.startswith(('http://', 'https://')):
            u = urlsplit(line)
            kind = 'movie' if u.path.startswith('/movie/') else 'series' if u.path.startswith('/series/') else 'channel'
            entries.append({'name': name, 'group':group,'logo':logo, 'url': line, 'kind': kind,
                            'id': u.path.rsplit('/', 1)[-1].split('.')[0], 'host': u.hostname})
            name = ''
    return entries


def incorporar_novos(new, updates, bases, counts):
    def read(p):
        return updates.get(p,p.read_text() if p.exists() else '')
    def compact(url):
        for n,b in bases.items():
            if url.startswith(b):
                rest=url[len(b):]
                return n+':'+(rest[:-4] if rest.endswith('.mp4') else rest)
        return url
    movies={}; movie_files={}; series={}; series_files={}
    for p in (ROOT/'vod').glob('*.txt'):
        if re.fullmatch(r'(filmes|reservado)-[#A-Z]\.txt',p.name):
            rows=[]
            for line in read(p).splitlines():
                if not line: continue
                f=line.split('\t'); title,year=separar_ano(f[0]); k=(p.name.startswith('reservado'),chave(title,year))
                rows.append(f); movies.setdefault(k,[]).append(f)
            movie_files[p]=rows
        elif re.fullmatch(r'series-[#A-Z]-\d+\.txt',p.name):
            records=[]; r=None
            for line in read(p).splitlines():
                if line.startswith('@'):
                    f=line[1:].split('\t'); r={'header':line,'title':f[0],'year':f[1] if len(f)>1 else '', 'eps':{}, 'path':p}
                    records.append(r); series.setdefault(chave(r['title'],r['year']),[]).append(r)
                elif r and line:
                    f=line.split('\t')
                    if len(f)>=4: r['eps'][int(f[0]),int(f[1]),f[2]]=f
            series_files[p]=records
    # Fontes já associadas identificam os títulos mesmo quando há aliases
    # ou metadados enriquecidos no catálogo (ano/TMDB).
    owners = {}
    for records in series_files.values():
        for r in records:
            for f in r['eps'].values():
                for u in f[3].split(','): owners.setdefault(u, {})[id(r)] = r
    aliases = {}
    for e in new:
        if e['kind'] != 'series': continue
        match = EPISODIO.match(limpar(e['name'])[0])
        if match:
            k = chave(*separar_ano(match[1]))
            for ident, r in owners.get(compact(e['url']), {}).items():
                aliases.setdefault(k, {})[ident] = r
    movie_owners = {}
    for rows in movie_files.values():
        for f in rows:
            for field in f[1:]:
                for u in field[4:].split(','): movie_owners.setdefault(u, {})[id(f)] = f
    marks_path=ROOT/'vod/marcas.txt'
    marks=dict(line.split('\t',1) for line in read(marks_path).splitlines() if '\t' in line and not line.startswith('\t'))
    for e in new:
        if e['kind']=='channel': continue
        title,leg,adult,quality=limpar(e['name']); language='leg' if leg else 'dub'; url=compact(e['url'])
        if quality: marks[url]=quality
        if e['kind']=='movie':
            title,year=separar_ano(title); k=(adult,chave(title,year)); candidates=list(movie_owners.get(url,{}).values()) or movies.get(k,[])
            if len(candidates)>1:
                counts['filmes_ambiguos_ignorados']+=1; continue
            if not candidates:
                f=[f'{title} ({year})' if year else title]
                p=ROOT/'vod'/f'{"reservado" if adult else "filmes"}-{letra(title)}.txt'
                movie_files.setdefault(p,[]).append(f); movies[k]=[f]; counts['novos_filmes']+=1
            else: f=candidates[0]
            i=next((i for i,v in enumerate(f) if v.startswith(language+'=')),None)
            if i is None: f.append(language+'='+url); counts['novas_fontes_filmes']+=1
            elif url not in f[i][4:].split(','): f[i]+=','+url; counts['novas_fontes_filmes']+=1
        else:
            match=EPISODIO.match(title)
            if not match or adult:
                counts['series_sem_identidade_ignoradas']+=1; continue
            title,year=separar_ano(match[1]); k=chave(title,year); candidates=list(owners.get(url,{}).values()) or list(aliases.get(k,{}).values()) or series.get(k,[])
            if len(candidates)>1:
                counts['series_ambiguas_ignoradas']+=1; continue
            if not candidates:
                bucket=letra(title)
                existing=[p for p in series_files if p.name.startswith(f'series-{bucket}-')]
                p=max(existing,key=lambda p:int(p.stem.rsplit('-',1)[1])) if existing else ROOT/'vod'/f'series-{bucket}-0.txt'
                if len(series_files.get(p,[]))>=120: p=p.with_name(f'series-{bucket}-{int(p.stem.rsplit("-",1)[1])+1}.txt')
                r={'title':title,'year':year,'header':'@'+title+('\t'+year if year else ''),'eps':{},'path':p}
                series[k]=[r]; series_files.setdefault(p,[]).append(r); counts['novas_series']+=1
            else: r=candidates[0]
            ep=(int(match[2]),int(match[3]),language)
            if ep not in r['eps']:
                r['eps'][ep]=[str(ep[0]),str(ep[1]),language,url]; counts['novos_episodios']+=1
            elif url not in r['eps'][ep][3].split(','):
                r['eps'][ep][3]+=','+url; counts['novas_fontes_episodios']+=1
    totals=collections.defaultdict(lambda:[0,0,0]); search=[]; indexes=collections.defaultdict(list)
    for p,rows in movie_files.items():
        rows.sort(key=lambda f:f[0]); updates[p]='\n'.join('\t'.join(f) for f in rows)+ ('\n' if rows else '')
        bucket=p.stem.rsplit('-',1)[1]; adult=p.name.startswith('reservado'); totals[bucket][2 if adult else 0]+=len(rows)
        if not adult: search.extend(f'{f[0]}\tf\t{bucket}' for f in rows)
    for p,records in series_files.items():
        lines=[]; bucket=p.name.split('-')[1]; part=p.stem.rsplit('-',1)[1]
        for r in records:
            if not r['eps']: continue
            lines.append(r['header']); lines.extend('\t'.join(r['eps'][ep]) for ep in sorted(r['eps']))
            indexes[bucket].append([r['title'],r['year'],part,str(len(r['eps']))]); totals[bucket][1]+=1
            search.append(f'{r["title"]}\ts\t{bucket}'+('\t'+r['year'] if r['year'] else ''))
        updates[p]='\n'.join(lines)+ ('\n' if lines else '')
    for b,rows in indexes.items(): updates[ROOT/'vod'/f'series-{b}.txt']='\n'.join('\t'.join(r) for r in sorted(rows))+'\n'
    updates[ROOT/'vod/busca.txt']='\n'.join(search)+'\n'
    updates[marks_path]='\n'.join(k+'\t'+v for k,v in sorted(marks.items()))+'\n'
    index=ROOT/'vod/indice.txt'
    updates[index]='\n'.join([l for l in read(index).splitlines() if l.startswith('base: ')]+[b+'\t'+'\t'.join(map(str,t)) for b,t in sorted(totals.items())])+'\n'
    # Os novos canais entram no fim; os existentes recebem novas reservas.
    channel_files={p:re.split(r'(?m)(?=^canal: )',read(p)) for p in [ROOT/'catalogo.txt',ROOT/'restritos.txt']}; names={}
    def channel_key(name): return chave(limpar(name)[0])
    for p,blocks in channel_files.items():
        for i,b in enumerate(blocks):
            if b.startswith('canal: '): names.setdefault(channel_key(b.splitlines()[0][7:]),[]).append((p,i))
    for e in new:
        if e['kind']!='channel': continue
        k=channel_key(e['name']); positions=names.get(k,[])
        if len(positions)>1: counts['canais_ambiguos_ignorados']+=1; continue
        if not positions:
            group=norm(e['group']); name=limpar(e['name'])[0]
            cat=next((cat for words,cat in [(['adult','xxx','+18'],'Adulto'),(['24'],'24 Horas'),(['ppv'],'PPV'),(['esport','sport','premiere','espn','dazn','campeonato','futsal','nba','jogos'],'Esportes'),(['infanti','desenho','kids'],'Infantil'),(['noticia','news'],'Notícias'),(['document'],'Documentários'),(['filme','serie','hbo','telecine','max','legendado'],'Filmes e Séries'),(['abert','globo','record','sbt'],'TV Aberta'),(['relig'],'Religiosos')] if any(w in group for w in words)),'Variedades')
            p=ROOT/('restritos.txt' if cat=='Adulto' else 'catalogo.txt'); blocks=channel_files[p]
            if blocks: blocks[-1]=blocks[-1].rstrip()+'\n\n'
            blocks.append('canal: '+name+'\ncategoria: '+cat+'\n'+('logo: '+e['logo']+'\n' if e['logo'] else ''))
            positions=[(p,len(blocks)-1)]; names[k]=positions; counts['novos_canais']+=1
        p,i=positions[0]; blocks=channel_files[p]
        if e['url'] not in re.findall(r'^fonte: (.+)$',blocks[i],re.M):
            q=re.search(r'(?i)\b(4K|UHD|FHD|HD|SD)\b',e['name'])
            blocks[i]=blocks[i].rstrip()+'\nfonte: '+e['url']+'\nqualidade: '+(q[1].upper() if q else 'Qualidade não informada')+'\n\n'
            counts['novas_fontes_canais']+=1
    for p,blocks in channel_files.items(): updates[p]=''.join(blocks).rstrip()+'\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('lista', type=Path)
    parser.add_argument('--aplicar', action='store_true')
    args = parser.parse_args()
    old = [e for e in parse(ROOT/'1.m3u') if e['host'] == 'premiumsh.pro']
    new = parse(args.lista)
    if not old or not new:
        raise SystemExit('Lista antiga ou nova sem entradas; nenhuma alteração.')
    by_id = collections.defaultdict(list)
    by_name = collections.defaultdict(list)
    for e in new:
        by_id[e['kind'], e['id']].append(e)
        by_name[e['kind'], norm(e['name'])].append(e)
    mapping = {}
    unmatched = []
    for e in old:
        candidates = [n for n in by_id[e['kind'], e['id']] if norm(n['name']) == norm(e['name'])]
        if not candidates:
            candidates = by_name[e['kind'], norm(e['name'])]
        unique = {n['url']: n for n in candidates}
        if len(unique) == 1:
            mapping[e['url']] = next(iter(unique.values()))
        else:
            unmatched.append({'tipo': e['kind'], 'nome': e['name'], 'id': e['id'], 'motivo': 'ausente' if not unique else 'ambiguo'})
    stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
    out = ROOT/'arquivos-gerados'/f'substituicao-reservas-{stamp}'
    out.mkdir(parents=True)
    index = ROOT/'vod/indice.txt'
    index_text = index.read_text()
    bases = {m[0]:m[1] for m in re.findall(r'^base: (\d+) (.+)$', index_text, re.M) if urlsplit(m[1]).hostname == 'premiumsh.pro'}
    new_bases = {}
    for number, base in bases.items():
        kind = 'movie' if '/movie/' in base else 'series'
        available = {e['url'].rsplit('/',1)[0]+'/' for e in new if e['kind']==kind}
        if len(available) != 1:
            raise SystemExit('A nova lista contém múltiplas bases por tipo; revisão necessária.')
        new_bases[number] = available.pop()
    counts = collections.Counter()
    updates = {}
    for number, base in bases.items():
        index_text = index_text.replace(f'base: {number} {base}', f'base: {number} {new_bases[number]}')
    updates[index] = index_text
    missing_used = collections.Counter()
    removed_titles = []

    def replace_token(token):
        match = re.fullmatch(r'(\d+):(\d+(?:\.[A-Za-z0-9]+)?)', token)
        if match and match[1] in bases:
            suffix = match[2] if '.' in match[2] else match[2]+'.mp4'
            old_url = bases[match[1]] + suffix
            number = match[1]
        elif token.startswith(('http://','https://')) and urlsplit(token).hostname == 'premiumsh.pro':
            old_url, number = token, None
        else:
            return token
        entry = mapping.get(old_url)
        if not entry:
            counts['reservas_sem_correspondencia_removidas'] += 1
            missing_used[old_url.rsplit('/',1)[-1]] += 1
            return ''
        counts[entry['kind']+'_referencias_trocadas'] += 1
        if number:
            suffix = entry['url'][len(new_bases[number]):]
            if suffix.endswith('.mp4'):
                suffix = suffix[:-4]
            return number+':'+suffix
        return entry['url']

    for path in (ROOT/'vod').rglob('*.txt'):
        if path == index:
            continue
        text = path.read_text()
        if not any(re.search(r'(?<![\w:])'+n+r':',text) for n in bases) and 'premiumsh.pro' not in text:
            continue
        lines = []
        for line in text.splitlines():
            fields = line.split('\t')
            for i, field in enumerate(fields):
                if not any(re.search(r'(?<![\w:])'+n+r':',field) for n in bases) and 'premiumsh.pro' not in field:
                    continue
                prefix = ''
                if field.startswith(('dub=', 'leg=')):
                    prefix, field = field[:4], field[4:]
                parts = [replace_token(t) for t in field.split(',')]
                fields[i] = prefix + ','.join(dict.fromkeys(p for p in parts if p))
            fields = [f for f in fields if f not in ('dub=', 'leg=')]
            if len(fields) >= 4 and fields[0].isdigit() and not fields[3]:
                counts['episodios_sem_fonte_removidos'] += 1
                continue
            if len(fields)==1 and len(line.split('\t'))>1:
                counts['titulos_sem_fonte_removidos'] += 1
                removed_titles.append({'arquivo':str(path.relative_to(ROOT)), 'titulo':fields[0]})
                continue
            lines.append('\t'.join(fields))
        updated = '\n'.join(lines)+'\n'
        if updated != text:
            updates[path] = updated
    for path in [ROOT/'catalogo.txt',ROOT/'restritos.txt']:
        text = path.read_text()
        chunks = re.split(r'(?m)(?=^fonte: |^canal: )',text)
        for i, chunk in enumerate(chunks):
            if not chunk.startswith('fonte: '):
                continue
            url = chunk.splitlines()[0][7:].strip()
            if urlsplit(url).hostname != 'premiumsh.pro':
                continue
            entry = mapping.get(url)
            if entry:
                quality = re.search(r'(?i)\b(4K|UHD|FHD|HD|SD)\b',entry['name'])
                chunks[i] = 'fonte: '+entry['url']+'\nqualidade: '+(quality[1].upper() if quality else 'Qualidade não informada')+'\n'
                counts['channel_referencias_trocadas'] += 1
            else:
                chunks[i] = ''
                counts['canais_reservas_sem_correspondencia_removidas'] += 1
        updated = ''.join(chunks)
        for block in re.split(r'(?m)(?=^canal: )',updated):
            if block.startswith('canal: ') and 'fonte: ' not in block:
                raise RuntimeError('Canal perderia todas as fontes; revisão necessária.')
        if updated != text:
            updates[path] = updated
    incorporar_novos(new,updates,new_bases,counts)
    updates = {p:t for p,t in updates.items() if not p.exists() or p.read_text()!=t}
    report = {'nova_lista':len(new),'associadas_por_tipo':dict(collections.Counter(e['kind'] for e in mapping.values())),
              'alteracoes':dict(counts),'arquivos':len(updates)+1,'sem_correspondencia':unmatched,
              'referencias_ausentes_usadas':dict(missing_used),'aplicado':args.aplicar}
    (out/'relatorio.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    (out/'titulos-sem-fonte.json').write_text(json.dumps(removed_titles,ensure_ascii=False,indent=2)+'\n')
    (out/'arquivos-novos.json').write_text(json.dumps([str(p.relative_to(ROOT)) for p in updates if not p.exists()],ensure_ascii=False,indent=2)+'\n')
    if args.aplicar:
        for path in [*updates,ROOT/'1.m3u']:
            backup = out/'backup'/path.relative_to(ROOT)
            backup.parent.mkdir(parents=True,exist_ok=True)
            if path.exists(): shutil.copy2(path,backup)
        for path,text in updates.items():
            temp=path.with_suffix(path.suffix+'.tmp'); temp.write_text(text); temp.replace(path)
        (ROOT/'1.m3u').write_text(args.lista.read_text(encoding='utf-8-sig'))
    print(json.dumps({k:v for k,v in report.items() if k not in ('sem_correspondencia','referencias_ausentes_usadas')},ensure_ascii=False))
    print('Relatório e backup:',out)


if __name__ == '__main__':
    main()
