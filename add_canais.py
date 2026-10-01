import re
with open("canais.txt", "r") as f:
    lines = f.readlines()

new_entries = []

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

