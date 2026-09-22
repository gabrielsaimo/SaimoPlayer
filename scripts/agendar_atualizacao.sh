#!/bin/bash
#
# Põe (ou tira) a atualização diária do catálogo no macOS.
#
# Quem roda é o launchd, não um terminal aberto: ele acorda às 5h, chama o
# `atualizar_tudo.sh` e some. Se a máquina estiver dormindo na hora marcada, o
# launchd roda assim que ela acordar — que é o certo aqui, porque atrasar
# algumas horas é melhor que pular o dia.
#
#   ./scripts/agendar_atualizacao.sh            liga
#   ./scripts/agendar_atualizacao.sh --tirar    desliga
#   ./scripts/agendar_atualizacao.sh --ver      diz se está ligado e quando rodou
#
# Quem roda às 5h é uma cópia do repositório no disco interno, em
# ~/Library/Application Support/SaimoTV/SaimoPlayer, e não esta aqui. O macOS
# não deixa processo de fundo ler arquivo em disco externo ("Operation not
# permitted"), e por isso nenhuma rodada das 5h aconteceu de fato até 21/09 —
# todas as linhas do registro eram de rodadas manuais. A cópia é criada e
# recebe os caches daqui na primeira vez; depois ela mesma se atualiza pelo
# git antes de cada rodada.
#
# Para acompanhar: tail -f ~/Library/Application\ Support/SaimoTV/SaimoPlayer/arquivos-gerados/atualizacao.log
set -euo pipefail
cd "$(dirname "$0")/.."
ORIGEM="$(pwd)"
RAIZ="$HOME/Library/Application Support/SaimoTV/SaimoPlayer"

ETIQUETA="dev.saimo.atualizar-catalogo"
PLIST="$HOME/Library/LaunchAgents/$ETIQUETA.plist"
HORA=5
MINUTO=0

case "${1:-}" in
  --tirar)
    launchctl unload "$PLIST" 2>/dev/null || true
    rm -f "$PLIST"
    echo "agendamento removido."
    exit 0
    ;;
  --ver)
    # A lista vem para uma variável antes de ser procurada: com `pipefail`, um
    # `launchctl list | grep -q` dá falso mesmo achando, porque o grep fecha o
    # cano no primeiro acerto e o launchctl morre de SIGPIPE.
    registradas="$(launchctl list || true)"
    if printf '%s' "$registradas" | grep -q "$ETIQUETA"; then
      echo "ligado — todo dia às ${HORA}h${MINUTO}"
    else
      echo "desligado"
    fi
    if [ -f "$RAIZ/arquivos-gerados/atualizacao.log" ]; then
      echo "últimas linhas:"
      grep -E "^\[" "$RAIZ/arquivos-gerados/atualizacao.log" | tail -5
    fi
    exit 0
    ;;
  "") ;;
  *) echo "opção desconhecida: $1" >&2; exit 2 ;;
esac

mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs/SaimoTV"

if [ ! -d "$RAIZ/.git" ]; then
  echo "criando a cópia de trabalho em $RAIZ"
  mkdir -p "$(dirname "$RAIZ")"
  git clone -q "$(git -C "$ORIGEM" remote get-url origin)" "$RAIZ"
fi
mkdir -p "$RAIZ/arquivos-gerados"
# Os caches são o que torna a rodada curta: sem eles o resolvedor pergunta de
# novo por duzentos e tantos mil episódios. Vão uma vez; depois cada cópia
# cuida do seu.
for cache in redeflix generos.sqlite3 embedplayer-filmes embedplayer-series; do
  if [ -e "$ORIGEM/arquivos-gerados/$cache" ] && [ ! -e "$RAIZ/arquivos-gerados/$cache" ]; then
    echo "copiando o cache $cache"
    cp -R "$ORIGEM/arquivos-gerados/$cache" "$RAIZ/arquivos-gerados/"
    [ -d "$RAIZ/arquivos-gerados/$cache" ] && rm -f "$RAIZ/arquivos-gerados/$cache/execucao.lock"
  fi
done

# A chave do TMDB mora nos projetos vizinhos (ver discover_tmdb_key em
# gerar_embedplayer_filmes.py), que não existem ao lado da cópia interna. Ela
# vai para o ambiente do agendamento; sem isso os filmes novos não resolvem.
CHAVE_TMDB="$(cd "$ORIGEM" && python3 -c 'from gerar_embedplayer_filmes import discover_tmdb_key; print(discover_tmdb_key(""))' 2>/dev/null || true)"
[ -n "$CHAVE_TMDB" ] || echo "aviso: chave do TMDB não encontrada; filmes novos não vão resolver"

cat > "$PLIST" <<PLISTA
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$ETIQUETA</string>
  <!--
    Nada que o launchd precise abrir sozinho pode morar no disco externo: com
    WorkingDirectory e o log apontando para lá, ele desistia antes de começar
    (saída 78, EX_CONFIG) e nenhuma rodada das 5h aconteceu de fato. Quem entra
    no disco é o bash, depois de já estar rodando — e o atualizar_tudo.sh faz o
    próprio cd.
  -->
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$RAIZ/atualizar_tudo.sh</string>
  </array>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key><integer>$HORA</integer>
    <key>Minute</key><integer>$MINUTO</integer>
  </dict>
  <!-- O git precisa achar as credenciais e o python; o launchd dá um PATH
       mínimo que não inclui o Homebrew. -->
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    <key>TMDB_API_KEY</key>
    <string>$CHAVE_TMDB</string>
  </dict>
  <key>StandardOutPath</key>
  <string>$HOME/Library/Logs/SaimoTV/launchd.log</string>
  <key>StandardErrorPath</key>
  <string>$HOME/Library/Logs/SaimoTV/launchd.log</string>
  <key>RunAtLoad</key>
  <false/>
</dict>
</plist>
PLISTA

launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"
echo "ligado — todo dia às ${HORA}h${MINUTO}, rodando $RAIZ/atualizar_tudo.sh"
echo "acompanhar:  tail -f $RAIZ/arquivos-gerados/atualizacao.log"
echo "desligar:    ./scripts/agendar_atualizacao.sh --tirar"
