#!/usr/bin/env python3
"""Fontes de filmes e séries da lista principal (nixplay, conta cinevs-vods).

A lista M3U da conta traz cada filme e cada episódio com o id do TMDB:

    #EXTINF:-1 tvg-id="614696" tvg-name="#Alive" ... group-title="Filmes - Ação",#Alive
    https://nixplay.lat/movie/<usuario>/<senha>/614696.mp4?economy=1
    #EXTINF:-1 tvg-id="289708001001" tvg-name="Bloom Life - S01E01" ...
    https://nixplay.lat/series/<usuario>/<senha>/289708/1/1.mp4?economy=1&lang=leg

O id casa com o das fichas do acervo (vod/fichas.txt), então cada fonte vai
para o título certo mesmo quando o nome difere ("#Alive" na lista, "#Alive
(2020)" no acervo) e sem confundir refilmagens. Título que o acervo não tem
entra com o nome da lista.

`economy=1` não muda nada (o mesmo arquivo, do mesmo tamanho) e sai;
`lang=leg` marca a versão legendada e fica.

A conta não tem canais ao vivo: só filmes e séries.

Grava arquivos-gerados/nixplay/links-filmes.txt e links-series.txt no formato do acervo;
gerar_vod.py põe estas fontes na frente das outras, por ser a lista principal.

    python3 atualizar_nixplay.py
"""
import re
import socket
import time
from collections import defaultdict
from pathlib import Path
from urllib.parse import parse_qsl, urlencode
from urllib.request import Request, urlopen

# Evita travar em SYN_SENT IPv6 quando a rota IPv6 da operadora falha.
_orig_getaddrinfo = socket.getaddrinfo
def _ipv4_first(host, port, family=0, type=0, proto=0, flags=0):
    res = _orig_getaddrinfo(host, port, family, type, proto, flags)
    return sorted(res, key=lambda r: 0 if r[0] == socket.AF_INET else 1)
socket.getaddrinfo = _ipv4_first

RAIZ = Path(__file__).resolve().parent
LISTA = "https://nixplay.lat/get.php?username=cinevs-vods&password=wrcmBDcf4&type=m3u_plus"
SERIE_BASE = "https://nixplay.lat/series/cinevs-vods/wrcmBDcf4/"
SERIE_BASE_IDX = 19
CACHE = RAIZ / "arquivos-gerados" / "nixplay" / "lista.m3u"
SAIDA = RAIZ / "arquivos-gerados" / "nixplay"
FICHAS = RAIZ / "vod" / "fichas.txt"
BUSCA = RAIZ / "vod" / "busca.txt"
REDEFLIX = RAIZ / "vod" / "redeflix"
# "Bloom Life - S01E01" e "Born with Luck - S01E01 (Leg)": o nome da série é
# o que vem antes do episódio; "(Leg)" no fim de filme marca só a versão.
EPISODIO_NOME = re.compile(r"\s*-?\s*S\d{1,3}\s*E\d{1,4}\b.*$", re.I)
VERSAO_NOME = re.compile(r"\s*[\(\[](leg|legendado|dub|dublado|l)[\)\]]\s*$", re.I)
ANO_PAR = re.compile(r"\(\d{4}\)\s*$")


def nome_do_extinf(linha: str) -> str:
    """Extrai o título após a primeira vírgula fora de aspas."""
    dentro = False
    for posicao, caractere in enumerate(linha):
        if caractere == '"':
            dentro = not dentro
        elif caractere == "," and not dentro:
            return linha[posicao + 1:].strip()
    return linha.rsplit(",", 1)[-1].strip()


def baixar(forcar: bool = False) -> str:
    if not forcar and CACHE.exists() and (time.time() - CACHE.stat().st_mtime) < 1800:
        texto = CACHE.read_text(encoding="utf-8")
        if texto.startswith("#EXTM3U") and "#EXTINF" in texto:
            return texto
    pedido = Request(LISTA, headers={"User-Agent": "Mozilla/5.0"})
    try:
        with urlopen(pedido, timeout=180) as r:
            texto = r.read().decode("utf-8", "replace")
        if texto.startswith("#EXTM3U") and "#EXTINF" in texto:
            CACHE.parent.mkdir(parents=True, exist_ok=True)
            CACHE.write_text(texto, encoding="utf-8")
            return texto
    except OSError as erro:
        print(f"lista não baixou ({erro}); usando a última guardada")
    if CACHE.exists():
        return CACHE.read_text(encoding="utf-8")
    raise SystemExit("sem lista: nem baixada agora nem guardada antes")


def limpar(url: str) -> tuple[str, str]:
    """URL sem `economy` e a versão (dub ou leg) pelo `lang`."""
    base, _, consulta = url.partition("?")
    params = [(k, v) for k, v in parse_qsl(consulta) if k != "economy"]
    versao = "leg" if ("lang", "leg") in params else "dub"
    return (f"{base}?{urlencode(params)}" if params else base), versao


def encurtar_serie(url: str) -> str:
    if url.startswith(SERIE_BASE):
        resto = url[len(SERIE_BASE):]
        resto = resto[:-4] if resto.endswith(".mp4") else resto
        return f"{SERIE_BASE_IDX}:{resto}"
    return url


def fichas() -> dict[str, dict[str, str]]:
    """id do TMDB -> título canônico do acervo, separado em filme (f) e série (s).

    Um único título por id do TMDB evita ressuscitar grafias antigas que já
    saíram do acervo mas continuam guardadas em vod/fichas.txt. Prioriza quem
    já está em vod/busca.txt e, entre empatados, quem traz o ano no nome.
    """
    ativos: dict[str, set[str]] = {"f": set(), "s": set()}
    if BUSCA.exists():
        for linha in BUSCA.read_text(encoding="utf-8").splitlines():
            campos = linha.split("\t")
            if len(campos) >= 2 and campos[1] in ativos and campos[0]:
                ativos[campos[1]].add(campos[0])

    candidatos: dict[str, dict[str, list[str]]] = {"f": defaultdict(list), "s": defaultdict(list)}
    for linha in FICHAS.read_text(encoding="utf-8").splitlines():
        campos = linha.split("\t")
        if len(campos) >= 3 and campos[0] in candidatos and campos[2].isdigit():
            if campos[1] not in candidatos[campos[0]][campos[2]]:
                candidatos[campos[0]][campos[2]].append(campos[1])

    por_id: dict[str, dict[str, str]] = {"f": {}, "s": {}}
    for tipo in ("f", "s"):
        for tmdb, lista in candidatos[tipo].items():
            # Prioridade: (não está ativo no acervo atual, não tem ano explícito, posição original)
            melhor = min(
                enumerate(lista),
                key=lambda par: (
                    par[1] not in ativos[tipo],
                    not bool(ANO_PAR.search(par[1])),
                    par[0],
                ),
            )[1]
            por_id[tipo][tmdb] = melhor
    return por_id


def anos_das_series() -> dict[str, str]:
    """Título da série -> ano, como o acervo publicado escreve no cabeçalho.
    O ano faz parte da chave da série no gerar_vod.py: sem ele a fonte abriria
    uma série nova em vez de entrar na que existe."""
    anos: dict[str, str] = {}
    for arquivo in sorted((RAIZ / "vod").glob("series-*.txt")):
        for linha in arquivo.read_text(encoding="utf-8").splitlines():
            if linha.startswith("@"):
                campos = linha[1:].split("\t")
                anos.setdefault(campos[0].strip(), campos[1].strip() if len(campos) > 1 else "")
    return anos


def atualizar_colecoes_redeflix(
    eps_por_tmdb: dict[str, dict[tuple[int, int, str], list[str]]],
) -> None:
    """Injeta as fontes da NixPlay na frente de animes e doramas (vod/redeflix)."""
    for categoria in ("animes", "doramas"):
        cat_path = REDEFLIX / f"catalogo-{categoria}.txt"
        links_path = REDEFLIX / f"links-{categoria}.txt"
        if not cat_path.exists() or not links_path.exists():
            continue

        # Lê as fontes atuais já publicadas para preservá-las como reserva
        existentes: dict[str, dict[tuple[int, int, str], list[str]]] = defaultdict(lambda: defaultdict(list))
        metadados: dict[str, tuple[str, str]] = {}
        tmdb_atual = ""
        for linha in links_path.read_text(encoding="utf-8").splitlines():
            if linha.startswith("@"):
                campos = linha[1:].split("\t")
                titulo = campos[0].strip()
                ano = campos[1].strip() if len(campos) > 1 else ""
                tmdb_atual = campos[2].strip() if len(campos) > 2 else ""
                if tmdb_atual:
                    metadados[tmdb_atual] = (titulo, ano)
                continue
            if not tmdb_atual:
                continue
            campos = linha.split("\t")
            if len(campos) < 4 or not (campos[0].isdigit() and campos[1].isdigit()):
                continue
            alvo = (int(campos[0]), int(campos[1]), campos[2] or "dub")
            for u in campos[3].split(","):
                u = u.strip()
                if u and u not in existentes[tmdb_atual][alvo]:
                    existentes[tmdb_atual][alvo].append(u)

        # Percorre o catálogo completo da categoria (inclui títulos que o EmbedPlayer não tinha)
        linhas_saida: list[str] = []
        titulos_com_fonte = 0
        for linha in cat_path.read_text(encoding="utf-8").splitlines():
            campos = linha.split("\t")
            if len(campos) < 3 or not campos[0].isdigit():
                continue
            tmdb, nome, ano = campos[0].strip(), campos[1].strip(), campos[2].strip()
            if tmdb in metadados:
                nome, ano = metadados[tmdb]

            combinados: dict[tuple[int, int, str], list[str]] = defaultdict(list)
            for alvo, urls in eps_por_tmdb.get(tmdb, {}).items():
                for u in urls:
                    curta = encurtar_serie(u)
                    if curta not in combinados[alvo]:
                        combinados[alvo].append(curta)
            for alvo, urls in existentes.get(tmdb, {}).items():
                for u in urls:
                    if u not in combinados[alvo]:
                        combinados[alvo].append(u)

            if not combinados:
                continue
            titulos_com_fonte += 1
            linhas_saida.append(f"@{nome}\t{ano}\t{tmdb}")
            for (temp, ep, versao) in sorted(combinados):
                linhas_saida.append(f"{temp}\t{ep}\t{versao}\t{','.join(combinados[(temp, ep, versao)])}")

        if linhas_saida:
            links_path.write_text("\n".join(linhas_saida) + "\n", encoding="utf-8")
            print(f"nixplay -> {categoria}: {titulos_com_fonte} títulos atualizados")


def main() -> None:
    texto = baixar()
    por_id = fichas()
    anos = anos_das_series()

    filmes: dict[str, dict[str, list[str]]] = defaultdict(lambda: defaultdict(list))
    series: dict[tuple[str, str], dict[tuple[int, int, str], list[str]]] = defaultdict(lambda: defaultdict(list))
    eps_por_tmdb: dict[str, dict[tuple[int, int, str], list[str]]] = defaultdict(lambda: defaultdict(list))
    novos_f: set[str] = set()
    novas_s: set[str] = set()
    nome_novo: dict[tuple[str, str], str] = {}
    tmdb_por_titulo: dict[tuple[str, str], str] = {}

    nome = ""
    for linha in texto.splitlines():
        linha = linha.strip()
        if linha.startswith("#EXTINF"):
            nome = nome_do_extinf(linha)
            continue
        if not linha.startswith("http") or not nome:
            continue
        url, versao = limpar(linha)
        partes = url.split("?", 1)[0].split("/")
        if "/movie/" in url:
            tmdb = partes[-1].split(".")[0]
            titulo = por_id["f"].get(tmdb)
            if not titulo:
                novos_f.add(tmdb)
                titulo = nome_novo.setdefault(("f", tmdb), VERSAO_NOME.sub("", nome).strip())
            tmdb_por_titulo[("f", titulo)] = tmdb
            if url not in filmes[titulo][versao]:
                filmes[titulo][versao].append(url)
        elif "/series/" in url:
            tmdb, temporada, episodio = partes[-3], partes[-2], partes[-1].split(".")[0]
            if not (temporada.isdigit() and episodio.isdigit()):
                continue
            alvo = (int(temporada), int(episodio), versao)
            if url not in eps_por_tmdb[tmdb][alvo]:
                eps_por_tmdb[tmdb][alvo].append(url)
            titulo = por_id["s"].get(tmdb)
            if titulo:
                destino = (titulo, anos.get(titulo, ""))
            else:
                novas_s.add(tmdb)
                # Um nome por id: o do primeiro episódio que aparecer.
                titulo = nome_novo.setdefault(
                    ("s", tmdb),
                    VERSAO_NOME.sub("", EPISODIO_NOME.sub("", nome).strip()).strip(),
                )
                destino = (titulo, "")
            tmdb_por_titulo[("s", destino[0])] = tmdb
            if url not in series[destino][alvo]:
                series[destino][alvo].append(url)
        nome = ""

    SAIDA.mkdir(parents=True, exist_ok=True)
    with (SAIDA / "links-filmes.txt").open("w", encoding="utf-8") as f:
        for titulo in sorted(filmes):
            campos = [f"{v}={','.join(u)}" for v, u in sorted(filmes[titulo].items())]
            tmdb = tmdb_por_titulo.get(("f", titulo), "")
            if tmdb:
                campos.append(f"tmdb={tmdb}")
            f.write("\t".join([titulo, *campos]) + "\n")
    with (SAIDA / "links-series.txt").open("w", encoding="utf-8") as f:
        for (titulo, ano) in sorted(series):
            tmdb = tmdb_por_titulo.get(("s", titulo), "")
            cabecalho = f"@{titulo}\t{ano}" + (f"\t{tmdb}" if tmdb else "")
            f.write(cabecalho + "\n")
            for (t, e, v), urls in sorted(series[(titulo, ano)].items()):
                f.write(f"{t}\t{e}\t{v}\t{','.join(urls)}\n")

    atualizar_colecoes_redeflix(eps_por_tmdb)

    episodios = sum(len(eps) for eps in series.values())
    print(f"nixplay: {len(filmes)} filmes ({len(novos_f)} ids novos no acervo) | "
          f"{len(series)} séries ({len(novas_s)} ids novos), {episodios} episódios")


if __name__ == "__main__":
    main()
