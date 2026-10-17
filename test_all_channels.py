import requests
import concurrent.futures

channel_map = {
    # Catalog Name : list of possible slugs
    "Telecine Premium": ["telecinepremium", "TELECINE_PREMIUM", "TELECINE_PREMIUM_HD"],
    "Telecine Action": ["telecineaction", "TELECINE_ACTION", "TELECINE_ACTION_HD"],
    "Telecine Touch": ["telecinetouch", "TELECINE_TOUCH", "TELECINE_TOUCH_HD"],
    "Telecine Fun": ["telecinefun", "TELECINE_FUN", "TELECINE_FUN_HD"],
    "Telecine Pipoca": ["telecinepipoca", "TELECINE_PIPOCA", "TELECINE_PIPOCA_HD"],
    "Telecine Cult": ["telecinecult", "TELECINE_CULT", "TELECINE_CULT_HD"],
    "Megapix": ["megapix", "MEGAPIX", "MEGAPIX_HD"],
    "Universal TV": ["universal", "UNIVERSAL", "UNIVERSAL_HD", "UNIVERSAL_TV"],
    "Warner Channel": ["warner", "WARNER", "WARNER_HD", "WARNER_CHANNEL"],
    "Sony Movies": ["sony", "SONY", "SONY_HD"],
    "AXN": ["axn", "AXN", "AXN_HD"],
    "History": ["history", "HISTORY", "HISTORY_HD", "HISTORY_CHANNEL"],
    "History 2": ["history2", "HISTORY_2", "HISTORY2_HD"],
    "National Geographic": ["natgeo", "NATGEO", "NAT_GEO", "NATGEO_HD", "NATIONAL_GEOGRAPHIC"],
    "CNN Brasil": ["cnn", "cnnbrasil", "CNN", "CNN_BRASIL", "CNN_BRASIL_HD"],
    "GloboNews": ["globonews", "GLOBONEWS", "GLOBONEWS_HD", "GLOBO_NEWS"],
    "Multishow": ["multishow", "MULTISHOW", "MULTISHOW_HD"],
    "GNT": ["gnt", "GNT", "GNT_HD"],
    "VIVA": ["viva", "VIVA", "VIVA_HD"],
    "Canal OFF": ["off", "OFF", "OFF_HD", "CANAL_OFF"],
    "BIS": ["bis", "BIS", "BIS_HD", "CANAL_BIS"],
    "Mais na Tela": ["maisglobosat", "MAIS_GLOBOSAT", "MAIS_NA_TELA"],
    "Canal Brasil": ["canalbrasil", "CANAL_BRASIL", "CANAL_BRASIL_HD"],
    "A&E": ["ae", "A_E", "A_E_HD"],
    "AMC": ["amc", "AMC", "AMC_HD"],
    "Cinemax": ["cinemax", "CINEMAX", "CINEMAX_HD"],
    "Paramount Network": ["paramount", "PARAMOUNT", "PARAMOUNT_HD"],
    "Comedy Central": ["comedycentral", "COMEDY_CENTRAL", "COMEDY_CENTRAL_HD", "COMEDY"],
    "MTV": ["mtv", "MTV", "MTV_HD"],
    "Nickelodeon": ["nickelodeon", "nick", "NICKELODEON", "NICKELODEON_HD", "NICK_HD"],
    "Cartoon Network": ["cartoon", "cartoonnetwork", "CARTOON_NETWORK", "CARTOON_NETWORK_HD", "CARTOON"],
    "Discovery Kids": ["discoverykids", "DISCOVERY_KIDS", "DISCOVERY_KIDS_HD"],
    "Boomerang": ["boomerang", "BOOMERANG", "BOOMERANG_HD"],
    "Disney Channel": ["disney", "disneychannel", "DISNEY_CHANNEL", "DISNEY_CHANNEL_HD", "DISNEY"],
    "RedeTV!": ["redetv", "REDETV", "REDETV_HD", "REDE_TV"],
    "Band News": ["bandnews", "BANDNEWS", "BAND_NEWS", "BANDNEWS_HD"],
    "Globo SP": ["globosp", "GLOBO_SP", "GLOBO_SP_HD"],
    "Globo RJ": ["globorj", "GLOBO_RJ", "GLOBO_RJ_HD"],
    "Globo": ["globo", "GLOBO", "GLOBO_HD"],
    "SBT": ["sbt", "SBT", "SBT_HD"],
    "Record": ["record", "RECORD", "RECORD_HD", "RECORD_TV"],
    "Band": ["band", "BAND", "BAND_HD"],
    
    # We already have ESPN/SporTV/Premiere/Combate/BandSports/TNT/Space/HBO/Discovery from before, 
    # but let's re-add some to ensure we capture all combinations just in case.
    "HBO Plus": ["hboplus", "HBO_PLUS", "HBO_PLUS_HD"],
    "HBO Family": ["hbofamily", "HBO_FAMILY", "HBO_FAMILY_HD"],
    "HBO Signature": ["hbosignature", "HBO_SIGNATURE", "HBO_SIGNATURE_HD"],
    "HBO Mundi": ["hbomundi", "HBO_MUNDI", "HBO_MUNDI_HD"],
    "HBO Pop": ["hbopop", "HBO_POP", "HBO_POP_HD"],
    "HBO Xtreme": ["hboxtreme", "HBO_XTREME", "HBO_XTREME_HD"],
    "Premiere 5": ["premiere5", "PREMIERE_5", "PREMIERE5_HD", "PREMIERE_5_HD"],
    "Premiere 6": ["premiere6", "PREMIERE_6", "PREMIERE6_HD", "PREMIERE_6_HD"],
    "Premiere 7": ["premiere7", "PREMIERE_7", "PREMIERE7_HD", "PREMIERE_7_HD"],
    "Premiere 8": ["premiere8", "PREMIERE_8", "PREMIERE8_HD", "PREMIERE_8_HD"],
    "SporTV 4": ["sportv4", "SPORTV_4", "SPORTV4_HD"],
    
    "Discovery Turbo": ["discoveryturbo", "DISCOVERY_TURBO", "DISCOVERY_TURBO_HD"],
    "Discovery Science": ["discoveryscience", "DISCOVERY_SCIENCE", "DISCOVERY_SCIENCE_HD"],
    "Discovery Home & Health": ["discoveryhh", "discoveryhomeandhealth", "DISCOVERY_H_H", "DISCOVERY_HOME_HEALTH", "DISCOVERY_HOME_HEALTH_HD"],
    "Discovery ID": ["discoveryid", "investigationdiscovery", "DISCOVERY_ID", "DISCOVERY_ID_HD", "ID", "ID_HD"],
    "Discovery Theater": ["discoverytheater", "DISCOVERY_THEATER", "DISCOVERY_THEATER_HD"],
    "Discovery World": ["discoveryworld", "DISCOVERY_WORLD", "DISCOVERY_WORLD_HD"],
}

servers = [
    "https://16-5-0-235.sslip.io/{}/index.m3u8",
    "http://45.162.64.114/{}/index.m3u8",
    "http://138.204.86.4:8080/{}/index.m3u8"
]

def check_url(url, catalog_name):
    try:
        r = requests.get(url, timeout=3, allow_redirects=True)
        if r.status_code == 200 and "#EXTM3U" in r.text:
            return (catalog_name, url)
    except:
        pass
    return None

urls_to_check = []
for catalog_name, slugs in channel_map.items():
    for slug in slugs:
        for s in servers:
            urls_to_check.append((s.format(slug), catalog_name))

results = []
with concurrent.futures.ThreadPoolExecutor(max_workers=30) as executor:
    futures = {executor.submit(check_url, url, cname): (url, cname) for url, cname in urls_to_check}
    for future in concurrent.futures.as_completed(futures):
        res = future.result()
        if res:
            results.append(res)
            print("FOUND:", res)

# Write results to file so we can consume them in the next step
with open("discovered_more.txt", "w") as f:
    for cname, url in results:
        f.write(f"{cname}|{url}\n")
