#!/usr/bin/env python3
"""Procura a versão dublada de tudo que o app só tem legendado.

O atualizar_redeflix.py só olha a lista do Redeflix: título que já foi achado
não é mais consultado, e o que veio das listas M3U só legendado nunca é
procurado dublado. Este passo faz o caminho inverso — parte do acervo
publicado:

    filme sem dub=              -> id da ficha -> TMDB (confere nome e ano,
                                   pega o IMDb) -> EmbedPlayer
    episódio sem linha dub      -> id da ficha -> TMDB (confere) ->
                                   /tv/id/temporada/episódio/dub

A ficha (vod/fichas.txt, do gerar_generos.py) vem da primeira resposta de uma
busca por nome, e às vezes é outro título. Colar o áudio de outro filme num
cartão é pior que não ter dublado, então o id só vale se o nome e o ano baterem
com o TMDB.

O cache é o mesmo do atualizar_redeflix.py: o que já está dublado nele não é
consultado de novo, e o que foi tentado e não deu fica quieto por
--dias-repescagem dias (0 = tenta tudo). O que achar vai para
vod/redeflix/dublados-filmes.txt e dublados-series.txt, com o título exato do
acervo, e o gerar_vod.py junta ali, no mesmo cartão.

    python3 dublar_legendados.py                      o que não foi tentado na semana
    python3 dublar_legendados.py --dias-repescagem 0  tenta tudo de novo
"""
from __future__ import annotations

import argparse
import concurrent.futures
import contextlib
import json
import re
import threading
import time

import atualizar_redeflix as rf
from atualizar_redeflix import Episode, Resolved, _chave_de_nome
from gerar_embedplayer_filmes import acquire_execution_lock, atomic_write, discover_tmdb_key, resolve_embed, tmdb_json

DUBLADOS_FILMES = rf.STATE / "dublados-filmes.txt"
DUBLADOS_SERIES = rf.STATE / "dublados-series.txt"
ANO_NO_TITULO = re.compile(r"\s*\(((?:19|20)\d{2})\)\s*$")
PRINT = threading.Lock()


def legendados_do_acervo() -> tuple[list[str], dict[tuple[str, str], set[tuple[int, int]]]]:
    """Filmes sem dub= e, por série, os episódios sem linha dub."""
    vod = rf.ROOT / "vod"
    filmes: list[str] = []
    for caminho in sorted(vod.glob("filmes-*.txt")):
        if not re.fullmatch(r"filmes-(?:#|[A-Z])\.txt", caminho.name):
            continue
        for linha in caminho.read_text(encoding="utf-8").splitlines():
            campos = linha.split("\t")
            versoes = {c.split("=", 1)[0] for c in campos[1:] if "=" in c}
            if campos[0] and "leg" in versoes and "dub" not in versoes:
                filmes.append(campos[0])
    series: dict[tuple[str, str], set[tuple[int, int]]] = {}
    for caminho in sorted(vod.glob("series-*-*.txt")):
        atual: tuple[str, str] | None = None
        versoes: dict[tuple[int, int], set[str]] = {}
        for linha in caminho.read_text(encoding="utf-8").splitlines() + ["@"]:
            if linha.startswith("@"):
                if atual is not None:
                    so_leg = {ep for ep, v in versoes.items() if "leg" in v and "dub" not in v}
                    if so_leg:
                        series.setdefault(atual, set()).update(so_leg)
                campos = linha[1:].split("\t")
                atual = (campos[0].strip(), campos[1].strip() if len(campos) > 1 else "")
                versoes = {}
                continue
            campos = linha.split("\t")
            if atual is None or len(campos) < 4:
                continue
            with contextlib.suppress(ValueError):
                versoes.setdefault((int(campos[0]), int(campos[1])), set()).add(campos[2])
    return filmes, series


def fichas_tmdb() -> dict[tuple[str, str], str]:
    """(tipo, título do acervo) -> id TMDB."""
    saida: dict[tuple[str, str], str] = {}
    with contextlib.suppress(OSError):
        for linha in (rf.ROOT / "vod" / "fichas.txt").read_text(encoding="utf-8").splitlines():
            campos = linha.split("\t")
            if len(campos) >= 3 and campos[0] in ("f", "s") and campos[2].isdigit():
                saida[(campos[0], campos[1])] = campos[2]
    return saida


def mesmo_titulo(do_acervo: str, ano_acervo: str, nomes: list, ano_tmdb: str) -> bool:
    """Nome igual (ou um começando pelo outro, com ano batendo) e ano com folga de um."""
    alvo = _chave_de_nome(do_acervo)
    if not alvo:
        return False
    if ano_acervo and ano_tmdb and abs(int(ano_acervo) - int(ano_tmdb)) > 1:
        return False
    for nome in nomes:
        candidato = _chave_de_nome(str(nome or ""))
        if not candidato:
            continue
        if candidato == alvo:
            return True
        # Subtítulo que só um lado escreve ("Rocky" x "Rocky Um Lutador"). Sem
        # ano dos dois lados não vale: "Duna" pegaria qualquer continuação.
        curto, longo = sorted((candidato, alvo), key=len)
        if ano_acervo and ano_tmdb and longo.startswith(curto + " ") and len(curto) >= 6:
            return True
    return False


def ler_dublados_filmes() -> dict[str, list[str]]:
    saida: dict[str, list[str]] = {}
    with contextlib.suppress(OSError):
        for linha in DUBLADOS_FILMES.read_text(encoding="utf-8").splitlines():
            campos = linha.split("\t")
            for campo in campos[1:]:
                if campo.startswith("dub="):
                    saida[campos[0]] = [u for u in campo[4:].split(",") if u]
    return saida


def ler_dublados_series() -> dict[tuple[str, str], dict[tuple[int, int], list[str]]]:
    saida: dict[tuple[str, str], dict[tuple[int, int], list[str]]] = {}
    atual = None
    with contextlib.suppress(OSError):
        for linha in DUBLADOS_SERIES.read_text(encoding="utf-8").splitlines():
            if linha.startswith("@"):
                campos = linha[1:].split("\t")
                atual = (campos[0], campos[1] if len(campos) > 1 else "")
                saida.setdefault(atual, {})
                continue
            campos = linha.split("\t")
            if atual is None or len(campos) < 4 or campos[2] != "dub":
                continue
            with contextlib.suppress(ValueError):
                saida[atual][(int(campos[0]), int(campos[1]))] = campos[3].split(",")
    return saida


def tem_dub(item: Resolved | None) -> bool:
    return bool(item and item.status == "encontrado"
                and any(s.language != "leg" for s in item.sources))


def dubs(item: Resolved) -> list[str]:
    return [s.url for s in item.sources if s.language != "leg"]


def progresso(rotulo: str, feitos: int, total: int, comeco: float, achados: int) -> None:
    ritmo = feitos / max(time.monotonic() - comeco, 0.001)
    falta = (total - feitos) / max(ritmo, 0.001) / 60
    with PRINT:
        print(f"[dublados · {rotulo} {feitos}/{total}] {ritmo:.1f}/s · ETA {falta:.1f} min · "
              f"dublado achado: {achados}", flush=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("--workers", type=int, default=96)
    parser.add_argument("--dias-repescagem", type=int, default=7,
                        help="não reconsulta o que foi tentado há menos que isso (0 = tudo)")
    parser.add_argument("--tentativas-indisponiveis", type=int, default=2)
    parser.add_argument("--delay-episodio", type=float, default=0.05)
    parser.add_argument("--tmdb-key", default="")
    parser.add_argument("--sem-validar", action="store_true")
    parser.add_argument("--cache", default=str(rf.OUTPUT / "cache.sqlite3"))
    args = parser.parse_args()

    lock = acquire_execution_lock(rf.OUTPUT)
    db = rf.open_cache(__import__("pathlib").Path(args.cache))
    rf.import_legacy(db)
    cached = rf.load_cache(db)
    tentado_em = {
        (m, t, s, e): u for m, t, s, e, u in db.execute(
            "SELECT media_type,tmdb,season,episode,updated_at FROM resolved")
    }
    limite = time.time() - args.dias_repescagem * 86400

    def pode_tentar(chave) -> bool:
        # Erro não é resposta: foi o serviço que falhou (em 28/09/2026 o
        # EmbedPlayer passou a dar 520 em tudo). Esse tenta de novo sempre.
        antigo = cached.get(chave)
        if antigo is not None and antigo.status == "erro":
            return True
        return args.dias_repescagem <= 0 or tentado_em.get(chave, 0) < limite

    class Disjuntor:
        """Muitos erros seguidos: o serviço caiu. Parar poupa horas de 520."""
        LIMITE = 150

        def __init__(self) -> None:
            self.seguidos = 0

        def conta(self, item: Resolved | None) -> bool:
            self.seguidos = self.seguidos + 1 if item is not None and item.status == "erro" else 0
            return self.seguidos >= self.LIMITE

    caiu = ""

    fichas = fichas_tmdb()
    filmes, series = legendados_do_acervo()
    print(f"Só legendado no acervo: {len(filmes)} filmes, {len(series)} séries "
          f"({sum(len(v) for v in series.values())} episódios)", flush=True)

    tmdb_key = discover_tmdb_key(args.tmdb_key)
    detalhes: dict[tuple[str, str], dict | None] = {}
    detalhes_lock = threading.Lock()

    def detalhe(tipo: str, tmdb: str) -> dict | None:
        with detalhes_lock:
            if (tipo, tmdb) in detalhes:
                return detalhes[(tipo, tmdb)]
        # Mesmo espaçamento do atualizador: o TMDB corta rajada com 429.
        with rf.TMDB_RATE_LOCK:
            espera = rf.TMDB_NEXT_REQUEST - time.monotonic()
            if espera > 0:
                time.sleep(espera)
            rf.TMDB_NEXT_REQUEST = time.monotonic() + 0.04
        # Títulos alternativos e traduções vêm na mesma resposta: a lista M3U
        # escreve "Article 370" onde o TMDB em português diz "Artigo 370".
        extra = {"append_to_response": ("external_ids," if tipo == "movie" else "")
                 + "alternative_titles,translations"}
        try:
            dados = tmdb_json(f"/{tipo}/{tmdb}", {"language": "pt-BR", **extra}, tmdb_key)
        except Exception:
            dados = None
        with detalhes_lock:
            detalhes[(tipo, tmdb)] = dados
        return dados

    def confere(tipo: str, tmdb: str, titulo: str, ano: str) -> dict | None:
        dados = detalhe(tipo, tmdb)
        if not dados:
            return None
        if tipo == "movie":
            nomes = [dados.get("title"), dados.get("original_title")]
            ano_tmdb = str(dados.get("release_date") or "")[:4]
        else:
            nomes = [dados.get("name"), dados.get("original_name")]
            ano_tmdb = str(dados.get("first_air_date") or "")[:4]
        alternativos = dados.get("alternative_titles") or {}
        for alt in alternativos.get("titles") or alternativos.get("results") or []:
            nomes.append(alt.get("title"))
        for traducao in (dados.get("translations") or {}).get("translations") or []:
            info = traducao.get("data") or {}
            nomes.append(info.get("title") or info.get("name"))
        ano_tmdb = ano_tmdb if ano_tmdb.isdigit() else ""
        return dados if mesmo_titulo(titulo, ano, nomes, ano_tmdb) else None

    db_lock = threading.Lock()

    def guardar(item: Resolved) -> Resolved:
        chave = (item.media_type, item.tmdb, item.season, item.episode)
        with db_lock:
            antigo = cached.get(chave)
            # Achado nunca é trocado por não-achado; o antigo só ganha a data nova.
            if antigo and antigo.status == "encontrado" and not tem_dub(item):
                if item.status != "encontrado" or tem_dub(antigo):
                    item = antigo
            rf.save(db, item)
            cached[chave] = item
        return item

    rejeitados: list[str] = []
    sem_ficha = 0

    # --- filmes
    tarefas_filme: list[tuple[str, str]] = []
    for titulo in filmes:
        tmdb = fichas.get(("f", titulo))
        if not tmdb:
            sem_ficha += 1
            continue
        chave = ("movie", tmdb, 0, 0)
        if tem_dub(cached.get(chave)) or pode_tentar(chave):
            tarefas_filme.append((titulo, tmdb))

    def dublar_filme(titulo: str, tmdb: str):
        achado = ANO_NO_TITULO.search(titulo)
        dados = confere("movie", tmdb, ANO_NO_TITULO.sub("", titulo).strip(),
                        achado.group(1) if achado else "")
        if dados is None:
            return titulo, tmdb, None, False
        antigo = cached.get(("movie", tmdb, 0, 0))
        if tem_dub(antigo):
            return titulo, tmdb, antigo, True
        nome = str(dados.get("title") or dados.get("original_title") or titulo)
        ano = str(dados.get("release_date") or "")[:4]
        imdb = str((dados.get("external_ids") or {}).get("imdb_id") or "")
        if not re.fullmatch(r"tt\d{7,10}", imdb):
            return titulo, tmdb, Resolved("movie", tmdb, 0, 0, "sem_imdb", nome, ano), True
        try:
            sources, _ = resolve_embed(imdb, not args.sem_validar)
        except Exception as erro:
            return titulo, tmdb, Resolved("movie", tmdb, 0, 0, "erro", nome, ano, imdb,
                                          error=f"{type(erro).__name__}: {erro}"), True
        status = "encontrado" if sources else "indisponivel"
        return titulo, tmdb, Resolved("movie", tmdb, 0, 0, status, nome, ano, imdb, sources), True

    achados_filme: dict[str, list[str]] = {}
    print(f"Filmes a conferir: {len(tarefas_filme)} (sem ficha no TMDB: {sem_ficha})", flush=True)
    comeco = time.monotonic()
    disjuntor = Disjuntor()
    with concurrent.futures.ThreadPoolExecutor(max_workers=min(args.workers, 32)) as pool:
        futuros = [pool.submit(dublar_filme, t, i) for t, i in tarefas_filme]
        for feitos, futuro in enumerate(concurrent.futures.as_completed(futuros), 1):
            titulo, tmdb, item, conferiu = futuro.result()
            if not conferiu:
                rejeitados.append(f"{titulo} ≠ TMDB {tmdb}")
            elif item is not None:
                item = guardar(item)
                if tem_dub(item):
                    achados_filme[titulo] = dubs(item)
            if conferiu and disjuntor.conta(item):
                caiu = item.error if item else "erro"
                pool.shutdown(wait=False, cancel_futures=True)
                break
            if feitos % 50 == 0 or feitos == len(futuros):
                with db_lock:
                    db.commit()
                progresso("filmes", feitos, len(futuros), comeco, len(achados_filme))

    # --- séries: primeiro confere cada id, depois os episódios
    candidatas = []
    for titulo, ano in series:
        tmdb = fichas.get(("s", titulo))
        if tmdb:
            candidatas.append((titulo, ano, tmdb))
        else:
            sem_ficha += 1
    conferidas: dict[tuple[str, str], str] = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=16) as pool:
        resultados = pool.map(lambda c: confere("tv", c[2], c[0], c[1]), candidatas)
        for (titulo, ano, tmdb), dados in zip(candidatas, resultados):
            if dados is None:
                rejeitados.append(f"{titulo} ≠ TMDB {tmdb}")
            else:
                conferidas[(titulo, ano)] = tmdb
    print(f"Séries conferidas no TMDB: {len(conferidas)} de {len(candidatas)}", flush=True)

    achados_serie: dict[tuple[str, str], dict[tuple[int, int], list[str]]] = {}
    tarefas_ep: list[tuple[tuple[str, str], Episode]] = []
    for serie, tmdb in conferidas.items():
        for temporada, episodio in sorted(series[serie]):
            chave = ("tv", tmdb, temporada, episodio)
            antigo = cached.get(chave)
            if tem_dub(antigo):
                achados_serie.setdefault(serie, {})[(temporada, episodio)] = dubs(antigo)
            elif pode_tentar(chave):
                tarefas_ep.append((serie, Episode("series", tmdb, serie[0], serie[1], temporada, episodio)))
    do_cache = sum(len(v) for v in achados_serie.values())
    print(f"Episódios: {do_cache} já dublados no cache, {len(tarefas_ep)} a consultar", flush=True)

    comeco = time.monotonic()
    novos_ep = 0
    if caiu:
        tarefas_ep = []  # o serviço já caiu nos filmes: nem começa os episódios
    disjuntor = Disjuntor()
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        futuros = {
            pool.submit(rf.process_episode, ep, not args.sem_validar,
                        args.tentativas_indisponiveis, args.delay_episodio): serie
            for serie, ep in tarefas_ep
        }
        for feitos, futuro in enumerate(concurrent.futures.as_completed(futuros), 1):
            item = guardar(futuro.result())
            if tem_dub(item):
                novos_ep += 1
                achados_serie.setdefault(futuros[futuro], {})[(item.season, item.episode)] = dubs(item)
            if disjuntor.conta(item):
                caiu = item.error or "erro"
                pool.shutdown(wait=False, cancel_futures=True)
                break
            if feitos % 100 == 0 or feitos == len(futuros):
                with db_lock:
                    db.commit()
                progresso("episódios", feitos, len(futuros), comeco, novos_ep)
    db.commit()
    db.close()

    # Soma com o que rodadas anteriores acharam: o arquivo é o registro do que
    # veio dublado, e o gerar_vod.py só junta em título que o acervo tem.
    todos_filmes = ler_dublados_filmes()
    for titulo, urls in achados_filme.items():
        todos_filmes[titulo] = list(dict.fromkeys(urls + todos_filmes.get(titulo, [])))
    atomic_write(DUBLADOS_FILMES, "".join(
        f"{t}\tdub={','.join(u)}\n" for t, u in sorted(todos_filmes.items()) if u))
    todas_series = ler_dublados_series()
    for serie, eps in achados_serie.items():
        destino = todas_series.setdefault(serie, {})
        for ep, urls in eps.items():
            destino[ep] = list(dict.fromkeys(urls + destino.get(ep, [])))
    linhas = []
    for (titulo, ano), eps in sorted(todas_series.items()):
        if eps:
            linhas.append(f"@{titulo}\t{ano}")
            linhas += [f"{s}\t{e}\tdub\t{','.join(u)}" for (s, e), u in sorted(eps.items()) if u]
    atomic_write(DUBLADOS_SERIES, "\n".join(linhas) + ("\n" if linhas else ""))

    if caiu:
        print(f"PAROU: {Disjuntor.LIMITE} erros seguidos do EmbedPlayer ({caiu}). O serviço está "
              "fora ou barrando; o que foi achado está salvo e o resto é tentado na próxima rodada.",
              flush=True)
    if rejeitados:
        print(f"Ficha com id de outro título (ignorada): {len(rejeitados)}; ex.: "
              + " | ".join(rejeitados[:5]), flush=True)
    resumo = {
        "filmes_so_legendados": len(filmes),
        "filmes_com_dublado": len(achados_filme),
        "series_so_legendadas": len(series),
        "series_conferidas": len(conferidas),
        "episodios_consultados": len(tarefas_ep),
        "episodios_dublados_novos": novos_ep,
        "episodios_dublados_do_cache": do_cache,
        "sem_ficha": sem_ficha,
        "ficha_errada": len(rejeitados),
        "servico_caiu": caiu,
    }
    print("Dublados: " + json.dumps(resumo, ensure_ascii=False), flush=True)
    atomic_write(rf.OUTPUT / "ultimos-dublados.json", json.dumps(resumo, ensure_ascii=False, indent=2) + "\n")
    lock.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
