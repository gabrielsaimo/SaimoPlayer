#!/bin/bash
#
# Atualiza o catálogo inteiro e as fileiras da tela inicial, e publica.
#
# Cinco passos, nesta ordem, porque cada um lê o que o anterior escreveu:
#
#   1. atualizar_redeflix.py  filmes e séries novos do Redeflix (vod/redeflix)
#   2. atualizar_redeflix.py  animes e doramas: episódios novos e títulos novos
#   3. gerar_vod.py           o acervo que os apps mostram: listas M3U + o que
#                             o Redeflix resolveu, sem perder os links antigos
#   4. gerar_generos.py       capa e gênero de cada título (fichas.txt); só
#                             pergunta ao TMDB pelos que ainda não conhece
#   5. gerar_destaques.py     as fileiras da tela inicial
#
# Até 21/09/2026 só o 1, o 2 e o 5 rodavam: os filmes e séries novos ficavam
# resolvidos em vod/redeflix sem que app nenhum os lesse, anime novo nunca
# entrava, e título novo ficava sem capa.
#
# O mesmo trabalho existe num workflow do GitHub, que roda sozinho de
# madrugada. Enquanto a conta estiver travada por cobrança, este aqui faz o
# serviço na própria máquina — e os dois podem conviver: o que um publicar, o
# outro encontra publicado.
#
#   ./atualizar_tudo.sh              tudo: fontes novas e fileiras
#   ./atualizar_tudo.sh --destaques  só as fileiras (rápido, uns dois minutos)
#   ./atualizar_tudo.sh --sem-subir  faz, mostra, mas não commita nem empurra
#
# Sem terminal nenhum, todo dia: ver `scripts/agendar_atualizacao.sh`.
set -uo pipefail
cd "$(dirname "$0")"

REGISTRO="arquivos-gerados/atualizacao.log"
TRAVA="arquivos-gerados/atualizacao.lock"
mkdir -p arquivos-gerados

somente_destaques=0
subir=1
for argumento in "$@"; do
  case "$argumento" in
    --destaques) somente_destaques=1 ;;
    --sem-subir) subir=0 ;;
    *) echo "opção desconhecida: $argumento" >&2; exit 2 ;;
  esac
done

# Duas execuções ao mesmo tempo disputariam o cache do resolvedor. A do
# agendamento pode cair em cima de uma que você começou à mão.
exec 9>"$TRAVA"
if ! flock -n 9 2>/dev/null; then
  # O macOS não traz flock; nesse caso a trava é o próprio PID no arquivo.
  if [ -s "$TRAVA" ] && kill -0 "$(cat "$TRAVA")" 2>/dev/null; then
    echo "já tem uma atualização rodando (PID $(cat "$TRAVA")). Saindo."
    exit 0
  fi
fi
echo $$ > "$TRAVA"
trap 'rm -f "$TRAVA"' EXIT

anotar() {
  printf '[%s] %s\n' "$(date '+%d/%m %H:%M:%S')" "$*" | tee -a "$REGISTRO"
}

anotar "=== início ($([ $somente_destaques = 1 ] && echo "só destaques" || echo "tudo"))"

if [ "$somente_destaques" = 0 ]; then
  anotar "resolvendo filmes e séries"
  python3 atualizar_redeflix.py --gerar --categorias filmes,series --workers 96 \
    >>"$REGISTRO" 2>&1 || anotar "filmes e séries: falhou, seguindo assim mesmo"

  anotar "resolvendo animes e doramas"
  python3 atualizar_redeflix.py --gerar --categorias animes,doramas \
    --repetir-indisponiveis --workers 48 \
    --tentativas-indisponiveis 2 --delay-episodio 0.05 \
    --somente-titulos-publicados \
    >>"$REGISTRO" 2>&1 || anotar "animes e doramas: falhou, seguindo assim mesmo"

  # Se o acervo não se remontar, o resto segue com o de ontem: melhor que
  # parar a atualização inteira por causa de uma lista M3U fora do ar.
  anotar "montando o acervo (listas M3U + Redeflix)"
  python3 gerar_vod.py >>"$REGISTRO" 2>&1 \
    || { anotar "acervo: falhou, voltando ao publicado"; git checkout -q -- ":(glob)vod/*.txt"; }

  anotar "capas e gêneros dos títulos novos"
  python3 gerar_generos.py >>"$REGISTRO" 2>&1 \
    || anotar "capas e gêneros: falhou, seguindo com as de ontem"
fi

# Esta não pode falhar calada: é ela que desenha a primeira tela de todo mundo.
anotar "montando as fileiras da tela inicial"
if ! python3 gerar_destaques.py >>"$REGISTRO" 2>&1; then
  anotar "destaques: FALHOU — nada será publicado"
  exit 1
fi

if [ -n "$(git status --porcelain -- vod)" ]; then
  anotar "mudou: $(git add -N vod && git diff --stat -- vod | tail -1)"
else
  anotar "nada mudou, nada a publicar"
  exit 0
fi

if [ "$subir" = 0 ]; then
  anotar "--sem-subir: parando antes de commitar"
  exit 0
fi

# Só a pasta do catálogo: o que mais estiver mexido na árvore é trabalho seu,
# e não pode entrar de carona num commit automático. Pasta inteira porque o
# acervo cria e apaga arquivos (uma letra nova, um pedaço de série a mais).
git add -A vod
if git diff --cached --quiet; then
  anotar "nada a commitar"
  exit 0
fi
git commit -q -m "Atualiza catálogo e destaques" || { anotar "commit falhou"; exit 1; }

if git push -q origin HEAD 2>>"$REGISTRO"; then
  anotar "publicado: $(git log --oneline -1)"
else
  # O commit fica: a próxima execução empurra os dois juntos. Perder o
  # trabalho por causa de um push recusado seria pior que o atraso.
  anotar "push recusado (branch atrás do remoto?). O commit ficou aqui."
  exit 1
fi

anotar "=== fim"
