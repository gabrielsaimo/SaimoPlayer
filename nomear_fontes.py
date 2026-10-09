#!/usr/bin/env python3
"""Dá nome às fontes do catálogo a partir das listas de origem (M3U).

Nos canais 24 horas cada fonte é uma temporada: nas listas importadas o
mesmo canal aparece como "[24H] Os Simpsons [S01]", "[24H] Os Simpsons [S02]"
e assim por diante, mas o catálogo guardava só o endereço — e os apps
mostravam "Fonte 1", "Fonte 2" sem dizer qual temporada era qual.

Este script procura o endereço de cada fonte nas listas M3U da pasta, tira
do nome o que diferencia uma fonte da outra e grava logo abaixo do `fonte:`:

    fonte: http://servidor/135601.ts
    nome: Temporada 1

  [S01]   -> Temporada 1
  [L]     -> Legendado
  (1993)  -> Versão de 1993

Rodar de novo é seguro: a linha `nome:` de cada fonte é refeita, não somada.
Fonte sem nome reconhecível fica sem a linha e o app mostra "Fonte N".

    python3 nomear_fontes.py            # grava no catalogo.txt
    python3 nomear_fontes.py --mostrar  # só lista o que faria
"""
import re
import sys
from pathlib import Path

PASTA = Path(__file__).parent
CATALOGO = PASTA / "catalogo.txt"

EXTINF = re.compile(r"^#EXTINF[^,]*,(.*)$")
TEMPORADA = re.compile(r"\[\s*S(\d{1,2})\s*\]", re.I)
LEGENDADO = re.compile(r"\[\s*L(?:eg(?:endado)?)?\s*\]", re.I)
ANO = re.compile(r"\(\s*((?:19|20)\d{2})\s*\)")


def nomes_das_listas() -> dict[str, str]:
    """Endereço -> nome do canal como está na lista M3U."""
    nomes: dict[str, str] = {}
    for lista in sorted(PASTA.glob("*.m3u")) + sorted(PASTA.glob("*.m3u8")):
        anterior = None
        for linha in lista.read_text(encoding="utf-8", errors="replace").splitlines():
            linha = linha.strip()
            achado = EXTINF.match(linha)
            if achado:
                anterior = achado.group(1).strip()
            elif linha and not linha.startswith("#") and anterior:
                nomes.setdefault(linha, anterior)
                anterior = None
    return nomes


def rotulo(nome: str) -> str:
    """O que diferencia esta fonte das outras do mesmo canal."""
    partes = []
    temporada = TEMPORADA.search(nome)
    if temporada:
        partes.append(f"Temporada {int(temporada.group(1))}")
    ano = ANO.search(nome)
    if ano:
        partes.append(f"Versão de {ano.group(1)}")
    if LEGENDADO.search(nome):
        partes.append("Legendado")
    return " · ".join(partes)


def main() -> None:
    mostrar = "--mostrar" in sys.argv
    nomes = nomes_das_listas()
    linhas = CATALOGO.read_text(encoding="utf-8").splitlines()
    saida: list[str] = []
    nomeadas = 0
    canal = ""
    for linha in linhas:
        # A linha nome: antiga sai; a nova (se houver) entra logo abaixo do fonte:.
        if linha.startswith("nome:"):
            continue
        saida.append(linha)
        if linha.startswith("canal:"):
            canal = linha.split(":", 1)[1].strip()
        elif linha.startswith("fonte:"):
            url = linha.split(":", 1)[1].strip()
            texto = rotulo(nomes.get(url, ""))
            if texto:
                saida.append(f"nome: {texto}")
                nomeadas += 1
                if mostrar:
                    print(f"{canal}: {texto}")
    if not mostrar:
        CATALOGO.write_text("\n".join(saida) + "\n", encoding="utf-8")
    print(f"{nomeadas} fontes com nome ({len(nomes)} endereços nas listas)")


if __name__ == "__main__":
    main()
