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
JAVA17="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"

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

  CELL_DIR="../Saimo-Cell-V2"
  if [ -d "$CELL_DIR" ]; then
    python3 - "$CELL_DIR" "$versao" "$codigo" <<'PY'
import sys, json

cell_dir, versao, codigo = sys.argv[1], sys.argv[2], int(sys.argv[3])
pkg_path = f"{cell_dir}/package.json"
try:
    with open(pkg_path, "r", encoding="utf-8") as f:
        pkg = json.load(f)
    pkg["version"] = versao
    with open(pkg_path, "w", encoding="utf-8") as f:
        json.dump(pkg, f, indent=2)
        f.write("\n")
except Exception as e:
    print(f"Aviso ao atualizar package.json do celular: {e}")

app_path = f"{cell_dir}/app.json"
try:
    with open(app_path, "r", encoding="utf-8") as f:
        app = json.load(f)
    expo = app.get("expo", {})
    expo["version"] = versao
    if "ios" in expo:
        expo["ios"]["buildNumber"] = versao
    if "android" in expo:
        expo["android"]["versionCode"] = codigo
    with open(app_path, "w", encoding="utf-8") as f:
        json.dump(app, f, indent=2)
        f.write("\n")
except Exception as e:
    print(f"Aviso ao atualizar app.json do celular: {e}")
PY
    if [ -f "$CELL_DIR/android/app/build.gradle" ]; then
      sed -i '' "s/versionName \".*\"/versionName \"$versao\"/" "$CELL_DIR/android/app/build.gradle"
      sed -i '' "s/versionCode .*/versionCode $codigo/" "$CELL_DIR/android/app/build.gradle"
    fi
  fi

  if [ -f "../SaimoWin/Cargo.toml" ]; then
    sed -i '' "s/^version = \".*\"/version = \"$versao\"/" "../SaimoWin/Cargo.toml"
  fi
  if [ -f "../Saimo-TV/package.json" ]; then
    python3 - "../Saimo-TV/package.json" "$versao" <<'PY'
import sys, json
p, v = sys.argv[1], sys.argv[2]
with open(p, "r", encoding="utf-8") as f:
    d = json.load(f)
d["version"] = v
with open(p, "w", encoding="utf-8") as f:
    json.dump(d, f, indent=2)
    f.write("\n")
PY
  fi
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

if [ -d "../Saimo-Cell-V2/android" ]; then
  echo "==> montando o APK do celular"
  ( cd ../Saimo-Cell-V2/android && JAVA_HOME="$JAVA17" ANDROID_HOME="$HOME/Library/Android/sdk" \
    ./gradlew assembleRelease -q )
  cp "../Saimo-Cell-V2/android/app/build/outputs/apk/release/app-release.apk" "build/release/SaimoCell.apk"
elif [ -f "../Saimo-Cell-V2/android/app/build/outputs/apk/release/app-release.apk" ]; then
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
    echo "Novidades da versão $versao:"
    echo
    git log --pretty="• %s" "$(git describe --tags --abbrev=0 2>/dev/null || echo HEAD~10)"..HEAD \
      | grep -v "• Merge" \
      | sed -E 's/• [a-z]+(\([^)]+\))?: /• /' || true
  } > "$notas"
fi

extra=""
for arg in "$@"; do
  [ "$arg" = "--rascunho" ] && extra="--draft"
done

echo "==> publicando v$versao"
# Onde os arquivos ficam para baixar. O principal vem primeiro e é o que o
# versao.json anuncia; o legado (remote `legado`, o GitHub de antes da mudança)
# recebe o mesmo release enquanto houver app 2.3.x procurando por lá — é a ponte
# que leva essas instalações para uma versão que lê o versao.json.
#   scripts/release-repo.txt  (opcional) "dono/repo" público só com os downloads
#   SAIMO_REPO_RELEASE        o mesmo, por variável de ambiente
repo_de() {
  git remote get-url "$1" 2>/dev/null | sed -E 's#^(https://github.com/|git@github.com:)##; s#\.git$##'
}
REPO_PRINCIPAL="${SAIMO_REPO_RELEASE:-}"
[ -z "$REPO_PRINCIPAL" ] && [ -f scripts/release-repo.txt ] && REPO_PRINCIPAL="$(tr -d ' \r\n' < scripts/release-repo.txt)"
[ -z "$REPO_PRINCIPAL" ] && REPO_PRINCIPAL="$(repo_de origin)"
REPO_LEGADO="$(repo_de legado)"
repos="$REPO_PRINCIPAL"
[ -n "$REPO_LEGADO" ] && [ "$REPO_LEGADO" != "$REPO_PRINCIPAL" ] && repos="$repos $REPO_LEGADO"

for repo in $repos; do
  echo "    -> $repo"
  gh release create "v$versao" --repo "$repo" \
    --title "Saimo TV $versao" \
    --notes-file "$notas" \
    $extra \
    build/release/SaimoTV.dmg build/release/SaimoTV.apk \
    build/release/SaimoTV-Windows.zip \
    ${cell:-}
done

# O que os apps leem para saber que há versão nova (e de onde baixar). Só depois
# de os arquivos existirem: um app que visse o versao.json antes encontraria
# um link quebrado. Rascunho não anuncia nada.
if [ -z "$extra" ]; then
  echo "==> anunciando em versao.json"
  python3 - "$versao" "$REPO_PRINCIPAL" "$notas" <<'PY'
import hashlib, json, sys, datetime, pathlib
versao, repo, notas = sys.argv[1], sys.argv[2], pathlib.Path(sys.argv[3])
pasta = pathlib.Path("build/release")
def arq(nome):
    f = pasta / nome
    if not f.exists():
        return None
    h = hashlib.sha256()
    with f.open("rb") as fh:
        for bloco in iter(lambda: fh.read(1 << 20), b""):
            h.update(bloco)
    return {"nome": nome, "url": f"https://github.com/{repo}/releases/download/v{versao}/{nome}",
            "bytes": f.stat().st_size, "sha256": h.hexdigest()}
arquivos = {k: arq(n) for k, n in [("tvbox", "SaimoTV.apk"), ("celular", "SaimoCell.apk"),
                                    ("mac", "SaimoTV.dmg"), ("windows", "SaimoTV-Windows.zip")]}
doc = {"versao": versao, "tag": f"v{versao}",
       "publicadoEm": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
       "notas": notas.read_text(encoding="utf-8") if notas.exists() else "",
       "arquivos": {k: v for k, v in arquivos.items() if v}}
pathlib.Path("versao.json").write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
  # Só este arquivo vai no commit: o resto da árvore é trabalho em andamento.
  git add versao.json
  git commit -q -m "versao.json: $versao" -- versao.json || true
  git push -q origin HEAD || echo "aviso: não consegui empurrar o versao.json (o publicar abaixo usa o arquivo local)"
  ./scripts/publicar_catalogos.sh canais --nao-falhar
fi

echo "pronto: https://github.com/$REPO_PRINCIPAL/releases/tag/v$versao"
