#!/bin/bash
#
# Leva todos os projetos Saimo para outro GitHub, sem derrubar nada.
#
# Como a troca é segura:
#  - Os apps não leem o GitHub: leem saimo-canais.pages.dev e saimo-filmes.pages.dev
#    (Cloudflare). Trocar o GitHub não muda nenhum endereço que eles usam.
#  - O GitHub antigo continua recebendo tudo (remote `legado`, espelho e release)
#    enquanto houver app 2.3.x procurando por lá. Aposente-o só quando o painel do
#    monitor mostrar que quase ninguém está nessas versões.
#  - Nada é apagado, em lugar nenhum.
#
# Antes de rodar:
#   1. Crie a conta (ou organização) nova no GitHub.
#   2. gh auth login           (entre com a conta nova; a antiga continua guardada)
#   3. Crie um token da Cloudflare em dash.cloudflare.com/profile/api-tokens
#      com a permissão "Cloudflare Pages: Edit" e exporte:
#        export CLOUDFLARE_API_TOKEN=...
#   4. (para o espelho do GitHub antigo) um token fine-grained da conta antiga com
#      "Contents: Read and write" só no SaimoPlayer antigo:
#        export LEGADO_TOKEN=...
#
#   ./scripts/migrar-github.sh NOVO_DONO              só mostra o que faria
#   ./scripts/migrar-github.sh NOVO_DONO --executar   faz de verdade
#   ./scripts/migrar-github.sh NOVO_DONO --executar --etapa 3   só a etapa 3
#
# Etapas:
#   1 conferir tudo         2 criar os repositórios      3 enviar o código e o histórico
#   4 segredos e fluxos     5 monitor                    6 cópia do agendador do Mac
#   7 links nos READMEs     8 desligar o agendamento duplicado no GitHub antigo
# O site (Cloudflare Pages) tem um passo à parte, que derruba o site por ~1 minuto:
# ver Saimo-TV/docs/TROCA-DO-SITE.md.
set -uo pipefail

NOVO="${1:-}"
[ -z "$NOVO" ] || [ "${NOVO:0:2}" = "--" ] && { sed -n '2,36p' "$0"; exit 2; }
shift
EXECUTAR=0
SO_ETAPA=""
while [ $# -gt 0 ]; do
  case "$1" in
    --executar) EXECUTAR=1 ;;
    --etapa) shift; SO_ETAPA="${1:-}" ;;
    *) echo "opção desconhecida: $1" >&2; exit 2 ;;
  esac
  shift
done

RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
ANTIGO_DONO="gabrielsaimo"
REPOS=(SaimoPlayer SaimoTV-Android Saimo-Cell-V2 SaimoWin Saimo-TV SaimoMonitor)
# Só código e catálogo: privados. O que o app baixa (APK, DMG, zip) precisa ser
# público para a atualização funcionar sem login, e vai num repositório só para isso.
DOWNLOADS="saimo-downloads"
CONTA="e0f6d97a9f8f4bb1b7a8ce6a7a470b3f"

faz() {
  if [ "$EXECUTAR" = 1 ]; then
    echo "  \$ $*"
    "$@"
  else
    echo "  (simulação) $*"
  fi
}
etapa() { [ -z "$SO_ETAPA" ] || [ "$SO_ETAPA" = "$1" ]; }
titulo() { echo; echo "== etapa $1: $2"; }
erro() { echo "ERRO: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
if etapa 1; then
  titulo 1 "conferir"
  command -v gh >/dev/null || erro "instale o gh (brew install gh)"
  login="$(gh api user -q .login 2>/dev/null || true)"
  [ -n "$login" ] || erro "gh sem login: rode gh auth login"
  echo "  gh está como: $login"
  if [ "$login" != "$NOVO" ] && ! gh api "orgs/$NOVO" -q .login >/dev/null 2>&1; then
    erro "o gh está logado como '$login', e '$NOVO' não é uma organização dele. Use: gh auth switch (ou gh auth login com a conta $NOVO)."
  fi
  for r in "${REPOS[@]}"; do
    d="$RAIZ/$r"
    [ -d "$d" ] || erro "não achei $d"
    if [ -d "$d/.git" ]; then
      [ -z "$(git -C "$d" status --porcelain)" ] || erro "$r tem alterações sem commit: commite antes"
      [ "$(git -C "$d" branch --show-current)" = main ] || erro "$r não está na main"
      git -C "$d" remote get-url legado >/dev/null 2>&1 && erro "$r já tem o remote 'legado': já foi migrado?"
    fi
  done
  curl -fsS -o /dev/null https://saimo-canais.pages.dev/catalogo.txt || erro "o link dos canais não responde"
  curl -fsS -o /dev/null https://saimo-filmes.pages.dev/indice.txt || erro "o link dos filmes não responde"
  echo "  tudo certo"
fi

# ---------------------------------------------------------------------------
if etapa 2; then
  titulo 2 "criar os repositórios em $NOVO"
  for r in "${REPOS[@]}"; do
    faz gh repo create "$NOVO/$r" --private
  done
  faz gh repo create "$NOVO/$DOWNLOADS" --public --add-readme \
    --description "Downloads dos apps Saimo TV"
fi

# ---------------------------------------------------------------------------
if etapa 3; then
  titulo 3 "enviar código e histórico (o antigo vira o remote 'legado')"
  for r in "${REPOS[@]}"; do
    d="$RAIZ/$r"
    if [ -d "$d/.git" ] && git -C "$d" remote get-url origin >/dev/null 2>&1; then
      faz git -C "$d" remote rename origin legado
    fi
    faz git -C "$d" remote add origin "https://github.com/$NOVO/$r.git"
    faz git -C "$d" push origin --all
    faz git -C "$d" push origin --tags
  done
  # O release vai para o repositório de downloads (público); o antigo recebe o
  # mesmo release enquanto durar a ponte (release.sh faz isso pelo remote legado).
  if [ "$EXECUTAR" = 1 ]; then
    echo "$NOVO/$DOWNLOADS" > "$RAIZ/SaimoPlayer/scripts/release-repo.txt"
    git -C "$RAIZ/SaimoPlayer" add scripts/release-repo.txt
    git -C "$RAIZ/SaimoPlayer" commit -q -m "release: downloads em $NOVO/$DOWNLOADS" -- scripts/release-repo.txt
    git -C "$RAIZ/SaimoPlayer" push -q origin HEAD
  else
    echo "  (simulação) escrever scripts/release-repo.txt com $NOVO/$DOWNLOADS e commitar"
  fi
fi

# ---------------------------------------------------------------------------
if etapa 4; then
  titulo 4 "segredos dos fluxos no SaimoPlayer novo"
  [ -n "${CLOUDFLARE_API_TOKEN:-}" ] || echo "  AVISO: CLOUDFLARE_API_TOKEN não exportado — o fluxo de publicação só vai avisar"
  if [ -n "${CLOUDFLARE_API_TOKEN:-}" ]; then
    faz bash -c "printf %s \"\$CLOUDFLARE_API_TOKEN\" | gh secret set CLOUDFLARE_API_TOKEN --repo $NOVO/SaimoPlayer"
  fi
  faz bash -c "printf %s $CONTA | gh secret set CLOUDFLARE_ACCOUNT_ID --repo $NOVO/SaimoPlayer"
  if [ -n "${LEGADO_TOKEN:-}" ]; then
    faz bash -c "printf %s \"\$LEGADO_TOKEN\" | gh secret set LEGADO_TOKEN --repo $NOVO/SaimoPlayer"
    faz gh variable set LEGADO_REPO --repo "$NOVO/SaimoPlayer" --body "$ANTIGO_DONO/SaimoPlayer"
  else
    echo "  AVISO: LEGADO_TOKEN não exportado — o GitHub antigo só será atualizado pelo Mac (git push legado)"
  fi
  # Primeira publicação pelo fluxo, para provar que os segredos funcionam.
  faz gh workflow run publicar-catalogos.yml --repo "$NOVO/SaimoPlayer"
fi

# ---------------------------------------------------------------------------
if etapa 5; then
  titulo 5 "monitor"
  m="$RAIZ/SaimoMonitor"
  # O escopo do repositório é fixo no código de propósito (ver o teste em
  # source-order.test.mjs): troca-se a constante, não uma variável.
  if [ "$EXECUTAR" = 1 ]; then
    sed -i '' "s#const REPO = '$ANTIGO_DONO/SaimoPlayer';#const REPO = '$NOVO/SaimoPlayer';#" "$m/src/source-order.js"
    grep -q "const REPO = '$NOVO/SaimoPlayer'" "$m/src/source-order.js" || erro "não consegui trocar o REPO em source-order.js"
    git -C "$m" add -A
    git -C "$m" commit -q -m "monitor: repositório do catálogo agora em $NOVO"
    git -C "$m" push -q origin HEAD
  else
    echo "  (simulação) trocar REPO em SaimoMonitor/src/source-order.js para $NOVO/SaimoPlayer e commitar"
  fi
  faz bash -c "cd '$m' && CLOUDFLARE_ACCOUNT_ID=$CONTA npx wrangler deploy"
  faz bash -c "cd '$m' && printf %s $NOVO/SaimoPlayer | CLOUDFLARE_ACCOUNT_ID=$CONTA npx wrangler secret put GITHUB_REPO"
  echo "  FALTA (à mão, o token não passa por aqui): crie um token fine-grained da conta nova com"
  echo "    Contents: Read and write + Actions: Read and write, só no $NOVO/SaimoPlayer, e rode:"
  echo "    cd $m && CLOUDFLARE_ACCOUNT_ID=$CONTA npx wrangler secret put GITHUB_TOKEN"
fi

# ---------------------------------------------------------------------------
if etapa 6; then
  titulo 6 "cópia de trabalho do agendador do Mac"
  copia="$HOME/Library/Application Support/SaimoTV/SaimoPlayer"
  if [ -d "$copia/.git" ]; then
    faz git -C "$copia" remote rename origin legado
    faz git -C "$copia" remote add origin "https://github.com/$NOVO/SaimoPlayer.git"
    faz git -C "$copia" fetch origin
    faz git -C "$copia" branch --set-upstream-to=origin/main main
  else
    echo "  sem cópia do agendador em $copia (ela é criada por scripts/agendar_atualizacao.sh)"
  fi
fi

# ---------------------------------------------------------------------------
if etapa 7; then
  titulo 7 "links nos READMEs"
  for r in "${REPOS[@]}"; do
    f="$RAIZ/$r/README.md"
    [ -f "$f" ] || continue
    if grep -q "github.com/$ANTIGO_DONO/" "$f"; then
      if [ "$EXECUTAR" = 1 ]; then
        sed -i '' "s#github.com/$ANTIGO_DONO/#github.com/$NOVO/#g" "$f"
        git -C "$RAIZ/$r" commit -q -m "docs: links do GitHub agora em $NOVO" -- README.md
        git -C "$RAIZ/$r" push -q origin HEAD
        echo "  $r/README.md atualizado"
      else
        echo "  (simulação) $r/README.md: github.com/$ANTIGO_DONO/ -> github.com/$NOVO/"
      fi
    fi
  done
fi

# ---------------------------------------------------------------------------
if etapa 8; then
  titulo 8 "desligar o agendamento duplicado no GitHub antigo"
  echo "  O repositório novo passa a gerar o catálogo e espelha no antigo (fluxo 'Espelhar no repositório antigo')."
  faz gh workflow disable atualizar-ids-redeflix.yml --repo "$ANTIGO_DONO/SaimoPlayer"
fi

echo
echo "pronto${EXECUTAR:+.}$([ "$EXECUTAR" = 0 ] && echo ' (era só simulação: use --executar)')"
