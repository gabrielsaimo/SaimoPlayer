import urllib.request, time
from concurrent.futures import ThreadPoolExecutor

def get(i):
    try:
        req = urllib.request.Request(f"https://pipocacine.lat/embed/{738231+i}", headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=5) as r:
            return r.status
    except Exception as e:
        return getattr(e, 'code', type(e).__name__)

with ThreadPoolExecutor(2) as ex:
    res = list(ex.map(get, range(50)))

from collections import Counter
print("2 workers:", Counter(res))
