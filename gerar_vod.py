#!/usr/bin/env python3
"""Junta as listas de origem num catálogo de filmes e séries que cabe numa TV.

As listas somam 60 MB e 590 mil linhas, e não trazem atributo nenhum: nem capa,
nem gênero, nem grupo. Só nome e URL. Tudo o que dá para saber vem do nome:

    "Nome S01E02"  -> episódio de série
    "Nome [L]"     -> versão legendada do mesmo título
    "[Adulto]"     -> vai para a parte reservada, não para a lista comum
    resto          -> filme

O mesmo filme costuma existir nas duas listas. Fontes do mesmo título, ano e
idioma ficam juntas, mas refilmagens nunca podem ser confundidas: "Mestres do
Universo (1987)" e "Mestres do Universo (2026)" são dois itens. Quando há mais
de uma fonte, os apps deixam a pessoa escolher qual quer abrir.

Os canais de TV das listas são ignorados: esta parte é só filme e série.

O resultado sai fatiado por letra, e as séries ainda em pedaços dentro da letra,
porque nenhum TV Box abre um arquivo de 20 MB. As URLs encolhem junto: o que se
repete é o começo, então cada base mora uma vez no índice e o item guarda só o
número.
"""
import re
import unicodedata
from collections import defaultdict
from pathlib import Path
from urllib.request import urlopen

ORIGENS = [
    "https://raw.githubusercontent.com/Ramys/Iptv-Brasil-2026/refs/heads/master/CanaisBR01.m3u8",
    "https://raw.githubusercontent.com/Ramys/Iptv-Brasil-2026/refs/heads/master/Filmes-Series.m3u8",
]
ROOT = Path(__file__).resolve().parent
SAIDA = ROOT / "vod"

# A segunda lista escreve "S01 E01", com espaço antes do E; a primeira escreve
# "S01E01", colado. O \s* aceita as duas sem precisar de um regex por origem.
EPISODIO = re.compile(r"^(.*?)\s*S(\d{1,2})\s*E(\d{1,3})\s*$", re.I)
MARCADOR = re.compile(r"\s*[\[\(]([^\]\)]{1,24})[\]\)]")
ANO_FIM = re.compile(r"\s*(?:\(((?:19|20)\d{2})\)|((?:19|20)\d{2}))\s*$")
ADULTO = {"adulto", "xxx", "+18", "18+"}
QUALIDADE = re.compile(r"\s*\b(4k|uhd|fhd|hd|sd|h265|hevc|hdr|dv)\b\s*²?", re.I)
POR_PEDACO = 120


def letra(titulo):
    texto = unicodedata.normalize("NFKD", titulo).encode("ascii", "ignore").decode()
    inicial = texto.strip()[:1].upper()
    return inicial if "A" <= inicial <= "Z" else "#"


def limpar(nome):
    """Devolve (título, legendado, adulto). Marcador é versão, não título."""
    ano_final = ANO_FIM.search(nome)
    ano = (ano_final.group(1) or ano_final.group(2)) if ano_final else ""
    marcadores = [m.strip().lower() for m in MARCADOR.findall(nome)]
    legendado = any(m == "l" for m in marcadores)
    adulto = any(m in ADULTO for m in marcadores)
    titulo = MARCADOR.sub(" ", nome)
    titulo = titulo.replace("²", " ")
    titulo = re.sub(r"\s{2,}", " ", titulo).strip()
    # O parser de marcadores também encontra "(1987)". Recolocar o ano evita
    # que duas refilmagens voltem a cair na mesma chave depois da limpeza.
    if ano and not ANO_FIM.search(titulo):
        titulo = f"{titulo} ({ano})"
    return titulo, legendado, adulto


def separar_ano(titulo):
    """Devolve título sem ano e o ano final, entre parênteses ou solto."""
    achado = ANO_FIM.search(titulo)
    if not achado:
        return titulo, ""
    sem_ano = ANO_FIM.sub("", titulo).strip()
    # Ano solto vem antecedido de um separador — "Nome - 2014" — que a busca
    # do ano não apaga por não fazer parte dele. Sobrando, o mesmo filme das
    # duas listas vira "Nome" numa e "Nome -" na outra: chaves diferentes,
    # duas entradas em vez de duas fontes do mesmo título.
    sem_ano = re.sub(r"[\s\-–—:|]+$", "", sem_ano).strip()
    # "2012" também é título de filme. Nunca o transforme num nome vazio.
    if not sem_ano:
        return titulo, ""
    return sem_ano, achado.group(1) or achado.group(2)


def chave(titulo, ano=""):
    """Nome comparável entre listas, preservando o ano que separa refilmagens."""
    texto = QUALIDADE.sub(" ", titulo)
    texto = unicodedata.normalize("NFKD", texto).encode("ascii", "ignore").decode().lower()
    base = re.sub(r"[^a-z0-9]+", " ", texto).strip()
    return f"{base}|{ano}" if ano else base


class Bases:
    """Começos de URL que se repetem, para o item guardar só o número."""

    def __init__(self):
        self.lista = []

    def encurtar(self, url):
        for indice, base in enumerate(self.lista):
            if url.startswith(base):
                resto = url[len(base):]
                resto = resto[:-4] if resto.endswith(".mp4") else resto
                return f"{indice}:{resto}"
        corte = url.rfind("/") + 1
        base = url[:corte]
        if corte > 10 and len(self.lista) < 12:
            self.lista.append(base)
            return self.encurtar(url)
        return url


def baixar(url):
    print(f"baixando {url.rsplit('/', 1)[-1]}…")
    with urlopen(url, timeout=180) as resposta:
        return resposta.read().decode("utf-8", "replace")


def main():
    bases = Bases()
    filmes = defaultdict(lambda: {"titulo": "", "versoes": defaultdict(list)})
    series = defaultdict(lambda: {"titulo": "", "ano": "", "eps": defaultdict(list)})
    reservado = defaultdict(lambda: {"titulo": "", "versoes": defaultdict(list)})
    ignorados = 0

    for origem in ORIGENS:
        linhas = baixar(origem).split("\n")
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
            # Canal de TV ao vivo: não é o assunto desta lista. Na primeira ele
            # termina em .ts; na segunda vem sem extensão nenhuma.
            if url.endswith(".ts") or "." not in url.rsplit("/", 1)[-1]:
                ignorados += 1
                continue

            titulo, legendado, adulto = limpar(nome)
            if not titulo:
                continue
            versao = "leg" if legendado else "dub"
            curta = bases.encurtar(url)

            episodio = EPISODIO.match(titulo)
            if episodio:
                if adulto:
                    continue
                serie = episodio.group(1).strip()
                serie, ano = separar_ano(serie)
                if not serie:
                    continue
                registro = series[chave(serie, ano)]
                registro["titulo"] = registro["titulo"] or serie
                registro["ano"] = registro["ano"] or ano
                alvo = (int(episodio.group(2)), int(episodio.group(3)), versao)
                if curta not in registro["eps"][alvo]:
                    registro["eps"][alvo].append(curta)
            else:
                destino = reservado if adulto else filmes
                titulo, ano = separar_ano(titulo)
                exibido = f"{titulo} ({ano})" if ano else titulo
                registro = destino[chave(titulo, ano)]
                registro["titulo"] = registro["titulo"] or exibido
                if curta not in registro["versoes"][versao]:
                    registro["versoes"][versao].append(curta)

    SAIDA.mkdir(exist_ok=True)
    for antigo in SAIDA.glob("*.txt"):
        antigo.unlink()

    def gravar_filmes(colecao, prefixo):
        gavetas = defaultdict(list)
        for registro in colecao.values():
            gavetas[letra(registro["titulo"])].append(registro)
        for chave_letra, registros in sorted(gavetas.items()):
            linhas_saida = []
            for registro in sorted(registros, key=lambda r: r["titulo"]):
                partes = [f"{v}=" + ",".join(registro["versoes"][v])
                          for v in ("dub", "leg") if registro["versoes"].get(v)]
                linhas_saida.append(registro["titulo"] + "\t" + "\t".join(partes))
            nome = f"{prefixo}-{chave_letra}.txt"
            (SAIDA / nome).write_text("\n".join(linhas_saida) + "\n", encoding="utf-8")
        return {k: len(v) for k, v in gavetas.items()}

    contagem_filmes = gravar_filmes(filmes, "filmes")
    contagem_reservado = gravar_filmes(reservado, "reservado")

    gavetas_serie = defaultdict(list)
    for registro in series.values():
        gavetas_serie[letra(registro["titulo"])].append(registro)

    total_eps = 0
    contagem_series = {}
    for chave_letra, registros in sorted(gavetas_serie.items()):
        registros.sort(key=lambda r: r["titulo"])
        contagem_series[chave_letra] = len(registros)
        indice_linhas, pedaco, linhas_pedaco, dentro = [], 0, [], 0
        for registro in registros:
            if dentro >= POR_PEDACO:
                (SAIDA / f"series-{chave_letra}-{pedaco}.txt").write_text(
                    "\n".join(linhas_pedaco) + "\n", encoding="utf-8")
                pedaco, linhas_pedaco, dentro = pedaco + 1, [], 0
            eps = registro["eps"]
            indice_linhas.append(
                f'{registro["titulo"]}\t{registro["ano"]}\t{pedaco}\t{len(eps)}')
            # O ano faz parte da identidade. Duas séries homônimas podem cair
            # no mesmo pedaço e o app precisa abrir os episódios da série certa.
            identidade = "@" + registro["titulo"]
            if registro["ano"]:
                identidade += "\t" + registro["ano"]
            linhas_pedaco.append(identidade)
            for (temporada, numero, versao) in sorted(eps):
                total_eps += 1
                linhas_pedaco.append(
                    f"{temporada}\t{numero}\t{versao}\t" + ",".join(eps[(temporada, numero, versao)]))
            dentro += 1
        if linhas_pedaco:
            (SAIDA / f"series-{chave_letra}-{pedaco}.txt").write_text(
                "\n".join(linhas_pedaco) + "\n", encoding="utf-8")
        (SAIDA / f"series-{chave_letra}.txt").write_text(
            "\n".join(indice_linhas) + "\n", encoding="utf-8")

    # Índice de busca: só nome, tipo e letra. É o que permite procurar em todo
    # o acervo sem baixar o acervo — trinta mil linhas curtas, uma vez.
    busca = []
    for registro in sorted(filmes.values(), key=lambda r: r["titulo"]):
        busca.append(f'{registro["titulo"]}\tf\t{letra(registro["titulo"])}')
    for registro in sorted(series.values(), key=lambda r: (r["titulo"], r["ano"])):
        linha_busca = f'{registro["titulo"]}\ts\t{letra(registro["titulo"])}'
        if registro["ano"]:
            linha_busca += "\t" + registro["ano"]
        busca.append(linha_busca)
    (SAIDA / "busca.txt").write_text("\n".join(busca) + "\n", encoding="utf-8")

    indice_linhas = [f"base: {i} {b}" for i, b in enumerate(bases.lista)]
    for chave_letra in sorted(set(contagem_filmes) | set(contagem_series) | set(contagem_reservado)):
        indice_linhas.append(
            f"{chave_letra}\t{contagem_filmes.get(chave_letra, 0)}"
            f"\t{contagem_series.get(chave_letra, 0)}"
            f"\t{contagem_reservado.get(chave_letra, 0)}")
    (SAIDA / "indice.txt").write_text("\n".join(indice_linhas) + "\n", encoding="utf-8")

    tamanho = sum(f.stat().st_size for f in SAIDA.glob("*.txt"))
    fontes_filme = sum(len(v) for r in filmes.values() for v in r["versoes"].values())
    print(f"filmes: {len(filmes)} ({fontes_filme} fontes) | séries: {len(series)} "
          f"| episódios: {total_eps} | reservados: {len(reservado)}")
    print(f"canais de TV ignorados: {ignorados}")
    print(f"{len(list(SAIDA.glob('*.txt')))} arquivos, {tamanho / 1e6:.1f} MB, "
          f"{len(bases.lista)} bases")
    for f in sorted(SAIDA.glob("*.txt"), key=lambda f: -f.stat().st_size)[:3]:
        print(f"   {f.name}: {f.stat().st_size / 1e6:.2f} MB")


if __name__ == "__main__":
    main()
