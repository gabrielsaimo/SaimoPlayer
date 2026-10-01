#!/usr/bin/env python3
"""Executa consultas e testes numa cópia isolada, sem publicar nem excluir."""
import concurrent.futures
import datetime
import json
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[1]


def run(job):
    work=job/'copia'
    env=dict(os.environ,PYTHONUNBUFFERED='1',PYTHONDONTWRITEBYTECODE='1')
    sys.path.insert(0,str(ROOT))
    from gerar_embedplayer_filmes import discover_tmdb_key
    env['TMDB_API_KEY']=discover_tmdb_key('')
    def command(script,args,log):
        with (job/log).open('a') as f:
            return subprocess.run([sys.executable,'-B',str(work/script),*args],cwd=work,env=env,stdout=f,stderr=subprocess.STDOUT).returncode
    def discovery():
        # O teste real de dublagem tem disjuntor para indisponibilidade do provedor.
        code=command('dublar_legendados.py',['--workers','8','--dias-repescagem','0'],'descoberta.log')
        summary=work/'arquivos-gerados/redeflix/ultimos-dublados.json'
        data=json.loads(summary.read_text()) if summary.exists() else {}
        (job/'dublagem.json').write_text(json.dumps({'saida':code,**data},ensure_ascii=False,indent=2))
        if data.get('servico_caiu'):
            (job/'novidades-status.txt').write_text('Busca de títulos/episódios faltantes interrompida: o provedor retornou erros consecutivos.\n'+data['servico_caiu']+'\nNada foi removido ou publicado.\n')
            return 'bloqueada pelo provedor'
        if code:return 'erro na consulta; veja descoberta.log'
        code=command('atualizar_redeflix.py',['--gerar','--repetir-erros','--repetir-indisponiveis','--workers','8'],'descoberta.log')
        return 'concluída' if not code else 'erro na busca de novidades'
    def health():
        code=command('testar_fontes_vod.py',['--tudo','--workers','32','--por-servidor','2'],'testes.log')
        return 'concluída' if not code else 'erro nos testes'
    state={'inicio':datetime.datetime.now().isoformat(),'testes':'em execução','descoberta':'em execução','catalogo_original':'não alterado'}
    (job/'status.json').write_text(json.dumps(state,ensure_ascii=False,indent=2))
    with concurrent.futures.ThreadPoolExecutor(2) as pool:
        futures={pool.submit(discovery):'descoberta',pool.submit(health):'testes'}
        for future in concurrent.futures.as_completed(futures):
            key=futures[future]
            try:state[key]=future.result()
            except Exception as e:state[key]='erro: '+type(e).__name__
            (job/'status.json').write_text(json.dumps(state,ensure_ascii=False,indent=2))
    state['fim']=datetime.datetime.now().isoformat()
    (job/'status.json').write_text(json.dumps(state,ensure_ascii=False,indent=2))


def resume_tests(job):
    state=json.loads((job/'status.json').read_text())
    state.pop('fim',None)
    state.update(testes='em execução (acelerado)',concorrencia='96 total; começa em 2 e sobe até 6 por servidor',modo='disponibilidade sem medir resolução')
    (job/'status.json').write_text(json.dumps(state,ensure_ascii=False,indent=2))
    with (job/'testes.log').open('a') as log:
        log.write('\n=== RETOMADA ACELERADA: progresso preservado; 96 workers, até 6 por servidor; sem medir resolução ===\n');log.flush()
        code=subprocess.run([sys.executable,'-B',str(job/'copia/testar_fontes_vod.py'),
            '--tudo','--workers','96','--por-servidor','6','--horas','168','--somente-disponibilidade'],
            stdout=log,stderr=subprocess.STDOUT).returncode
    state.update(testes='concluída' if not code else 'erro nos testes',fim=datetime.datetime.now().isoformat())
    (job/'status.json').write_text(json.dumps(state,ensure_ascii=False,indent=2))


def start():
    job=ROOT/'arquivos-gerados'/('auditoria-acervo-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S'))
    work=job/'copia';work.mkdir(parents=True)
    for p in ROOT.glob('*.py'):shutil.copy2(p,work/p.name)
    shutil.copytree(ROOT/'vod',work/'vod')
    cache=work/'arquivos-gerados/redeflix';cache.mkdir(parents=True)
    candidates=[ROOT/'arquivos-gerados/redeflix/cache.sqlite3',Path('/Users/gabrielespindola/Library/Application Support/SaimoTV/SaimoPlayer/arquivos-gerados/redeflix/cache.sqlite3')]
    available=[p for p in candidates if p.exists()]
    if available:
        source=max(available,key=lambda p:p.stat().st_mtime)
        with sqlite3.connect(source.as_uri()+'?mode=ro',uri=True) as src, sqlite3.connect(cache/'cache.sqlite3') as dst:src.backup(dst)
    (job/'LEIA-ME.txt').write_text('AUDITORIA ISOLADA — nenhuma alteração no catálogo publicado.\n'
        'testes.log: andamento dos testes de filmes e de todos os episódios.\n'
        'descoberta.log: procura de dublagens e conteúdos faltantes.\n'
        'copia/arquivos-gerados/fontes-vod/: relatórios e progresso dos testes.\n'
        'Uma falha atual não prova que o link funcionava antes. Bloqueios e erros temporários são inconclusivos.\n'
        'O teste inspeciona cabeçalhos/playlists, não reproduz os vídeos inteiros.\n'
        'Fontes suspeitas devem ser revistas; nada será removido automaticamente.\n')
    with (job/'execucao.log').open('a') as log:
        p=subprocess.Popen([sys.executable,'-B',__file__,'--run',str(job)],cwd=ROOT,stdin=subprocess.DEVNULL,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
    (job/'pid.txt').write_text(str(p.pid)+'\n')
    print(json.dumps({'pasta':str(job),'pid':p.pid},ensure_ascii=False))


if __name__=='__main__':
    if len(sys.argv)>1 and sys.argv[1]=='--run':run(Path(sys.argv[2]))
    elif len(sys.argv)>1 and sys.argv[1]=='--resume-tests':resume_tests(Path(sys.argv[2]))
    else:start()
