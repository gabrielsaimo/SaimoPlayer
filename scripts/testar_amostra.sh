#!/bin/bash
# Compila Amostra.swift com o teste e roda: confere o hash FNV-1a contra
# valores calculados com o mesmo algoritmo do servidor (node).
set -euo pipefail
cd "$(dirname "$0")/.."
saida="$(mktemp -d)"
trap 'rm -rf "$saida"' EXIT
cp Tests/AmostraTeste.swift "$saida/main.swift"
swiftc -swift-version 6 Sources/Amostra.swift "$saida/main.swift" -o "$saida/teste"
"$saida/teste"
