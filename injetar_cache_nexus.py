import json
import sqlite3
from pathlib import Path
from atualizar_nexus import append_nexus, load_vod_files, build_title_index, parse_vod_sources, build_vod_line, normalize, extract_year

db_path = Path("/Volumes/SSD 1TB/DEV/Saimo/SaimoPlayer/arquivos-gerados/nexus/cache.sqlite3")
conn = sqlite3.connect(db_path)
cur = conn.cursor()
cur.execute("SELECT tmdb, url FROM nexus_urls WHERE url != ''")
cache = {str(row[0]): row[1] for row in cur.fetchall()}
conn.close()

with open("/Users/gabrielespindola/.gemini/antigravity/brain/6dc3eb6d-405d-4476-b70a-32c96b5ad136/scratch/todos_os_filmes.json", "r") as f:
    movies = json.load(f)

vod_files = load_vod_files()
index = build_title_index(vod_files)

changes = 0
for movie in movies:
    tmdb = str(movie.get("id") or movie.get("tmdb") or "")
    if tmdb not in cache: continue
    
    nexus_url = cache[tmdb]
    nome = str(movie.get("nome", "")).strip()
    ano = str(movie.get("ano", "")).strip()
    norm = normalize(nome)
    
    matches = index.get((norm, ano)) or index.get((norm, ""))
    if matches:
        for fname, idx in matches:
            raw = vod_files[fname][idx][1]
            title_raw, langs, extras = parse_vod_sources(raw)
            dub_urls = langs.get("dub", [])
            new_dub = append_nexus(dub_urls, nexus_url)
            if new_dub != dub_urls:
                langs["dub"] = new_dub
                vod_files[fname][idx] = (idx, build_vod_line(title_raw, langs, extras))
                changes += 1

if changes > 0:
    for fname, lines in vod_files.items():
        with open(Path("/Volumes/SSD 1TB/DEV/Saimo/SaimoPlayer/vod") / fname, "w") as f:
            f.write("\n".join(l[1] for l in lines) + "\n")

print(f"Aplicadas {changes} fontes do cache.")
