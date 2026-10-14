#!/bin/bash
# Refaz a abertura animada a partir do AppIcon.png: camadas, página e os dois vídeos.
#   ./gerar.sh      (precisa de python3 com Pillow e numpy, node 22+, Chrome e ffmpeg)
set -euo pipefail
cd "$(dirname "$0")"
T=$(mktemp -d)
export ARTE="$PWD/../AppIcon.png"
cp modelo.html camadas.py gravar.mjs "$T/"
( cd "$T"
  python3 camadas.py >/dev/null
  python3 - <<'PY'
from PIL import Image
import numpy as np, base64, io, json
orig = Image.open('original.png').convert('RGBA')
final = orig.copy(); final.putalpha(Image.open('cartao.png').split()[3]); final.save('final.png')
out = {}
for n in ['cartao', 'final', 'tv', 's', 'play', 'antena', 'texto']:
    im = Image.open(n + '.png'); a = np.asarray(im.split()[3]); ys, xs = np.where(a > 2)
    x0, y0, x1, y1 = xs.min(), ys.min(), xs.max() + 1, ys.max() + 1
    b = io.BytesIO(); im.crop((x0, y0, x1, y1)).save(b, 'WEBP', quality=92, method=6)
    out[n] = dict(x=int(x0), y=int(y0), w=int(x1 - x0), h=int(y1 - y0),
                  src='data:image/webp;base64,' + base64.b64encode(b.getvalue()).decode())
open('abertura-saimo.html', 'w').write(open('modelo.html').read().replace('__CAMADAS__', json.dumps(out)))
PY
  node gravar.mjs 1920 1080 60 quadros-h & node gravar.mjs 1080 1920 60 quadros-v & wait
  for o in h v; do
    ffmpeg -loglevel error -y -framerate 60 -i quadros-$o/q%04d.png -c:v libx264 -profile:v main -level 4.1 \
      -pix_fmt yuv420p -crf 17 -preset slow -movflags +faststart abertura-$o.mp4
  done )
cp "$T/abertura-h.mp4" "$T/abertura-v.mp4" "$T/abertura-saimo.html" .
rm -rf "$T"
echo "abertura-h.mp4 (1920x1080), abertura-v.mp4 (1080x1920) e abertura-saimo.html prontos"
