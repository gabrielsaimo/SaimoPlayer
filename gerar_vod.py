#!/usr/bin/env python3
"""Transforma a lista de 30 MB num catálogo de filmes e séries que cabe numa TV.

A lista de origem tem 298 mil linhas e nenhum atributo: nem capa, nem gênero,
nem grupo. Só nome e URL. Tudo o que dá para saber vem do nome, então é dele que
sai a separação:

    "Nome S01E02"  -> episódio de série
    "Nome [L]"     -> versão legendada do mesmo título
    resto          -> filme

Os canais de TV da lista (.ts) são ignorados: esta parte é só filme e série.

O resultado sai fatiado por letra inicial, e as séries ainda em pedaços dentro
da letra. Um TV Box não abre um arquivo de 20 MB, mas abre o pedaço que a pessoa
escolheu — e é assim que a tela funciona também, então o download acompanha a
navegação em vez de contrariá-la.

As URLs também encolhem: todas partem do mesmo endereço, então o prefixo mora
uma vez no índice e cada item guarda só o número. São 70 bytes que viram 7.
"""
import re
import unicodedata
from collections import defaultdict
from pathlib import Path
from urllib.request import urlopen

ORIGEM = "https://raw.githubusercontent.com/Ramys/Iptv-Brasil-2026/refs/heads/master/CanaisBR02.m3u8"
ROOT = Path(__file__).resolve().parent
SAIDA = ROOT / "vod"

EPISODIO = re.compile(r"^(.*?)\s*S(\d{1,2})E(\d{1,3})\s*$", re.I)
BASE_FILME = "http://tjtor8411.com:80/movie/Osiel123/Felicidade321/"
BASE_SERIE = "http://tjtor8411.com:80/series/Osiel123/Felicidade321/"
# Séries por pedaço. Abrir uma série baixa um pedaço, não a letra inteira.
POR_PEDACO = 120
MARCADOR = re.compile(r"\s*\[([^\]]+)\]")
ANO = re.compile(r"\s*\((19|20)\d{2}\)\s*$")


def letra(titulo):
    """Gaveta do título: A–Z, ou # para o que não começa por letra."""
    texto = unicodedata.normalize("NFKD", titulo).encode("ascii", "ignore").decode()
    inicial = texto.strip()[:1].upper()
    return inicial if "A" <= inicial <= "Z" else "#"


def limpar(nome):
    """Devolve (título, legendado). O marcador [L] é versão, não título."""
    legendado = False
    marcadores = MARCADOR.findall(nome)
    if any(m.strip().upper() == "L" for m in marcadores):
        legendado = True
    titulo = MARCADOR.sub("", nome).strip()
    return re.sub(r"\s{2,}", " ", titulo), legendado


def encurtar(url, base):
    """Só o número, quando a URL parte do endereço conhecido."""
    if url.startswith(base):
        resto = url[len(base):]
        return resto[:-4] if resto.endswith(".mp4") else resto
    return url


def baixar():
    print("baixando a lista de origem…")
    with urlopen(ORIGEM, timeout=120) as resposta:
        return resposta.read().decode("utf-8", "replace")


def main():
    texto = baixar()
    linhas = texto.split("\n")
    print(f"{len(linhas)} linhas")

    filmes = defaultdict(lambda: defaultdict(dict))  # letra -> título -> {versão: url}
    series = defaultdict(lambda: defaultdict(dict))  # letra -> série -> (t,e,ver) -> url
    anos = {}
    ignorados = 0

    indice = 0
    while indice < len(linhas) - 1:
        linha = linhas[indice]
        if not linha.startswith("#EXTINF"):
            indice += 1
            continue
        nome = linha.split(",", 1)[-1].strip()
        url = linhas[indice + 1].strip()
        indice += 2
        if not url or url.startswith("#"):
            continue
        # Canal de TV ao vivo: não é o assunto desta lista.
        if url.endswith(".ts"):
            ignorados += 1
            continue

        titulo, legendado = limpar(nome)
        versao = "leg" if legendado else "dub"
        episodio = EPISODIO.match(titulo)
        if episodio:
            serie = episodio.group(1).strip()
            temporada, numero = int(episodio.group(2)), int(episodio.group(3))
            achado = ANO.search(serie)
            if achado:
                anos[ANO.sub("", serie).strip()] = achado.group(0).strip(" ()")
                serie = ANO.sub("", serie).strip()
            if serie:
                series[letra(serie)][serie][(temporada, numero, versao)] = url
        elif titulo:
            filmes[letra(titulo)][titulo][versao] = url

    SAIDA.mkdir(exist_ok=True)
    for antigo in SAIDA.glob("*.txt"):
        antigo.unlink()

    total_filmes = sum(len(v) for v in filmes.values())
    for chave, titulos in sorted(filmes.items()):
        linhas_saida = []
        for titulo in sorted(titulos):
            versoes = titulos[titulo]
            partes = [f"{v}={encurtar(versoes[v], BASE_FILME)}"
                      for v in ("dub", "leg") if v in versoes]
            linhas_saida.append(f"{titulo}\t" + "\t".join(partes))
        (SAIDA / f"filmes-{chave}.txt").write_text("\n".join(linhas_saida) + "\n",
                                                   encoding="utf-8")

    total_series = sum(len(v) for v in series.values())
    total_eps = 0
    for chave, titulos in sorted(series.items()):
        indice_serie = []
        pedaco, linhas_pedaco, dentro = 0, [], 0
        for titulo in sorted(titulos):
            if dentro >= POR_PEDACO:
                (SAIDA / f"series-{chave}-{pedaco}.txt").write_text(
                    "\n".join(linhas_pedaco) + "\n", encoding="utf-8")
                pedaco, linhas_pedaco, dentro = pedaco + 1, [], 0
            episodios = titulos[titulo]
            indice_serie.append(f"{titulo}\t{anos.get(titulo, '')}\t{pedaco}\t{len(episodios)}")
            linhas_pedaco.append(f"@{titulo}")
            for (temporada, numero, versao) in sorted(episodios):
                total_eps += 1
                curto = encurtar(episodios[(temporada, numero, versao)], BASE_SERIE)
                linhas_pedaco.append(f"{temporada}\t{numero}\t{versao}\t{curto}")
            dentro += 1
        if linhas_pedaco:
            (SAIDA / f"series-{chave}-{pedaco}.txt").write_text(
                "\n".join(linhas_pedaco) + "\n", encoding="utf-8")
        (SAIDA / f"series-{chave}.txt").write_text("\n".join(indice_serie) + "\n",
                                                   encoding="utf-8")

    # Índice pequeno, o único arquivo que a tela inicial precisa baixar.
    indice_linhas = [
        f"base-filme: {BASE_FILME}",
        f"base-serie: {BASE_SERIE}",
    ]
    for chave in sorted(set(filmes) | set(series)):
        indice_linhas.append(f"{chave}\t{len(filmes.get(chave, {}))}\t{len(series.get(chave, {}))}")
    (SAIDA / "indice.txt").write_text("\n".join(indice_linhas) + "\n", encoding="utf-8")

    tamanho = sum(f.stat().st_size for f in SAIDA.glob("*.txt"))
    print(f"filmes: {total_filmes} | séries: {total_series} | episódios: {total_eps}")
    print(f"canais de TV ignorados: {ignorados}")
    print(f"{len(list(SAIDA.glob('*.txt')))} arquivos, {tamanho / 1e6:.1f} MB")
    maiores = sorted(SAIDA.glob("*.txt"), key=lambda f: -f.stat().st_size)[:5]
    for f in maiores:
        print(f"   {f.name}: {f.stat().st_size / 1e6:.2f} MB")


if __name__ == "__main__":
    main()
