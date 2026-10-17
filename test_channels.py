import requests
import concurrent.futures

channels = [
    # Server 1 format (lowercase, simple names usually)
    "espn2", "espn3", "espn4", "espn5", "espn6", "espnextra",
    "sportv", "sportv2", "sportv3", "sportv4",
    "premiere", "premiere2", "premiere3", "premiere4", "premiereclubes",
    "bandsports", "foxsports", "foxsports2", "globo", "sbt", "record", "band",
    "tnt", "space", "hbo", "telecine", "combate",
    
    # Server 2 format (UPPERCASE with _BRASIL or _HD)
    "ESPN_2_BRASIL", "ESPN_3_BRASIL", "ESPN_4_BRASIL", "ESPN_5_BRASIL", "ESPN_EXTRA",
    "ESPN_2", "ESPN_3", "ESPN_4", "ESPN_5",
    "SPORTV_1", "SPORTV_2", "SPORTV_3", "SPORTV",
    "SPORTV_1_HD", "SPORTV_2_HD", "SPORTV_3_HD",
    "PREMIERE_1", "PREMIERE_2", "PREMIERE_3", "PREMIERE_4", "PREMIERE_CLUBES",
    "PREMIERE_1_HD", "PREMIERE_2_HD", "PREMIERE_CLUBES_HD",
    "BANDSPORTS", "BANDSPORTS_HD", "COMBATE", "COMBATE_HD",
    "GLOBO_SP", "GLOBO_RJ", "SBT", "RECORD", "BAND",
    "TNT_HD", "SPACE_HD", "TELECINE_PREMIUM", "TELECINE_ACTION", "TELECINE_TOUCH",
    
    # Server 3 format
    "ESPN_HD", "ESPN2_HD", "ESPN3_HD", "ESPN5_HD", "ESPN6_HD",
    "SPORTV_HD", "SPORTV2_HD", "SPORTV3_HD",
    "PREMIERE_HD", "PREMIERE2_HD", "PREMIERE3_HD",
    "BANDSPORTS_HD", "FOX_SPORTS_HD", "COMBATE_HD",
]

servers = [
    "https://16-5-0-235.sslip.io/{}/index.m3u8",
    "http://45.162.64.114/{}/index.m3u8",
    "http://138.204.86.4:8080/{}/index.m3u8"
]

results = []

def check_url(url):
    try:
        # Check headers first to avoid downloading large files
        r = requests.get(url, timeout=3, allow_redirects=True)
        if r.status_code == 200 and "#EXTM3U" in r.text:
            return url
    except:
        pass
    return None

urls_to_check = []
for s in servers:
    for c in set(channels):
        urls_to_check.append(s.format(c))

with concurrent.futures.ThreadPoolExecutor(max_workers=20) as executor:
    futures = {executor.submit(check_url, url): url for url in urls_to_check}
    for future in concurrent.futures.as_completed(futures):
        res = future.result()
        if res:
            print("FOUND:", res)

