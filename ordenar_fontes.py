#!/usr/bin/env python3
"""Põe as fontes dos servidores preferidos na frente de cada canal.

A primeira fonte é a que o app abre; as outras são reserva, tentadas na
ordem quando ela falha. O nexustvplay é o servidor mais estável hoje, então
em todo canal que tem fonte dele ela vai para o começo da fila — menos nos
canais 24 horas, onde o vivlar.me vem antes.

Cada fonte anda com os atributos dela (qualidade, nome, referer, agente,
chave). Nada é apagado nem duplicado: só a ordem muda. Rodar de novo é seguro.

    python3 ordenar_fontes.py
"""
from pathlib import Path

CATALOGO = Path(__file__).parent / "catalogo.txt"

# Em ordem de preferência: o primeiro que aparecer no endereço vai à frente.
PREFERIDOS = ("nexustvplay.bbroot.com",)
# Categorias com preferência própria. Nos canais 24 horas o vivlar.me vem
# primeiro: é onde estão as temporadas inteiras, em HLS estável.
PREFERIDOS_POR_CATEGORIA = {
    "24 Horas": ("vivlar.me", "nexustvplay.bbroot.com"),
}

ATRIBUTOS = ("qualidade:", "referer:", "agente:", "chave:", "nome:")


def peso(fonte: list[str], preferidos: tuple[str, ...]) -> int:
    for i, host in enumerate(preferidos):
        if host in fonte[0]:
            return i
    return len(preferidos)


def ordenar(bloco: list[str]) -> list[str]:
    cabeca, fontes, resto = [], [], []
    k = 0
    while k < len(bloco) and not bloco[k].startswith("fonte:"):
        cabeca.append(bloco[k])
        k += 1
    while k < len(bloco):
        if bloco[k].startswith("fonte:"):
            fonte = [bloco[k]]
            k += 1
            while k < len(bloco) and bloco[k].startswith(ATRIBUTOS):
                fonte.append(bloco[k])
                k += 1
            fontes.append(fonte)
        else:
            resto.append(bloco[k])
            k += 1
    categoria = next((l.split(":", 1)[1].strip() for l in cabeca if l.startswith("categoria:")), "")
    preferidos = PREFERIDOS_POR_CATEGORIA.get(categoria, PREFERIDOS)
    # sort é estável: entre as não preferidas, a ordem de antes fica.
    fontes.sort(key=lambda fonte: peso(fonte, preferidos))
    return cabeca + [linha for fonte in fontes for linha in fonte] + resto


def main() -> None:
    linhas = CATALOGO.read_text(encoding="utf-8").split("\n")
    saida: list[str] = []
    i = 0
    while i < len(linhas):
        if not linhas[i].startswith("canal:"):
            saida.append(linhas[i])
            i += 1
            continue
        j = i + 1
        while j < len(linhas) and not linhas[j].startswith("canal:"):
            j += 1
        saida += ordenar(linhas[i:j])
        i = j
    novo = "\n".join(saida)
    if novo != "\n".join(linhas):
        CATALOGO.write_text(novo, encoding="utf-8")
        print("ordem das fontes atualizada")
    else:
        print("já estava em ordem")


if __name__ == "__main__":
    main()
