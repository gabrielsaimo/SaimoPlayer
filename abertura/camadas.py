"""Separa o AppIcon em camadas para a splash: fundo, cartão, TV, S, play, antena, letras."""
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
SRC = Image.open(__import__('os').environ['ARTE']).convert('RGB')
A = np.asarray(SRC).astype(np.float32)
H, W = A.shape[:2]

def _caixa(a, r, eixo):
    r = max(1, int(r)); n = a.shape[eixo]
    pad = [(0, 0)] * a.ndim; pad[eixo] = (r + 1, r)
    c = np.cumsum(np.pad(a, pad, mode='edge'), axis=eixo)
    sl_hi = [slice(None)] * a.ndim; sl_lo = [slice(None)] * a.ndim
    sl_hi[eixo] = slice(2 * r + 1, 2 * r + 1 + n); sl_lo[eixo] = slice(0, n)
    return (c[tuple(sl_hi)] - c[tuple(sl_lo)]) / (2 * r + 1)

def blur(arr, r):
    """Gaussiana aproximada: três passadas de caixa em cada eixo."""
    b = max(1, round(r * 0.9))
    out = arr.astype(np.float64)
    for _ in range(3):
        out = _caixa(_caixa(out, b, 0), b, 1)
    return out.astype(np.float32)

def inpaint(img, buraco):
    """Preenche onde buraco=1 com a média dos vizinhos válidos, em várias escalas."""
    w = (buraco < 0.5).astype(np.float32)
    out = img.copy(); preenchido = w.copy()
    for r in (2, 4, 8, 16, 32, 64, 128):
        num = blur(img * w[..., None], r); den = blur(w, r)
        ok = (den > 0.02) & (preenchido < 0.5)
        out[ok] = (num[ok] / den[ok][:, None])
        preenchido[ok] = 1
    return out

def mascara_desenho(fn):
    m = Image.new('L', (W, H), 0); fn(ImageDraw.Draw(m)); return np.asarray(m).astype(np.float32) / 255

# cartão: bounds medidos
X0, Y0, X1, Y1 = 129, 130, 894, 894
RAIO = round((X1 - X0) * 0.19)
cartao = mascara_desenho(lambda d: d.rounded_rectangle((X0, Y0, X1, Y1), RAIO, fill=255))

# o que não é cartão branco dentro dele: cor ou escuro
mx, mn = A.max(-1), A.min(-1)
sat = (mx - mn) / np.maximum(mx, 1)
lum = A @ np.array([0.299, 0.587, 0.114])
interior = mascara_desenho(lambda d: d.rounded_rectangle((X0 + 18, Y0 + 18, X1 - 18, Y1 - 18), RAIO - 18, fill=255))
tinta = ((sat > 0.12) | (lum < 190)) & (interior > 0.5)
tinta = np.asarray(Image.fromarray((tinta * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(7))).astype(np.float32) / 255
tinta_suave = np.clip(blur(tinta, 1.2) * 1.3, 0, 1)

# cartão liso: as áreas do símbolo e do texto inteiras (com sombras) preenchidas
# a partir do cartão em volta; só fica de fora o branco, que é liso
areas = mascara_desenho(lambda d: (d.rounded_rectangle((285, 180, 740, 640), 60, fill=255),
                                   d.rounded_rectangle((230, 615, 800, 880), 60, fill=255)))
# Superfície do cartão: polinômio de grau 4 ajustado no branco em volta
validos = (interior > 0.5) & (areas < 0.01) & (sat < 0.12) & (lum > 190)
yy, xx = np.mgrid[0:H, 0:W].astype(np.float64)
u, v = (xx - 512) / 512, (yy - 512) / 512
termos = [u**i * v**j for i in range(5) for j in range(5 - i)]
M = np.stack([t[validos] for t in termos], 1)
liso = np.empty_like(A)
for c in range(3):
    coef, *_ = np.linalg.lstsq(M, A[..., c][validos], rcond=None)
    liso[..., c] = sum(k * t for k, t in zip(coef, termos))
areas = np.clip(blur(areas, 10), 0, 1) * (areas > 0)
liso = liso * areas[..., None] + A * (1 - areas[..., None])
# tinta = o que difere do cartão liso (pega as sombras suaves também)
dif = np.abs(A - liso).max(-1)
tinta_suave = np.clip((dif - 3) / 22, 0, 1) * areas
tinta = (tinta_suave > 0.5).astype(np.float32)

# regiões
def zona(fn): return mascara_desenho(fn)
S_PATH = [(540,242),(490,250),(445,275),(415,315),(412,355),(440,390),(495,410),(560,430),(605,460),(615,500),(590,540),(545,570),(490,592)]
s_zona = zona(lambda d: (d.line(S_PATH, fill=255, width=64, joint='curve'), [d.ellipse((x-32,y-32,x+32,y+32), fill=255) for x,y in (S_PATH[0], S_PATH[-1])]))
TRI = [(477,382),(477,473),(561,425)]
tri_zona = zona(lambda d: d.polygon([(470,372),(470,484),(572,425)], fill=255))
ant_zona = zona(lambda d: (d.line([(405,214),(455,272)], fill=255, width=16), d.ellipse((392,201,418,227), fill=255)))
simbolo_zona = zona(lambda d: d.rectangle((300, 195, 725, 625), fill=255))
texto_zona = zona(lambda d: d.rectangle((230, 625, 800, 870), fill=255))

def camada(rgb, alfa, nome):
    a = np.clip(alfa, 0, 1)
    img = np.dstack([np.clip(rgb, 0, 255), a * 255]).astype(np.uint8)
    Image.fromarray(img, 'RGBA').save(f'{nome}.png')

tinta_sim = tinta_suave * simbolo_zona
# TV (moldura e tela) por baixo: tinta do símbolo sem S, play e antena, buracos preenchidos com a própria TV
fora_tv = np.clip(s_zona + tri_zona + ant_zona, 0, 1)
tv_alfa = tinta_sim * (1 - ant_zona)
tv_rgb = inpaint(A, np.clip(fora_tv * simbolo_zona + (1 - tinta) * 0, 0, 1))
# a TV termina no retângulo da moldura: fora dele, só o que é antena/S (que não é TV)
tv_ret = zona(lambda d: d.rounded_rectangle((312, 289, 713, 563), 26, fill=255))
camada(tv_rgb, tv_alfa * tv_ret, 'tv')
# S: original na zona do S, play preenchido com o próprio S
s_rgb = inpaint(A, tri_zona)
camada(s_rgb, tinta_sim * s_zona, 's')
camada(A, tinta_sim * tri_zona * (1 - 0), 'play')
camada(A, tinta_sim * ant_zona * (1 - tv_ret), 'antena')
# texto
tinta_txt = tinta_suave * texto_zona
camada(A, tinta_txt, 'texto')
# cartão liso recortado e fundo
camada(liso, cartao, 'cartao')
fundo = A.copy()
camada(fundo, np.ones((H, W)), 'original')

# colunas das letras de "Saimo" (y 630..760) e "TV" (y 775..860)
def colunas(y0, y1, x0, x1):
    faixa = (lum[y0:y1, x0:x1] < 140).any(0)
    out = []; i = 0
    while i < len(faixa):
        if faixa[i]:
            j = i
            while j < len(faixa) and faixa[j]: j += 1
            out.append((x0 + i, x0 + j)); i = j
        else: i += 1
    return out
print('Saimo', colunas(630, 760, 230, 800))
print('TV', colunas(775, 865, 560, 800))
print('linhas Saimo', np.where((lum[600:900, 240:780] < 140).any(1))[0][[0, -1]] + 600)
