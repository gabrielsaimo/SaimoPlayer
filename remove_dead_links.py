import re

dead_urls = {
    "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/adultswim/__index.m3u8?sv=10&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786290776-nJUghGmLjJRyjF0SPqaBgidgAOJiU3S97xh4hE2NE1I%3D",
    "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/animalplanet/__index.m3u8?sv=12&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786291576-cljMHYyJK3iEhKhqrwvs2DVTA0kXJMj71miu9g%2Bmv9w%3D",
    "https://_______________________________________________________________.null-null.shop/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/cartoon/__index.m3u8?sv=84&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1787689309-%2FssbacY0lf%2FaEdVkBHNWxAAcCUGhU2J8y9NgGnE440g%3D",
    "https://dfr80qz435crc.cloudfront.net/MNOP/Amagi/Caze/Caze_TV_BR/Caze_TV.m3u8",
    "https://video46.mais.uol.com.br/live/281.mpd",
    "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/sportv1/__index.m3u8?sv=159&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786408554-MK0K7%2F0RIabb2i7ktFkDI1P2aEeyuwRUwvOxauQ5e1c%3D",
    "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/telecineaction/__index.m3u8?sv=191&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786409777-6357MK63%2ByysgfFiZNfFK3mJeGmSWEVxX3ET2vato6g%3D",
    "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/telecinepipoca/__index.m3u8?sv=58&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786492376-lVHrv7GkGdIq6AAU1c65luWS5GerVjL4DwRV0Ajf6x8%3D",
    "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/telecinepremium/__index.m3u8?sv=79&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786292168-FKlxVeuJhXev%2F1KUUB5nexfVY5bv0OpgfJecX3Kk9q0%3D",
    "https://p12-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/foodnetwork/__index.m3u8?sv=154&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1787510790-oLglpNJTCmF4dMfrjs1DtdFDeq5mTV9g6bSMLrUWnT0%3D",
    "https://p12-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/cinemax/__index.m3u8?sv=66&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1787510316-X70RycSXFaJIDV%2BwMOJkE%2Bdz%2FmNYSqg%2B2TU9KVeKl4Y%3D",
    "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/combate/__index.m3u8?sv=180&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786317841-kasstfdIhiqSElnrlbwkM4AVYt3R8NSVQYvsaAz2vmc%3D",
    "https://p12-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/discoveryhomeihealth/__index.m3u8?sv=29&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1787510491-LXPCJR%2BIA5IcHXUlV%2FZ9bcvbmd%2FTzc2XQwKhkl1c7wc%3D",
    "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/espn/__index.m3u8?sv=12&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786318392-QvKT%2FUp7bZQSZYJz6P10ssTqi7CQZwlTquxwquyZKOM%3D",
    "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/espn2/__index.m3u8?sv=141&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786318445-zhWacyLIG8lLoYvlDCss2l3Uzb6bPtJB7boGnCgWXvI%3D",
    "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/espn4/__index.m3u8?sv=166&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786318524-FDNFOsKiw6lTQJ35mV3KKuwHL8%2Bg%2FeKqmq3oedHtH9s%3D",
    "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/hbo/__index.m3u8?sv=132&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786492099-MUqmGUjva9IbHeQRUp%2BYUm3aOWZlUj6pQOchl2bOPoc%3D",
    "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/hbo2/__index.m3u8?sv=130&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786318898-K3ZqHfTFH1G%2BGiR8Cm9Rj%2F97Hz%2FArnNn7isruGQHqK0%3D",
    "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/hbofamily/__index.m3u8?sv=110&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786318990-VHr%2FSKUQMB04QL6bqlaqNJUjBnjWuqn%2BtRMC3XY30uw%3D",
    "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/tnt/__index.m3u8?sv=86&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786320015-pLkZ%2FNdlgXV4jqtDYTJ51nEkLG8WRJkACfkgm5UMYF8%3D",
    "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/tntseries/__index.m3u8?sv=5&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786320066-hcnuxiV0uoL54pSnZai999RtJv4kuUlXop3OpOigZek%3D",
    "http://46.151.196.223:14654",
    "http://79.127.243.211:14653",
    "http://79.127.243.211:14657",
    "http://79.127.243.211:14658",
    "https://dfr80qz435crc.cloudfront.net/MNOP/Amagi/Caze/Caze_TV_BR/1080p-vtt/index.m3u8",
    "http://79.127.243.211:14697",
    "http://46.151.196.223:14124",
    "http://46.151.196.223:14126",
    "http://79.127.243.211:14565",
    "http://46.151.196.223:14636",
    "http://79.127.243.211:14569",
    "http://79.127.243.211:14573",
    "http://79.127.243.211:14449",
    "http://79.127.243.211:14506",
    "http://46.151.196.223:14457",
    "http://46.151.196.223:14197",
    "http://79.127.243.211:14497",
    "http://46.151.196.223:14586",
    "http://79.127.243.211:14501",
    "http://46.151.196.223:14587",
    "http://46.151.196.223:14056",
    "http://46.151.196.223:14603",
    "http://46.151.196.223:14607",
    "http://46.151.196.223:14686",
    "http://79.127.243.211:14623",
    "http://46.151.196.223:14648",
}

# Clean canais.txt
with open("canais.txt", "r") as f:
    canais_lines = f.readlines()

new_canais = []
i = 0
while i < len(canais_lines):
    line = canais_lines[i]
    if line.startswith("#EXTINF"):
        extinf = line
        i += 1
        url = canais_lines[i].strip() if i < len(canais_lines) else ""
        if url not in dead_urls:
            new_canais.append(extinf)
            new_canais.append(url + "\n")
    else:
        new_canais.append(line)
    i += 1

with open("canais.txt", "w") as f:
    f.writelines(new_canais)

# Clean catalogo.txt
with open("catalogo.txt", "r") as f:
    content = f.read()
    
# We parse blocks separated by double newlines or similar
blocks = re.split(r'\n(?=canal: )', content)
if not blocks[0].startswith("canal:"):
    print("Warning: First block doesn't start with canal:")

new_blocks = []
for block in blocks:
    if not block.strip(): continue
    if not block.startswith("canal:"):
        block = "canal: " + block
    
    # Extract sources
    source_blocks = re.split(r'(?=fonte: )', block)
    
    header_part = source_blocks[0]
    kept_sources = []
    
    for src in source_blocks[1:]:
        lines = src.strip().split('\n')
        url = lines[0].replace("fonte: ", "").strip()
        if url not in dead_urls:
            kept_sources.append(src)
            
    if kept_sources:
        new_blocks.append(header_part + "".join(kept_sources))
    else:
        print(f"Removed entire channel block: {header_part.strip()}")

with open("catalogo.txt", "w") as f:
    f.write("\n".join(new_blocks))

print("Cleaned up dead links.")
