import json

with open("/Users/gabrielespindola/Documents/br.json", "r", encoding="utf-8") as f:
    data = json.load(f)

lines = []
for r in data:
    name = r.get("name", "").replace("|", "").strip()
    streams = r.get("sources", {}).get("streams", [])
    if streams:
        url = streams[0]
        if name and url:
            lines.append(f"{name}|{url}")

with open("/Volumes/SSD 1TB/DEV/Saimo/SaimoPlayer/vod/radios.txt", "w", encoding="utf-8") as f:
    for line in lines:
        f.write(line + "\n")
