import re
with open("canais.txt", "r") as f:
    lines = f.readlines()

new_entries = [
    ('#EXTINF:-1 tvg-id="ESPN 5" tvg-logo="https://i.imgur.com/Zz2VFpL.png" group-title="ESPN", ESPN 5', 
     'https://xn--l---------------------------_________________________-2w85c.null-null.shop/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/espn5/__index.m3u8?sv=155&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1787869439-M0reI%2FWUrZUiSHsWxwUlePEwiXc2IRD%2FmXMl9JZJvZ8%3D'),
    ('#EXTINF:-1 tvg-id="PRIME BOX BRAZIL" tvg-logo="https://is.gd/En5RD3" group-title="VARIEDADES", PRIME BOX BRAZIL', 
     'https://xn--l---------------------------_________________________-2w85c.null-null.shop/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/primeboxbrazil/__index.m3u8?sv=138&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1787869497-UeiDFAmfxU40dxtplC5AdwvCD%2BMT4gEHflkznQykTw4%3D')
]

channels = []
i = 0
header = ""
while i < len(lines):
    line = lines[i].strip()
    if line == "#EXTM3U":
        header = line + "\n"
        i += 1
        continue
    if line.startswith("#EXTINF:"):
        extinf = lines[i].strip()
        url = lines[i+1].strip() if i+1 < len(lines) else ""
        channels.append((extinf, url))
        i += 2
    else:
        if line:
            print("Warning, stray line:", line)
        i += 1

for extinf, url in new_entries:
    channels.append((extinf, url))

def get_name(extinf):
    match = re.search(r'tvg-id="([^"]+)"', extinf)
    if match:
        return match.group(1).lower()
    return extinf.split(",")[-1].strip().lower()

channels.sort(key=lambda x: get_name(x[0]))

with open("canais.txt", "w") as f:
    f.write(header)
    for extinf, url in channels:
        f.write(extinf + "\n")
        f.write(url + "\n")

