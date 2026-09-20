#!/usr/bin/env python3
"""Monta as fileiras da tela inicial num arquivo só.

A tela inicial dos aplicativos mostra fileiras de capas — o que está em alta,
o que acabou de entrar, animes, doramas. Nada disso dá para descobrir no
aparelho: o catálogo tem trinta e quatro mil filmes e nenhuma data de entrada,
e um TV Box não vai varrer isso a cada abertura, muito menos perguntar a capa
de cada título ao TMDB.

Então a conta é feita aqui, uma vez, e o resultado publicado num arquivo de
poucos quilobytes. O aparelho baixa ele e desenha — sem varredura, sem
consulta, sem espera.

O "em alta" vem do próprio TMDB, cruzado com o que existe no acervo: ninguém
quer uma fileira de filmes que não dá para assistir. O caminho do pôster vai
gravado junto, então a capa aparece sem nenhuma consulta no aparelho.

    ./gerar_destaques.py

Lê o que já está publicado em vod/ e escreve vod/destaques.txt.
"""
import json
import re
import time
import unicodedata
from collections import OrderedDict
from datetime import date
from pathlib import Path
from urllib.parse import quote
from urllib.request import urlopen

RAIZ = Path(__file__).resolve().parent
VOD = RAIZ / "vod"
SAIDA = VOD / "destaques.txt"

CHAVE_TMDB = "15d2ea6d0dc1d476efbca3eba2b9bbfb"
TMDB = "https://api.themoviedb.org/3"
CAPA_BASE = "https://image.tmdb.org/t/p/w342"

# Quantos itens por fileira. Vinte enche a tela e não pesa: cada capa é uma
# imagem de 342 pixels de largura, e o aparelho só baixa as que estão à vista.
POR_FILA = 20
ANO_ATUAL = date.today().year


def sem_acento(texto):
    return unicodedata.normalize("NFKD", texto).encode("ascii", "ignore").decode()


def chave(titulo):
    """Nome comparável entre o TMDB e o acervo."""
    base = sem_acento(titulo).lower()
    return re.sub(r"[^a-z0-9]+", " ", base).strip()


def pegar(url, tentativas=3):
    for tentativa in range(tentativas):
        try:
            with urlopen(url, timeout=25) as resposta:
                return json.loads(resposta.read().decode("utf-8"))
        except Exception:
            if tentativa == tentativas - 1:
                return None
            time.sleep(1.5)
    return None


def acervo():
    """Tudo o que existe, por nome comparável: (titulo, tipo, letra, ano)."""
    linhas = (VOD / "busca.txt").read_text(encoding="utf-8").splitlines()
    por_chave = {}
    for linha in linhas:
        campos = linha.split("\t")
        if len(campos) < 3:
            continue
        titulo, tipo, letra = campos[0], campos[1], campos[2]
        ano = campos[3] if len(campos) > 3 else ""
        # O ano do filme vem dentro do nome; o da série, num campo à parte.
        achado = re.search(r"\((\d{4})\)\s*$", titulo)
        if achado and not ano:
            ano = achado.group(1)
        nu = re.sub(r"\s*\(\d{4}\)\s*$", "", titulo).strip()
        item = (titulo, tipo, letra, ano)
        # Sem ano é a entrada mais genérica e casa com qualquer busca; com ano
        # é a exata. Guardando as duas chaves, o cruzamento acha dos dois jeitos.
        por_chave.setdefault(chave(nu), item)
        if ano:
            por_chave.setdefault(f"{chave(nu)}|{ano}", item)
    return por_chave


def colecao(tipo):
    """Animes e doramas: título, ano e id do TMDB, já publicados."""
    caminho = VOD / "redeflix" / f"links-{tipo}.txt"
    if not caminho.exists():
        return []
    out = []
    for linha in caminho.read_text(encoding="utf-8").splitlines():
        if not linha.startswith("@"):
            continue
        campos = linha[1:].split("\t")
        titulo = campos[0]
        ano = campos[1] if len(campos) > 1 else ""
        tmdb = campos[2] if len(campos) > 2 else ""
        out.append((titulo, ano, tmdb))
    return out


def tendencia(endpoint, paginas=2):
    """O que está em alta no TMDB agora, em português."""
    itens = []
    for pagina in range(1, paginas + 1):
        dados = pegar(
            f"{TMDB}/trending/{endpoint}/week?api_key={CHAVE_TMDB}"
            f"&language=pt-BR&page={pagina}")
        if not dados:
            break
        itens += dados.get("results", [])
    return itens


def lancamentos(endpoint, paginas=3):
    """O que estreou neste ano, do mais popular para o menos."""
    itens = []
    campo = "primary_release_year" if endpoint == "movie" else "first_air_date_year"
    for pagina in range(1, paginas + 1):
        dados = pegar(
            f"{TMDB}/discover/{endpoint}?api_key={CHAVE_TMDB}&language=pt-BR"
            f"&sort_by=popularity.desc&{campo}={ANO_ATUAL}&page={pagina}")
        if not dados:
            break
        itens += dados.get("results", [])
    return itens


def cruzar(itens_tmdb, catalogo, tipo_desejado):
    """Fica só com o que o acervo tem, na ordem em que o TMDB trouxe."""
    fila = OrderedDict()
    for item in itens_tmdb:
        nome = item.get("title") or item.get("name") or ""
        original = item.get("original_title") or item.get("original_name") or ""
        data = item.get("release_date") or item.get("first_air_date") or ""
        ano = data[:4]
        poster = item.get("poster_path") or ""
        if not nome:
            continue
        candidatas = []
        for base in filter(None, {nome, original}):
            if ano:
                candidatas.append(f"{chave(base)}|{ano}")
            candidatas.append(chave(base))
        for c in candidatas:
            achado = catalogo.get(c)
            if achado and achado[1] == tipo_desejado:
                fila.setdefault(achado[0], (achado, poster))
                break
        if len(fila) >= POR_FILA:
            break
    return list(fila.values())


def capa_da_colecao(tmdb_id, endpoint="tv"):
    if not tmdb_id:
        return ""
    dados = pegar(f"{TMDB}/{endpoint}/{tmdb_id}?api_key={CHAVE_TMDB}&language=pt-BR")
    return (dados or {}).get("poster_path") or ""


def main():
    catalogo = acervo()
    print(f"acervo: {len(catalogo)} chaves")

    filas = []

    em_alta_filmes = cruzar(tendencia("movie"), catalogo, "f")
    filas.append(("Em alta", "f", em_alta_filmes))

    em_alta_series = cruzar(tendencia("tv"), catalogo, "s")
    filas.append(("Séries em alta", "s", em_alta_series))

    novos_filmes = cruzar(lancamentos("movie"), catalogo, "f")
    filas.append((f"Lançamentos de {ANO_ATUAL}", "f", novos_filmes))

    novas_series = cruzar(lancamentos("tv"), catalogo, "s")
    filas.append((f"Séries novas de {ANO_ATUAL}", "s", novas_series))

    for tipo, titulo, marca in (("animes", "Animes", "a"), ("doramas", "Doramas", "d")):
        lista = colecao(tipo)
        # Do mais novo para o mais velho: é o que alguém espera de "novidades".
        lista.sort(key=lambda item: item[1] or "0", reverse=True)
        escolhidos = []
        for nome, ano, tmdb_id in lista[:POR_FILA]:
            escolhidos.append((((nome, marca, "", ano)), capa_da_colecao(tmdb_id)))
        filas.append((titulo, marca, escolhidos))

    linhas = [
        "# Fileiras da tela inicial. Geradas por gerar_destaques.py — não editar à mão.",
        f"capa: {CAPA_BASE}",
    ]
    total = 0
    for titulo, _, itens in filas:
        if not itens:
            continue
        linhas.append(f"fila\t{titulo}")
        for (nome, tipo, letra, ano), poster in itens:
            linhas.append(f"{tipo}\t{nome}\t{letra}\t{ano}\t{poster}")
            total += 1
        print(f"  {titulo}: {len(itens)}")

    SAIDA.write_text("\n".join(linhas) + "\n", encoding="utf-8")
    print(f"{SAIDA.name}: {len(filas)} fileiras, {total} itens, "
          f"{SAIDA.stat().st_size / 1024:.1f} KB")


if __name__ == "__main__":
    main()
