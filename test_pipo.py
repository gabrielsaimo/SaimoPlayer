import urllib.request, json, re

# 1. API probe
req = urllib.request.Request("https://pipocacine.lat/api/embed/738231", headers={"User-Agent": "Mozilla/5.0"})
with urllib.request.urlopen(req) as r:
    data = json.loads(r.read())
print("API:", data)

# 2. Get embed
req = urllib.request.Request("https://pipocacine.lat/embed/738231", headers={"User-Agent": "Mozilla/5.0"})
with urllib.request.urlopen(req) as r:
    html = r.read().decode()

sources = re.search(r'var videoSources\s*=\s*(\[.*?\]);', html)
if sources:
    srcs = json.loads(sources.group(1))
    print("Sources:", srcs)
    for s in srcs:
        u = s['src']
        if not u.startswith('http'):
            u = "https://pipocacine.lat" + u
        print("Following:", u)
        # get redirect
        class NoRedir(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, req, fp, code, msg, headers, newurl):
                return None
        opener = urllib.request.build_opener(NoRedir())
        try:
            res = opener.open(urllib.request.Request(u, headers={"User-Agent": "Mozilla/5.0"}))
            print("No redirect?", res.status)
        except urllib.error.HTTPError as e:
            if e.code in (301, 302, 303, 307):
                print("Final URL:", e.headers.get('Location'))
            else:
                print("Error", e.code)
