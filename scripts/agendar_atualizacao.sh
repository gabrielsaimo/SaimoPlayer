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
# Para acompanhar: tail -f arquivos-gerados/atualizacao.log
set -euo pipefail
cd "$(dirname "$0")/.."
RAIZ="$(pwd)"

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
    if [ -f arquivos-gerados/atualizacao.log ]; then
      echo "últimas linhas:"
      grep -E "^\[" arquivos-gerados/atualizacao.log | tail -5
    fi
    exit 0
    ;;
  "") ;;
  *) echo "opção desconhecida: $1" >&2; exit 2 ;;
esac

mkdir -p "$HOME/Library/LaunchAgents" "$RAIZ/arquivos-gerados"

cat > "$PLIST" <<PLISTA
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$ETIQUETA</string>
  <key>ProgramArguments</key>
  <array>
    <string>$RAIZ/atualizar_tudo.sh</string>
  </array>
  <key>WorkingDirectory</key>
  <string>$RAIZ</string>
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
  </dict>
  <key>StandardOutPath</key>
  <string>$RAIZ/arquivos-gerados/launchd.log</string>
  <key>StandardErrorPath</key>
  <string>$RAIZ/arquivos-gerados/launchd.log</string>
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
