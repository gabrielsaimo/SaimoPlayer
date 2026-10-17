import urllib.request
import re
import sys

URL = "https://raw.githubusercontent.com/ardvlmantovani-art/iptv-brasil-amantovani/refs/heads/main/listacompleta_working.m3u8"

print("Downloading M3U8...")
req = urllib.request.Request(URL, headers={'User-Agent': 'Mozilla/5.0'})
try:
    with urllib.request.urlopen(req) as response:
        content = response.read().decode('utf-8')
except Exception as e:
    print(f"Error downloading: {e}")
    sys.exit(1)

m3u8_channels = []
lines = content.splitlines()
for i, line in enumerate(lines):
    if line.startswith("#EXTINF"):
        # extract name
        # format is usually #EXTINF:-1 tvg-id="..." tvg-logo="..." group-title="..." ,Channel Name
        name_part = line.split(",")[-1].strip()
        url_part = ""
        # The URL is usually the next non-empty, non-comment line
        for j in range(i+1, min(i+5, len(lines))):
            next_line = lines[j].strip()
            if next_line and not next_line.startswith("#"):
                url_part = next_line
                break
        if name_part and url_part:
            m3u8_channels.append((name_part, url_part))

print(f"Found {len(m3u8_channels)} channels in M3U8")
