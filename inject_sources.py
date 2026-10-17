import re

# Discovered URLs mapping
# Format: (Channel Name in catalog, Discovered URL)
discovered = [
    ("ESPN", "https://16-5-0-235.sslip.io/espn/index.m3u8"),
    ("ESPN 2", "https://16-5-0-235.sslip.io/espn2/index.m3u8"),
    ("ESPN 3", "https://16-5-0-235.sslip.io/espn3/index.m3u8"),
    ("ESPN 4", "https://16-5-0-235.sslip.io/espn4/index.m3u8"),
    ("ESPN 5", "https://16-5-0-235.sslip.io/espn5/index.m3u8"),
    ("ESPN 6", "https://16-5-0-235.sslip.io/espn6/index.m3u8"),
    ("SporTV", "https://16-5-0-235.sslip.io/sportv/index.m3u8"),
    ("SporTV 2", "https://16-5-0-235.sslip.io/sportv2/index.m3u8"),
    ("SporTV 3", "https://16-5-0-235.sslip.io/sportv3/index.m3u8"),
    ("Premiere 2", "https://16-5-0-235.sslip.io/premiere2/index.m3u8"),
    ("Premiere 3", "https://16-5-0-235.sslip.io/premiere3/index.m3u8"),
    ("Premiere 4", "https://16-5-0-235.sslip.io/premiere4/index.m3u8"),
    ("Premiere Clubes", "https://16-5-0-235.sslip.io/premiereclubes/index.m3u8"),
    ("Combate", "https://16-5-0-235.sslip.io/combate/index.m3u8"),
    ("BAND SPORTS HD", "https://16-5-0-235.sslip.io/bandsports/index.m3u8"),
    ("TNT", "https://16-5-0-235.sslip.io/tnt/index.m3u8"),
    
    ("ESPN", "http://45.162.64.114/ESPN_BRASIL/index.m3u8"),
    ("ESPN 4", "http://45.162.64.114/ESPN_4/index.m3u8"),
    ("TNT", "http://45.162.64.114/TNT/index.m3u8"),
    ("Space", "http://45.162.64.114/SPACE/index.m3u8"),
    
    ("ESPN", "http://138.204.86.4:8080/ESPN_HD/index.m3u8"),
    ("ESPN 2", "http://138.204.86.4:8080/ESPN2_HD/index.m3u8"),
    ("ESPN 3", "http://138.204.86.4:8080/ESPN3_HD/index.m3u8"),
    ("ESPN 4", "http://138.204.86.4:8080/ESPN4_HD/index.m3u8"),
    ("Globo", "http://138.204.86.4:8080/GLOBO_HD/index.m3u8"),
    ("SBT", "http://138.204.86.4:8080/SBT_HD/index.m3u8"),
    ("Record", "http://138.204.86.4:8080/RECORD/index.m3u8"),
    ("Band", "http://138.204.86.4:8080/BAND_HD/index.m3u8"),
    ("TNT", "http://138.204.86.4:8080/TNT_HD/index.m3u8"),
    ("Space", "http://138.204.86.4:8080/SPACE_HD/index.m3u8"),
    ("HBO", "http://138.204.86.4:8080/HBO/index.m3u8"),
    ("HBO2", "http://138.204.86.4:8080/HBO2/index.m3u8"),
    ("Discovery Channel", "http://138.204.86.4:8080/DISCOVERY_HD/index.m3u8"),
]

# Read original
with open("/Volumes/SSD 1TB/DEV/Saimo/SaimoPlayer/catalogo.txt", "r", encoding="utf-8") as f:
    lines = f.readlines()

new_lines = []
current_channel = None

for line in lines:
    new_lines.append(line)
    
    if line.startswith("canal:"):
        current_channel = line.replace("canal:", "").strip()
        
    elif line.startswith("fonte:") or line.startswith("nome:"):
        # We want to inject right after the LAST font of a block, 
        # but the simplest way is to inject at the start of a block 
        # or after a font line. Actually let's just append at the END of a channel block.
        pass

# Second pass: append fonts at the end of each block
# A block ends when another "canal:" starts or EOF
out_lines = []
current_channel = None
fonts_for_current_channel = []

for line in lines:
    if line.startswith("canal:"):
        # Write any pending sources for the previous channel
        if current_channel and fonts_for_current_channel:
            for source in fonts_for_current_channel:
                out_lines.append(f"fonte: {source}\n")
            fonts_for_current_channel = []
            
        current_channel = line.replace("canal:", "").strip()
        out_lines.append(line)
        
        # Load up fonts to insert for this channel
        urls = [url for (ch, url) in discovered if ch == current_channel]
        fonts_for_current_channel.extend(urls)
        
    elif line.startswith("fonte:"):
        out_lines.append(line)
        # remove if it's already in the file to avoid duplicates
        existing_url = line.replace("fonte:", "").strip()
        if existing_url in fonts_for_current_channel:
            fonts_for_current_channel.remove(existing_url)
    else:
        out_lines.append(line)

# Handle the last channel block
if current_channel and fonts_for_current_channel:
    # Ensure there's no trailing whitespace issue
    for source in fonts_for_current_channel:
        out_lines.append(f"fonte: {source}\n")

with open("/Volumes/SSD 1TB/DEV/Saimo/SaimoPlayer/catalogo.txt", "w", encoding="utf-8") as f:
    f.writelines(out_lines)

