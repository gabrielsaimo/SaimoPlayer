#!/bin/bash
#
# Publica os catálogos nos dois links que os apps leem:
#
#   canais   https://saimo-canais.pages.dev   catalogo.txt, canais.txt, restritos.txt,
#                                             radios.txt e versao.json (a versão publicada)
#   filmes   https://saimo-filmes.pages.dev   tudo o que está em vod/ (acervo, capas,
#                                             fichas, destaques, novidades, imdb…)
#
# São arquivos estáticos no Cloudflare Pages: não passam pelo Worker, então não
# contam como pedido (o que o monitor cobra) e a banda é de graça. Os apps não
# sabem em que GitHub os arquivos moram — só os dois endereços acima. Trocar de
# GitHub, ou de servidor, é só deste script para frente.
#
#   ./scripts/publicar_catalogos.sh            publica os dois
#   ./scripts/publicar_catalogos.sh canais     só o catálogo de canais
#   ./scripts/publicar_catalogos.sh filmes     só filmes e séries
#   ./scripts/publicar_catalogos.sh --montar   só monta as pastas, sem publicar
#
# Autenticação: CLOUDFLARE_API_TOKEN (permissão "Cloudflare Pages: Edit") ou o
# `wrangler login` desta máquina. CLOUDFLARE_ACCOUNT_ID já vem fixado aqui.
#
# Sai com 0 mesmo se a publicação falhar quando chamado com --nao-falhar (é como
# o atualizar_tudo.sh chama: o catálogo foi gerado e commitado, e um problema
# na Cloudflare não pode desfazer isso — a próxima rodada publica de novo).
set -uo pipefail
cd "$(dirname "$0")/.."

CONTA="${CLOUDFLARE_ACCOUNT_ID:-e0f6d97a9f8f4bb1b7a8ce6a7a470b3f}"
export CLOUDFLARE_ACCOUNT_ID="$CONTA"
PROJETO_CANAIS="${SAIMO_PROJETO_CANAIS:-saimo-canais}"
PROJETO_FILMES="${SAIMO_PROJETO_FILMES:-saimo-filmes}"
# Limite do Pages: 25 MiB por arquivo.
TETO_BYTES=$((24 * 1024 * 1024))
SAIDA="arquivos-gerados/publico"

quais=""
montar_so=0
nao_falhar=0
for a in "$@"; do
  case "$a" in
    canais|filmes) quais="$quais $a" ;;
    --montar) montar_so=1 ;;
    --nao-falhar) nao_falhar=1 ;;
    *) echo "opção desconhecida: $a" >&2; exit 2 ;;
  esac
done
[ -z "$quais" ] && quais="canais filmes"

falhar() {
  echo "publicar_catalogos: $*" >&2
  [ "$nao_falhar" = 1 ] && exit 0
  exit 1
}

CABECALHOS='/*
  Access-Control-Allow-Origin: *
  Cache-Control: public, max-age=300
  X-Content-Type-Options: nosniff
'

montar_canais() {
  local d="$SAIDA/canais"
  rm -rf "$d"; mkdir -p "$d"
  for f in catalogo.txt canais.txt restritos.txt versao.json; do
    [ -f "$f" ] && cp "$f" "$d/$f"
  done
  [ -f vod/radios.txt ] && cp vod/radios.txt "$d/radios.txt"
  [ -f "$d/catalogo.txt" ] || falhar "sem catalogo.txt: nada a publicar"
  printf '%s' "$CABECALHOS" > "$d/_headers"
}

montar_filmes() {
  local d="$SAIDA/filmes"
  rm -rf "$d"; mkdir -p "$d"
  # mgeb e fenix são entradas dos geradores (dezenas de MB, ninguém lê).
  rsync -a --prune-empty-dirs \
    --exclude='.DS_Store' --exclude='__pycache__' --exclude='mgeb/' --exclude='fenix/' \
    --max-size="$TETO_BYTES" vod/ "$d/" || falhar "rsync do vod falhou"
  [ -f "$d/indice.txt" ] || falhar "sem vod/indice.txt: nada a publicar"
  printf '%s' "$CABECALHOS" > "$d/_headers"
}

achar_wrangler() {
  if command -v wrangler >/dev/null 2>&1; then command -v wrangler; return; fi
  local c
  # O launchd não carrega o PATH do terminal: procura onde o nvm costuma deixar.
  for c in "$HOME"/.nvm/versions/node/*/bin/wrangler /opt/homebrew/bin/wrangler /usr/local/bin/wrangler; do
    [ -x "$c" ] && { echo "$c"; return; }
  done
  return 1
}

for q in $quais; do
  case "$q" in
    canais) montar_canais ;;
    filmes) montar_filmes ;;
  esac
done
echo "montado em $SAIDA: $(for q in $quais; do printf '%s=%s arquivos  ' "$q" "$(find "$SAIDA/$q" -type f | wc -l | tr -d ' ')"; done)"
[ "$montar_so" = 1 ] && exit 0

WRANGLER="$(achar_wrangler)" || falhar "wrangler não encontrado (npm i -g wrangler)"
# O wrangler vive no nvm: precisa do node dele no PATH.
export PATH="$(dirname "$WRANGLER"):$PATH"

status=0
for q in $quais; do
  projeto="$PROJETO_CANAIS"; [ "$q" = filmes ] && projeto="$PROJETO_FILMES"
  # Um arquivo só mudou = um arquivo só enviado: o wrangler compara os hashes.
  if "$WRANGLER" pages deploy "$SAIDA/$q" --project-name "$projeto" --branch main \
       --commit-dirty=true --commit-message "publicar $q $(date '+%Y-%m-%d %H:%M')" >"$SAIDA/$q.log" 2>&1; then
    echo "publicado: $q -> https://$projeto.pages.dev"
  else
    echo "FALHOU: $q (veja $SAIDA/$q.log)" >&2
    tail -3 "$SAIDA/$q.log" >&2
    status=1
  fi
done
[ "$status" = 1 ] && [ "$nao_falhar" = 1 ] && exit 0
exit "$status"
