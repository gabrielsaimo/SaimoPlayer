#!/usr/bin/env python3
"""Registra o que entrou e o que mudou em cada rodada da atualização.

Compara o acervo de agora (vod/busca.txt e vod/series-*.txt, já remontados
pela rodada) com o que foi publicado na rodada anterior (o commit atual do
git) e acrescenta uma rodada em vod/novidades.json:

  - adicionados: filmes e séries que não existiam;
  - atualizados: séries que ganharam episódios.

Cada título leva o pôster da ficha (vod/fichas.txt) para a página de novidades
do site. Rodada sem mudança também é gravada: mostra que a atualização rodou.

    ./gerar_novidades.py

Roda depois do gerar_destaques.py e antes do commit (atualizar_tudo.sh).
"""
import json
import os
import re
import subprocess
from datetime import datetime
from pathlib import Path

RAIZ = Path(__file__).resolve().parent
VOD = RAIZ / "vod"
SAIDA = VOD / "novidades.json"

# Rodadas guardadas (duas por dia: um mês e meio) e quantos títulos cada lista
# leva (o total vai junto, para a página dizer "e mais N").
RODADAS = 90
POR_LISTA = 200


def git_show(caminho):
    """O arquivo como estava no último commit, ou None se não existia."""
    # NOVIDADES_BASE: outra revisão para comparar (testes); o normal é o HEAD.
    revisao = os.environ.get("NOVIDADES_BASE", "HEAD")
    r = subprocess.run(["git", "show", f"{revisao}:{caminho}"], cwd=RAIZ,
                       capture_output=True, text=True, encoding="utf-8")
    return r.stdout if r.returncode == 0 else None


def ler_busca(texto):
    """{(tipo, titulo)} de busca.txt: título, tipo (f/s), letra."""
    itens = set()
    for linha in (texto or "").splitlines():
        campos = linha.split("\t")
        if len(campos) >= 2 and campos[1] in ("f", "s"):
            t_low = campos[0].lower()
            if any(w in t_low for w in ("[xxx]", "[adulto]", "[+18]", "[18+]")):
                continue
            itens.add((campos[1], campos[0]))
    return itens


def ler_series(textos):
    """{titulo: episodios} somando os pedaços series-*.txt."""
    out = {}
    for texto in textos:
        for linha in (texto or "").splitlines():
            campos = linha.split("\t")
            if len(campos) < 4:
                continue
            try:
                out[campos[0]] = out.get(campos[0], 0) + int(campos[3])
            except ValueError:
                continue
    return out


def posteres():
    """{(tipo, titulo): pôster} e a base das imagens, de vod/fichas.txt."""
    base = "https://image.tmdb.org/t/p/w342"
    mapa = {}
    caminho = VOD / "fichas.txt"
    if not caminho.exists():
        return mapa, base
    for linha in caminho.read_text(encoding="utf-8").splitlines():
        if linha.startswith("capa:"):
            base = linha.split(":", 1)[1].strip()
        elif linha and not linha.startswith("#"):
            c = linha.split("\t")
            if len(c) >= 4 and c[0] in ("f", "s"):
                mapa[(c[0], c[1])] = c[3]
    return mapa, base


def ano_de(titulo):
    achado = re.search(r"\((\d{4})\)\s*$", titulo)
    return achado.group(1) if achado else ""


def main():
    agora_busca = ler_busca((VOD / "busca.txt").read_text(encoding="utf-8"))
    antes_busca = ler_busca(git_show("vod/busca.txt"))

    arquivos = sorted(p.name for p in VOD.glob("series-*.txt"))
    agora_series = ler_series((VOD / n).read_text(encoding="utf-8") for n in arquivos)
    antes_series = ler_series(git_show(f"vod/{n}") for n in arquivos)

    capas, base = posteres()

    # Sem o commit anterior (primeira vez) não há o que comparar: a primeira
    # rodada nasce vazia, em vez de listar o acervo inteiro como novidade.
    primeira = not antes_busca
    novos = [] if primeira else sorted(agora_busca - antes_busca, key=lambda x: x[1].lower())
    mais_episodios = [] if primeira else sorted(
        ((t, antes_series[t], n) for t, n in agora_series.items()
         if t in antes_series and n > antes_series[t]
         and ("s", t) not in (agora_busca - antes_busca)),
        key=lambda x: -(x[2] - x[1]))

    def item(tipo, titulo, extra=None):
        d = {"t": titulo, "tp": tipo, "ano": ano_de(titulo), "capa": capas.get((tipo, titulo), "")}
        if extra:
            d.update(extra)
        return d

    rodada = {
        # NOVIDADES_EM: hora da rodada, quando o registro é refeito depois (recuperação).
        "em": os.environ.get("NOVIDADES_EM") or datetime.now().astimezone().isoformat(timespec="minutes"),
        "adicionados": [item(tp, t) for tp, t in novos[:POR_LISTA]],
        "adicionados_total": len(novos),
        "atualizados": [item("s", t, {"de": a, "para": n}) for t, a, n in mais_episodios[:POR_LISTA]],
        "atualizados_total": len(mais_episodios),
    }

    historico = []
    if SAIDA.exists():
        try:
            historico = json.loads(SAIDA.read_text(encoding="utf-8")).get("rodadas", [])
        except (ValueError, OSError):
            historico = []
    historico.insert(0, rodada)
    saida = {"capa": base, "rodadas": historico[:RODADAS]}
    destino = Path(os.environ["NOVIDADES_SAIDA"]) if os.environ.get("NOVIDADES_SAIDA") else SAIDA
    destino.write_text(json.dumps(saida, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"novidades: {len(novos)} adicionados, {len(mais_episodios)} séries com episódios novos "
          f"({destino.stat().st_size / 1024:.1f} KB)")


if __name__ == "__main__":
    main()
