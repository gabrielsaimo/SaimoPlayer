#!/bin/bash
#
# Atualiza o catálogo inteiro e as fileiras da tela inicial, e publica.
#
# Passos:
#   1. atualizar_nixplay.py   a lista principal de filmes e séries (nixplay)
#   2. gerar_vod.py           o acervo que os apps mostram: nixplay na frente,
#                             listas M3U e o acervo consolidado existente
#   3. gerar_generos.py       capa e gênero de cada título (fichas.txt); só
#                             pergunta ao TMDB pelos que ainda não conhece
#   4. gerar_imdb.py          ids do IMDb dos títulos novos (legendas)
#   5. gerar_destaques.py     as fileiras da tela inicial
#   6. gerar_novidades.py     registra o que entrou e o que mudou na rodada
#
#   ./atualizar_tudo.sh              tudo: nixplay, acervo, capas e fileiras
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

# O agendamento roda numa cópia à parte (ver scripts/agendar_atualizacao.sh),
# e o que for publicado de outro lugar — um script corrigido, um catálogo
# rodado à mão — tem que chegar nela antes. --autostash porque esta mesma
# linha roda na cópia onde se trabalha, que pode ter coisa por commitar.
git pull -q --rebase --autostash origin main 2>>"$REGISTRO" \
  || anotar "não deu para puxar do GitHub; seguindo com o que há aqui"

# O catálogo de canais e a versão publicada (catalogo.txt, restritos.txt,
# versao.json…) também mudam por fora desta rodada — commit à mão, painel do
# monitor, release — e os apps leem de saimo-canais.pages.dev, não do Git.
# Publicar o que acabou de chegar custa segundos (o Pages só envia o que mudou).
anotar "publicando os canais nos links dos apps"
./scripts/publicar_catalogos.sh canais --nao-falhar >>"$REGISTRO" 2>&1 \
  || anotar "links dos canais: não consegui publicar (a próxima rodada tenta de novo)"

if [ "$somente_destaques" = 0 ]; then
  anotar "fontes da lista principal (nixplay)"
  python3 atualizar_nixplay.py \
    >>"$REGISTRO" 2>&1 || anotar "nixplay: falhou, seguindo assim mesmo"

  # Se o acervo não se remontar, o resto segue com o de ontem: melhor que
  # parar a atualização inteira por causa de uma lista M3U fora do ar.
  anotar "montando o acervo consolidado (listas M3U + nixplay)"
  python3 gerar_vod.py >>"$REGISTRO" 2>&1 \
    || { anotar "acervo: falhou, voltando ao publicado"; git checkout -q -- ":(glob)vod/*.txt"; }

  anotar "capas e gêneros dos títulos novos"
  python3 gerar_generos.py >>"$REGISTRO" 2>&1 \
    || anotar "capas e gêneros: falhou, seguindo com as de ontem"

  # O IMDb de cada título, para as legendas: só pergunta pelos que ainda não
  # conhece, então depois da primeira vez são segundos.
  anotar "ids do IMDb dos títulos novos (legendas)"
  python3 gerar_imdb.py >>"$REGISTRO" 2>&1 \
    || anotar "ids do IMDb: falhou, seguindo com os de ontem"
fi

# Esta não pode falhar calada: é ela que desenha a primeira tela de todo mundo.
anotar "montando as fileiras da tela inicial"
if ! python3 gerar_destaques.py >>"$REGISTRO" 2>&1; then
  anotar "destaques: FALHOU — nada será publicado"
  exit 1
fi

# O que entrou e o que mudou nesta rodada, para a página de novidades do site
# (vod/novidades.json). Não pode derrubar a publicação.
anotar "registrando as novidades da rodada"
python3 gerar_novidades.py >>"$REGISTRO" 2>&1 \
  || anotar "novidades: falhou, seguindo sem o registro desta rodada"

if [ -n "$(git status --porcelain -- vod)" ]; then
  anotar "mudou: $(git add -N vod && git diff --stat -- vod | tail -1)"
else
  anotar "nada mudou no Git"
  # Mesmo assim confere os links: uma publicação anterior pode ter falhado.
  ./scripts/publicar_catalogos.sh --nao-falhar >>"$REGISTRO" 2>&1 \
    || anotar "links dos apps: não consegui publicar (a próxima rodada tenta de novo)"
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

# Filmes e séries nos links dos apps. Também quando a rodada não mudou nada
# no Git: uma publicação anterior pode ter falhado.
anotar "publicando filmes e séries nos links dos apps"
./scripts/publicar_catalogos.sh --nao-falhar >>"$REGISTRO" 2>&1 \
  || anotar "links dos filmes: não consegui publicar (a próxima rodada tenta de novo)"

# O GitHub de antes da migração (remote `legado`), enquanto existir app 2.3.x
# lendo o catálogo de lá. Sem o remote, não faz nada.
if git remote get-url legado >/dev/null 2>&1; then
  git push -q legado HEAD:main 2>>"$REGISTRO" \
    && anotar "espelhado no legado" || anotar "legado: push recusado"
fi

anotar "=== fim"
