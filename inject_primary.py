import re

# Premium servers
PREMIUM_SERVERS = [
    "16-5-0-235.sslip.io",
    "45.162.64.114",
    "138.204.86.4:8080"
]

# Additional discovered URLs to ensure they are added
discovered = [
    ("Warner Channel", "http://138.204.86.4:8080/WARNER_HD/index.m3u8"),
    ("Sony Movies", "http://138.204.86.4:8080/SONY_HD/index.m3u8"),
    ("AXN", "http://138.204.86.4:8080/AXN_HD/index.m3u8"),
    ("History", "http://138.204.86.4:8080/HISTORY_HD/index.m3u8"),
    ("Megapix", "https://16-5-0-235.sslip.io/megapix/index.m3u8"),
    ("CNN Brasil", "http://45.162.64.114/CNN_BRASIL/index.m3u8"),
    ("GloboNews", "https://16-5-0-235.sslip.io/globonews/index.m3u8"),
    ("GNT", "https://16-5-0-235.sslip.io/gnt/index.m3u8"),
    ("Multishow", "https://16-5-0-235.sslip.io/multishow/index.m3u8"),
    ("Cinemax", "http://138.204.86.4:8080/CINEMAX/index.m3u8"),
    ("Cartoon Network", "http://45.162.64.114/CARTOON_NETWORK/index.m3u8"),
    ("Discovery Kids", "http://138.204.86.4:8080/DISCOVERY_KIDS_HD/index.m3u8"),
    ("Boomerang", "http://45.162.64.114/BOOMERANG/index.m3u8"),
    ("RedeTV!", "http://45.162.64.114/REDE_TV/index.m3u8"),
    ("Band News", "http://45.162.64.114/BAND_NEWS/index.m3u8"),
    ("MTV", "https://16-5-0-235.sslip.io/mtv/index.m3u8"),
    ("Globo", "http://138.204.86.4:8080/GLOBO_HD/index.m3u8"),
    ("SBT", "http://138.204.86.4:8080/SBT_HD/index.m3u8"),
    ("Record", "http://138.204.86.4:8080/RECORD/index.m3u8"),
    ("Band", "http://138.204.86.4:8080/BAND_HD/index.m3u8"),
    ("HBO Plus", "http://138.204.86.4:8080/HBO_PLUS/index.m3u8"),
    ("HBO Family", "http://138.204.86.4:8080/HBO_FAMILY/index.m3u8"),
    ("Globo SP", "https://16-5-0-235.sslip.io/globosp/index.m3u8"),
    ("HBO Signature", "http://138.204.86.4:8080/HBO_SIGNATURE/index.m3u8"),
    ("HBO Mundi", "http://138.204.86.4:8080/HBO_MUNDI_HD/index.m3u8"),
    ("Boomerang", "http://138.204.86.4:8080/BOOMERANG_HD/index.m3u8"),
    ("HBO Pop", "http://138.204.86.4:8080/HBO_POP_HD/index.m3u8"),
    ("Globo RJ", "https://16-5-0-235.sslip.io/globorj/index.m3u8"),
    ("Premiere 5", "https://16-5-0-235.sslip.io/premiere5/index.m3u8"),
    ("Discovery Turbo", "http://45.162.64.114/DISCOVERY_TURBO/index.m3u8"),
    ("Discovery Science", "http://138.204.86.4:8080/DISCOVERY_SCIENCE_HD/index.m3u8"),
    ("Premiere 6", "https://16-5-0-235.sslip.io/premiere6/index.m3u8"),
    ("Premiere 7", "https://16-5-0-235.sslip.io/premiere7/index.m3u8"),
    ("Discovery Home & Health", "http://45.162.64.114/DISCOVERY_H_H/index.m3u8"),
    ("Discovery ID", "http://45.162.64.114/DISCOVERY_ID/index.m3u8"),
    ("Discovery ID", "http://138.204.86.4:8080/ID_HD/index.m3u8"),
    ("Discovery Theater", "http://138.204.86.4:8080/DISCOVERY_THEATER_HD/index.m3u8"),
    ("Premiere 8", "https://16-5-0-235.sslip.io/premiere8/index.m3u8"),
    ("Discovery World", "http://45.162.64.114/DISCOVERY_WORLD/index.m3u8"),
    ("Discovery World", "http://138.204.86.4:8080/DISCOVERY_WORLD_HD/index.m3u8"),
    ("Discovery Turbo", "http://138.204.86.4:8080/DISCOVERY_TURBO_HD/index.m3u8"),
]

# Read original
with open("/Volumes/SSD 1TB/DEV/Saimo/SaimoPlayer/catalogo.txt", "r", encoding="utf-8") as f:
    lines = f.readlines()

def is_premium(url):
    for p in PREMIUM_SERVERS:
        if p in url:
            return True
    return False

# Group file into blocks
blocks = []
current_block = []

for line in lines:
    if line.startswith("canal:"):
        if current_block:
            blocks.append(current_block)
        current_block = [line]
    else:
        if current_block:
            current_block.append(line)
        else:
            # Header or comments
            blocks.append([line])
            current_block = []

if current_block:
    blocks.append(current_block)

out_lines = []

for block in blocks:
    if not block or not block[0].startswith("canal:"):
        out_lines.extend(block)
        continue
        
    channel_name = block[0].replace("canal:", "").strip()
    
    metadata = []
    fontes = []
    qualidades = {}
    
    # Parse the block
    last_fonte = None
    for line in block[1:]:
        if line.startswith("fonte:"):
            url = line.replace("fonte:", "").strip()
            fontes.append(url)
            last_fonte = url
        elif line.startswith("qualidade:") or line.startswith("nome:"):
            if last_fonte:
                if last_fonte not in qualidades:
                    qualidades[last_fonte] = []
                qualidades[last_fonte].append(line)
            else:
                metadata.append(line)
        else:
            metadata.append(line)
            
    # Add any new urls from 'discovered' to this channel if they are not already there
    for cname, url in discovered:
        if cname == channel_name and url not in fontes:
            fontes.append(url)
            
    # Reorder fonts: premium first
    premium_fontes = [f for f in fontes if is_premium(f)]
    other_fontes = [f for f in fontes if not is_premium(f)]
    
    reordered_fontes = premium_fontes + other_fontes
    
    # Reconstruct block
    out_lines.append(block[0])
    for m in metadata:
        out_lines.append(m)
        
    for f in reordered_fontes:
        out_lines.append(f"fonte: {f}\n")
        if f in qualidades:
            for q in qualidades[f]:
                out_lines.append(q)

with open("/Volumes/SSD 1TB/DEV/Saimo/SaimoPlayer/catalogo.txt", "w", encoding="utf-8") as f:
    f.writelines(out_lines)

