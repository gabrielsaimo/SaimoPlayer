#!/usr/bin/env python3
"""Importação aditiva com prévia, backup e preservação das fontes atuais."""
import argparse
import collections
import datetime
import difflib
import json
from pathlib import Path
import re
import shutil
from substituir_reservas_m3u import ROOT, parse, incorporar_novos, limpar, norm, chave, separar_ano, EPISODIO
from organizar_canais_importados import blocks, name, normalized, canonical_name, is_open_channel

LIVE_ALIASES = {
    'CARTOON NETWOORK':'Cartoon Network', 'FOOD NETWOORK':'Food Network',
    'TOONSCAST':'Tooncast', 'SONY':'Sony Channel', 'UNIVERSAL CHANNEL':'Universal TV',
    'DISCOVERY HOME & HEALT':'Discovery Home & Health', 'DISCOVERY TLC':'TLC',
    'ID - INVESTIGAÇÃO DISCOVERY':'Discovery ID', 'NOVELAS GLOBOPLAY':'Globoplay Novelas',
    'JOVEM PAN':'Jovem Pan News', 'RECORD GOIAS':'Record GO', 'RECORD MINAS':'Record MG',
    'SBT PIAUI':'SBT PI', 'SBT PARANA':'SBT PR',
    '3 ESPIÃS DEMAIS':'Tres Espias Demais',
    'CHAVES ANIMADO':'Chaves Em Desenho Animado', 'CHAVES DESENHO':'Chaves Em Desenho Animado',
    'CAVERNA DO DRAGÃAO':'Caverna do Dragao', 'BIG BANG THEORY':'The Big Bang Theory',
    'A HORA DE AVENTURA':'Hora de Aventura', 'SPIDER MAN':'Homem Aranha',
}


def clean_live(text):
    text = re.sub(r'[¹²³⁴⁵⁶⁷⁸⁹*]', '', text)
    text = re.sub(r'(?i)(?:H\.?26[45]|\.265)\b', '', text)
    text = re.sub(r'(?i)\b24\s*HS?\b', '', text)
    text = re.sub(r'\[\s*\]', '',limpar(text)[0]).strip()
    aliases = {normalized(k):v for k,v in LIVE_ALIASES.items()}
    text = aliases.get(normalized(text),text)
    text = re.sub(r'(?i)^PRIME VIDEO\s+(\d+)$',r'Amazon Prime Video \1',text)
    text = re.sub(r'(?i)^CANAL GOAT\s+(\d+)$',lambda m:'Canal GOAT (Jogo '+str(int(m[1]))+')',text)
    text = re.sub(r'(?i)^PARAMOUNT\s*\+\s*(\d+)$',lambda m:'Paramount+ (Jogo '+str(int(m[1]))+')',text)
    text = re.sub(r'(?i)^UFC FIGHT\s+(\d+)$',r'UFC Fight Pass \1',text)
    text = re.sub(r'(?i)^MR\. OLYMPIA 2026\s+(\d+)$',r'Mr Olympia \1',text)
    text = re.sub(r'(?i)^NBA\s*\|\s*League Pass\s+(\d+)$',r'NBA League Pass \1',text)
    return canonical_name(text)


def vod_key(e):
    return e['kind'],norm(e['name'])


def protect(before, after):
    """Nunca remover fontes, títulos ou episódios já existentes."""
    for p,old in before.items():
        if re.fullmatch(r'(filmes|reservado)-[#A-Z]\.txt',p.name):
            newer={l.split('\t')[0]:l.split('\t')[1:] for l in after[p].splitlines() if l}
            for l in old.splitlines():
                if not l:continue
                f=l.split('\t'); assert f[0] in newer
                for v in f[1:]:
                    nv=next(w for w in newer[f[0]] if w.startswith(v[:4]))
                    assert nv[4:].split(',')[:len(v[4:].split(','))]==v[4:].split(',')
        elif re.fullmatch(r'series-[#A-Z]-\d+\.txt',p.name):
            def rows(t):
                r={};h=''
                for l in t.splitlines():
                    if l.startswith('@'):h=l
                    elif l:
                        f=l.split('\t');r[h,*f[:3]]=f[3].split(',')
                return r
            newer=rows(after[p])
            for k,v in rows(old).items():assert newer[k][:len(v)]==v
        elif p.name in ('catalogo.txt','restritos.txt'):
            newer={name(b):b for b in blocks(after[p])[1]}
            for b in blocks(old)[1]:
                assert name(b) in newer
                src=re.findall(r'^fonte: (.+)$',b,re.M)
                assert re.findall(r'^fonte: (.+)$',newer[name(b)],re.M)[:len(src)]==src
            old_open={name(b) for b in blocks(old)[1] if 'categoria: TV Aberta' in b}
            new_open={name(b) for b in newer.values() if 'categoria: TV Aberta' in b}
            assert old_open==new_open


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('listas',nargs='+',type=Path);ap.add_argument('--aplicar',action='store_true')
    args=ap.parse_args()
    index=ROOT/'vod/indice.txt';updates={};counts=collections.Counter();pending=[];summaries=[]
    before={p:p.read_text() for p in [*(ROOT/'vod').glob('*.txt'),ROOT/'catalogo.txt',ROOT/'restritos.txt']}
    bases=dict(re.findall(r'^base: (\d+) (.+)$',before[index],re.M))
    references=collections.defaultdict(set)
    for e in parse(ROOT/'1.m3u'):
        if e['kind']!='channel':references[vod_key(e)].add(e['url'])
    known={normalized(clean_live(name(b))):name(b) for p in [ROOT/'catalogo.txt',ROOT/'restritos.txt'] for b in blocks(before[p])[1]}
    for path in args.listas:
        entries=parse(path); total=len(entries); filtered=[]
        for e in entries:
            if e['kind']=='channel':
                n=clean_live(e['name']); k=normalized(n); group=norm(e['group'])
                if 'radio' in group:
                    counts['radios_nao_importadas']+=1;continue
                if k not in known:
                    if is_open_channel(n,group) or re.search(r'canais[: |]+(?:band|sbt|record|redetv|globo)\b',group):
                        counts['fontes_de_abertos_novos_ignoradas']+=1;continue
                    if 'jogos' in group and re.search(r'\d\d:\d\d',n):
                        pending.append({'tipo':'evento_com_horario','nome':e['name']});continue
                    if '24' in group and re.search(r'\s\d{1,2}$',n):
                        pending.append({'tipo':'canal_24h_numerado','nome':e['name']});continue
                    close=difflib.get_close_matches(k,known,n=1,cutoff=.83)
                    if close:
                        pending.append({'tipo':'canal_nome_semelhante','nome':e['name'],'possivel':known[close[0]]});continue
                    known[k]=n
                # Retém a qualidade da fonte, mas usa o nome canônico para agrupamento.
                q=re.search(r'(?i)\b(4K|UHD|FHD|HD|SD)\b',e['name'])
                e['name']=known[k]+(' ['+q[1]+']' if q else '')
            else:
                adult_group=(any(w in norm(e['group']) for w in ('adult','xxx','+18'))
                             or bool(re.match(r'(?i)^XXX\s+\d{4}\.\d{2}\.\d{2}\b',e['name'])))
                e['adult']=adult_group
                if e['kind']=='series' and adult_group and not EPISODIO.match(limpar(e['name'])[0]):
                    # Alguns provedores entregam filmes na rota /series/.
                    e['kind']='movie'
                refs=references.get(vod_key(e),set())
                if len(refs)==1:e['identity_url']=next(iter(refs))
                if adult_group and not limpar(e['name'])[2]:
                    e['name']+=' [Adulto]'
            filtered.append(e)
        for base in sorted({e['url'].rsplit('/',1)[0]+'/' for e in filtered if e['kind']!='channel'}):
            if base not in bases.values():bases[str(max(map(int,bases))+1)]=base
        updates[index]='\n'.join('base: '+n+' '+b for n,b in bases.items())+'\n'
        previous=dict(counts)
        incorporar_novos(filtered,updates,bases,counts)
        summaries.append({'arquivo':path.name,'entradas':total,'alteracoes':{k:v-previous.get(k,0) for k,v in counts.items() if v!=previous.get(k,0)}})
        for e in filtered:
            if e['kind']!='channel':
                # A próxima lista pode reconhecer o mesmo título recém-adicionado.
                references[vod_key(e)].add(e.get('identity_url',e['url']))
        print('Processada:',path.name,flush=True)
    updates={p:t for p,t in updates.items() if before.get(p)!=t}
    protect(before,{**before,**updates})
    stamp=datetime.datetime.now().strftime('%Y%m%d-%H%M%S');out=ROOT/'arquivos-gerados'/('adicao-reservas-'+stamp);out.mkdir(parents=True)
    report={'listas':summaries,'totais':dict(counts),'pendentes':pending,'arquivos':len(updates),'aplicado':args.aplicar}
    def titles(t):return {l.split('\t')[0] for l in t.splitlines() if l}
    details={'novos_canais':[], 'novas_series':[], 'novos_filmes_publicos':[], 'novos_filmes_restritos':0}
    for p,t in updates.items():
        if p.name in ('catalogo.txt','restritos.txt'):
            old_names={name(b) for b in blocks(before[p])[1]}
            details['novos_canais'].extend(name(b) for b in blocks(t)[1] if name(b) not in old_names)
        elif re.fullmatch(r'series-[#A-Z]-\d+\.txt',p.name):
            details['novas_series'].extend(sorted({l for l in t.splitlines() if l.startswith('@')}-{l for l in before.get(p,'').splitlines() if l.startswith('@')}))
        elif re.fullmatch(r'filmes-[#A-Z]\.txt',p.name):
            details['novos_filmes_publicos'].extend(sorted(titles(t)-titles(before.get(p,''))))
        elif re.fullmatch(r'reservado-[#A-Z]\.txt',p.name):
            details['novos_filmes_restritos']+=len(titles(t)-titles(before.get(p,'')))
    (out/'novidades.json').write_text(json.dumps(details,ensure_ascii=False,indent=2)+'\n')
    (out/'relatorio.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    if args.aplicar:
        for p in updates:
            backup=out/'backup'/p.relative_to(ROOT);backup.parent.mkdir(parents=True,exist_ok=True)
            if p.exists():shutil.copy2(p,backup)
        for p,t in updates.items():p.write_text(t)
    print(json.dumps({k:v for k,v in report.items() if k!='pendentes'},ensure_ascii=False))
    print('Pendências:',len(pending),'Relatório:',out)


if __name__=='__main__':main()
