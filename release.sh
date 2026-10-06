#!/bin/bash
#
# Publica uma versão: monta o DMG, o APK da TV e o app do Windows, e sobe tudo
# no mesmo release, junto do APK do celular quando ele já estiver montado.
#
# A versão sai do Info.plist e é gravada também no APK, para que os dois lados
# comparem a mesma coisa com a tag. O nome dos arquivos é o contrato com o
# atualizador: ele procura no release um .dmg e um .apk.
#
#   ./release.sh                 usa a versão do Info.plist
#   ./release.sh 1.1.0           marca esta versão antes de publicar
#   ./release.sh 1.1.0 --rascunho  cria como rascunho, para revisar no site
set -euo pipefail
cd "$(dirname "$0")"

PLIST="Info.plist"
GRADLE="../SaimoTV-Android/app/build.gradle.kts"
JAVA17="/opt/homebrew/Cellar/openjdk@17/17.0.19/libexec/openjdk.jdk/Contents/Home"

versao="${1:-}"
if [ -n "$versao" ] && [ "${versao:0:2}" != "--" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $versao" "$PLIST"
  # O versionCode precisa só crescer, então vira um número a partir da versão:
  # 1.2.3 -> 10203. Sem isso o Android recusa a instalação por cima.
  codigo=$(python3 - "$versao" <<'PY'
import sys
p = (sys.argv[1].split(".") + ["0", "0"])[:3]
print(int(p[0]) * 10000 + int(p[1]) * 100 + int(p[2]))
PY
)
  sed -i '' "s/versionName = \".*\"/versionName = \"$versao\"/" "$GRADLE"
  sed -i '' "s/versionCode = .*/versionCode = $codigo/" "$GRADLE"
  shift
else
  versao=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")
fi

echo "==> versão $versao"

echo "==> montando o DMG"
./make_dmg.sh >/dev/null
mkdir -p build/release
cp "build/SaimoTV.dmg" "build/release/SaimoTV.dmg"

echo "==> montando o APK da TV"
# assembleRelease, e não Debug: o APK publicado sai assinado com a chave da
# pasta chaves, que é o que permite atualizar por cima.
( cd ../SaimoTV-Android && JAVA_HOME="$JAVA17" ANDROID_HOME="$HOME/Library/Android/sdk" \
  ./gradlew assembleRelease -q )
cp "../SaimoTV-Android/app/build/outputs/apk/release/app-release.apk" "build/release/SaimoTV.apk"

echo "==> montando o app do Windows"
( cd ../SaimoWin && ./empacotar.sh >/dev/null )
cp "../SaimoWin/dist/SaimoTV-Windows.zip" "build/release/SaimoTV-Windows.zip"

# O APK do celular é montado à parte (Expo) e copiado para cá antes de publicar.
if [ -f "../Saimo-Cell-V2/android/app/build/outputs/apk/release/app-release.apk" ]; then
  cp "../Saimo-Cell-V2/android/app/build/outputs/apk/release/app-release.apk" "build/release/SaimoCell.apk"
fi

echo "==> conferindo as assinaturas"
APKSIGNER=$(ls "$HOME"/Library/Android/sdk/build-tools/*/apksigner | tail -1)
for apk in build/release/*.apk; do
  echo "    $(basename "$apk"): $("$APKSIGNER" verify --print-certs "$apk" 2>/dev/null \
    | grep -m1 -o 'SHA-256 digest: .*')"
done

cell=""
[ -f "build/release/SaimoCell.apk" ] && cell="build/release/SaimoCell.apk"

notas="build/release/NOTAS.md"
if [ ! -f "$notas" ]; then
  {
    echo "## Saimo TV $versao"
    echo
    git log --pretty="- %s" "$(git describe --tags --abbrev=0 2>/dev/null || echo HEAD~10)"..HEAD \
      | grep -v "^- Merge" || true
  } > "$notas"
fi

extra=""
for arg in "$@"; do
  [ "$arg" = "--rascunho" ] && extra="--draft"
done

echo "==> publicando v$versao"
gh release create "v$versao" \
  --title "Saimo TV $versao" \
  --notes-file "$notas" \
  $extra \
  build/release/SaimoTV.dmg build/release/SaimoTV.apk \
  build/release/SaimoTV-Windows.zip \
  ${cell:-}

echo "pronto: https://github.com/gabrielsaimo/SaimoPlayer/releases/tag/v$versao"
