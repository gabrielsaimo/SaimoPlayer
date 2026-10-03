import json
from pathlib import Path

# 1. Carregar IDs do catálogo atual do SaimoPlayer
saimo_ids = set()
try:
    with open("/Volumes/SSD 1TB/DEV/Saimo/SaimoPlayer/vod/fichas.txt", "r", encoding="utf-8") as f:
        for line in f:
            parts = line.strip().split("\t")
            if len(parts) >= 3:
                # fichas.txt formato: tipo \t Titulo \t TMDB_ID ...
                tmdb_id = parts[2].strip()
                if tmdb_id.isdigit():
                    saimo_ids.add(tmdb_id)
except Exception as e:
    print(f"Erro ao ler fichas.txt: {e}")

# 2. Carregar IDs do catálogo da NexusTV
nexus_ids = set()
novos_filmes = []
try:
    with open("/Users/gabrielespindola/.gemini/antigravity/brain/6dc3eb6d-405d-4476-b70a-32c96b5ad136/scratch/todos_os_filmes.json", "r", encoding="utf-8") as f:
        nexus_movies = json.load(f)
        for m in nexus_movies:
            tmdb = str(m.get("id") or m.get("tmdb") or "").strip()
            if tmdb and tmdb.isdigit():
                nexus_ids.add(tmdb)
                if tmdb not in saimo_ids:
                    novos_filmes.append(m)
except Exception as e:
    print(f"Erro ao ler JSON da Nexus: {e}")

# 3. Salvar os novos IDs em um arquivo para usar depois
novos_ids = [str(m.get("id") or m.get("tmdb")) for m in novos_filmes]
with open("/Volumes/SSD 1TB/DEV/Saimo/SaimoPlayer/arquivos-gerados/nexus/ids_novos_para_adicionar.txt", "w", encoding="utf-8") as f:
    for nid in novos_ids:
        f.write(nid + "\n")

print(f"Total de filmes no seu catálogo atual: {len(saimo_ids)}")
print(f"Total de filmes na NexusTV: {len(nexus_ids)}")
print(f"Filmes NOVOS identificados na Nexus que você ainda não tem: {len(novos_filmes)}")
print(f"Lista de IDs novos salva em: arquivos-gerados/nexus/ids_novos_para_adicionar.txt")
