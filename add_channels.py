import re

new_channels = []

with open('canais.txt', 'r') as f:
    content = f.read()

for ch_id, ch_name, group, logo, url in new_channels:
    if f'tvg-id="{ch_id}"' not in content:
        content += f'\n#EXTINF:-1 tvg-id="{ch_id}" tvg-logo="{logo}" group-title="{group}", {ch_name}\n{url}\n'

# Sort canais.txt alphabetically
lines = [l for l in content.split('\n') if l.strip()]
channels = []
current_header = ""
for line in lines:
    if line.startswith('#EXTINF'):
        current_header = line
    elif line.startswith('http') and current_header:
        m = re.search(r'tvg-id="([^"]+)"', current_header)
        name = m.group(1).lower() if m else ""
        channels.append((name, current_header, line))
        current_header = ""

channels.sort(key=lambda x: x[0])

with open('canais.txt', 'w') as f:
    f.write('#EXTM3U\n')
    for _, header, url in channels:
        f.write(header + '\n' + url + '\n')

print("Added and sorted in canais.txt")
