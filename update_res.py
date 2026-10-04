import urllib.request, json, re

AGENTE = "Mozilla/5.0"
PIPO_BASE = "https://pipocacine.lat"
class NoRedir(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None
opener = urllib.request.build_opener(NoRedir())

tmdb = 1423191
api_url = f"{PIPO_BASE}/api/embed/{tmdb}"
r = urllib.request.urlopen(urllib.request.Request(api_url, headers={"User-Agent": AGENTE}))
data = json.loads(r.read())
embed_url = data.get("embed_url", f"{PIPO_BASE}/embed/{tmdb}")

r2 = urllib.request.urlopen(urllib.request.Request(embed_url, headers={"User-Agent": AGENTE}))
html = r2.read().decode("utf-8")
match = re.search(r'var videoSources\s*=\s*(\[.*?\]);', html)
sources = json.loads(match.group(1))

resultados = {}
for s in sources:
    label = str(s.get("label", "")).upper()
    src = str(s.get("src", ""))
    if not src or "Indisponível" in label: continue
    idioma = "dub" if "DUB" in label else "leg"
    url_redir = src if src.startswith("http") else f"{PIPO_BASE}{src}"
    
    req_redir = urllib.request.Request(url_redir, headers={"User-Agent": AGENTE, "Referer": embed_url})
    try:
        res = opener.open(req_redir, timeout=10)
    except urllib.error.HTTPError as e:
        if e.code in (301, 302, 303, 307):
            location = e.headers.get("Location")
            if location: resultados[idioma] = location

print("ACHOU:", resultados)

if resultados:
    # Append to vod/pipocacine/links-filmes.txt
    campos = ["Resident Evil (2026)"]
    for lang in ("dub", "leg"):
        if lang in resultados:
            campos.append(f"{lang}={resultados[lang]}")
    with open("vod/pipocacine/links-filmes.txt", "a") as f:
        f.write("\t".join(campos) + "\n")
    print("Salvo em vod/pipocacine/links-filmes.txt!")
