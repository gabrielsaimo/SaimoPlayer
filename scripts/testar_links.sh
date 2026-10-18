#!/bin/bash
# Testa a normalização dos endereços, o formulário "Endereço das listas", o
# guia.txt e a categoria do canal, sem rede.
set -euo pipefail
cd "$(dirname "$0")/.."
saida="$(mktemp -d)"
trap 'rm -rf "$saida"' EXIT
cp Tests/LinksTeste.swift "$saida/main.swift"
swiftc -swift-version 6 Sources/Links.swift Sources/FormularioListas.swift Sources/GuiaTabelas.swift \
  Sources/Migracao.swift Sources/Enderecos.swift Sources/Model.swift \
  "$saida/main.swift" -o "$saida/teste"
"$saida/teste" | grep -v '^ok' || true
"$saida/teste" >/dev/null && echo "links: tudo certo"
