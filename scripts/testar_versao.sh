#!/bin/bash
# Testa versao.json (parse, lista de endereços, SHA-256) sem rede.
set -euo pipefail
cd "$(dirname "$0")/.."
saida="$(mktemp -d)"
trap 'rm -rf "$saida"' EXIT
cp Tests/VersaoPublicadaTeste.swift "$saida/main.swift"
swiftc -swift-version 6 Sources/VersaoPublicada.swift Sources/Atualizacao.swift \
  Sources/BaixadorDeAtualizacao.swift Sources/Upstream.swift Sources/Enderecos.swift Sources/Log.swift \
  "$saida/main.swift" -o "$saida/teste"
"$saida/teste" | grep -v '^ok' || true
"$saida/teste" >/dev/null && echo "versao: tudo certo"
