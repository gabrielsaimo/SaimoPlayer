import requests
import concurrent.futures

bases = ["SPORTV", "PREMIERE", "PFC", "FOX", "DISCOVERY"]
suffixes = ["", "_HD", "_FHD", "1", "2", "3", "4", "5", "6", "1_HD", "2_HD", "3_HD", "4_HD", "5_HD", "_1", "_2", "_3", "_4", "_5", "_1_HD", "_2_HD", "_3_HD", "_4_HD", "_5_HD", "SPORTS", "SPORTS_2", "_SPORTS", "_SPORTS_2"]

servers = [
    "http://45.162.64.114/{}/index.m3u8",
    "http://138.204.86.4:8080/{}/index.m3u8",
]

def check_url(url):
    try:
        r = requests.get(url, timeout=3, allow_redirects=True)
        if r.status_code == 200 and "#EXTM3U" in r.text:
            return url
    except:
        pass
    return None

urls_to_check = set()
for s in servers:
    for b in bases:
        for suf in suffixes:
            urls_to_check.add(s.format(b + suf))

urls_to_check = list(urls_to_check)

with concurrent.futures.ThreadPoolExecutor(max_workers=30) as executor:
    futures = {executor.submit(check_url, url): url for url in urls_to_check}
    for future in concurrent.futures.as_completed(futures):
        res = future.result()
        if res:
            print("FOUND:", res)

