#!/usr/bin/env python3
"""Extrator completo de filmes do VisionCine para o Cloudflare R2.

Baixa o sitemap de 23.419 filmes, resolve as URLs diretas no Cloudflare R2
(https://pub-bda823ef358c448ea310cdf9539f9628.r2.dev/m/...), armazena em SQLite
para continuar de onde parou e gera:
1. visioncine_filmes.m3u
2. visioncine_filmes.json
3. visioncine_filmes_saimo.txt
"""

import os
import sys
import time
import json
import sqlite3
import re
import urllib.request
import urllib.parse
import urllib.error
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

OUT_DIR = Path("/Volumes/SSD 1TB/DEV/Saimo/arquivos-gerados/visioncine-filmes")
OUT_DIR.mkdir(parents=True, exist_ok=True)
DB_PATH = OUT_DIR / "cache.sqlite3"
SITEMAP_URL = "https://visioncine-1.lat/sitemap-movies.xml"
R2_BASE = "https://pub-bda823ef358c448ea310cdf9539f9628.r2.dev/m/"
USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None

OPENER = urllib.request.build_opener(NoRedirect)

def init_db():
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute("""
    CREATE TABLE IF NOT EXISTS movies (
        slug TEXT PRIMARY KEY,
        title TEXT,
        year TEXT,
        tmdb_id TEXT,
        r2_url TEXT,
        status TEXT,
        updated_at INTEGER
    );
    """)
    conn.commit()
    conn.close()

def get_all_slugs():
    print(f"Baixando sitemap oficial: {SITEMAP_URL}...")
    req = urllib.request.Request(SITEMAP_URL, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=20) as res:
        content = res.read().decode("utf-8", "ignore")
    slugs = re.findall(r"<loc>https://visioncine-1\.lat/watch/([^<]+)</loc>", content)
    print(f"Total de slugs encontrados no sitemap: {len(slugs)}")
    return slugs

def resolve_single_movie(slug):
    try:
        page_url = f"https://visioncine-1.lat/watch/{slug}"
        req = urllib.request.Request(page_url, headers={"User-Agent": USER_AGENT})
        html = urllib.request.urlopen(req, timeout=10).read().decode("utf-8", "ignore")
        
        # Extrair título da página se possível
        m_title = re.search(r"<title>VisionCine - Assistir (.*?) online", html)
        raw_title = m_title.group(1).strip() if m_title else slug.replace("-", " ").title()
        
        # Extrair ano
        m_year = re.search(r"\b(19\d\d|20\d\d)\b", raw_title)
        year = m_year.group(1) if m_year else ""
        clean_title = re.sub(r"\s*\((?:dublado|legendado)\)\s*", "", raw_title, flags=re.I).strip()
        
        m_player = re.search(r'href="(https://watch\.visioncine-1\.lat/m/\d+)"', html)
        if not m_player:
            return slug, clean_title, year, "", "", "no_player"
        player_url = m_player.group(1)
        
        req_p = urllib.request.Request(player_url, headers={"User-Agent": USER_AGENT, "Referer": page_url})
        html_p = urllib.request.urlopen(req_p, timeout=10).read().decode("utf-8", "ignore")
        m_resolve = re.search(r'file:\s*"(https://watch\.visioncine-1\.lat/api/vod-resolve\.php\?token=[^"]+)"', html_p)
        if not m_resolve:
            return slug, clean_title, year, "", "", "no_resolve"
        resolve_url = m_resolve.group(1)
        
        req_r = urllib.request.Request(resolve_url, headers={"User-Agent": USER_AGENT, "Referer": player_url})
        try:
            res = OPENER.open(req_r, timeout=10)
            loc = res.headers.get("Location")
        except urllib.error.HTTPError as e:
            loc = e.headers.get("Location")
            
        if not loc:
            return slug, clean_title, year, "", "", "no_loc"
        
        filename = urllib.parse.urlparse(loc).path.split("/")[-1]
        m_tmdb = re.search(r"_tmdb_(\d+)_", filename)
        tmdb_id = m_tmdb.group(1) if m_tmdb else ""
        
        r2_url = f"{R2_BASE}{filename}"
        return slug, clean_title, year, tmdb_id, r2_url, "found"
    except Exception as e:
        return slug, "", "", "", "", f"error: {str(e)[:50]}"

def export_catalogs():
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    rows = cur.execute("SELECT slug, title, year, tmdb_id, r2_url FROM movies WHERE status='found' ORDER BY title ASC;").fetchall()
    conn.close()
    
    if not rows:
        return
        
    m3u_lines = ["#EXTM3U"]
    saimo_dict = {}
    json_list = []
    
    for slug, title, year, tmdb_id, r2_url in rows:
        is_leg = "legendad" in slug.lower()
        audio = "leg" if is_leg else "dub"
        
        m3u_lines.append(f'#EXTINF:-1 tvg-name="{title}" group-title="Filmes",{title}')
        m3u_lines.append(r2_url)
        
        json_list.append({
            "title": title,
            "slug": slug,
            "year": year,
            "tmdb_id": tmdb_id,
            "audio": audio,
            "url": r2_url
        })
        
        if title not in saimo_dict:
            saimo_dict[title] = {"dub": [], "leg": []}
        if r2_url not in saimo_dict[title][audio]:
            saimo_dict[title][audio].append(r2_url)
            
    # Salvar M3U
    with open(OUT_DIR / "visioncine_filmes.m3u", "w", encoding="utf-8") as f:
        f.write("\n".join(m3u_lines) + "\n")
        
    # Salvar JSON
    with open(OUT_DIR / "visioncine_filmes.json", "w", encoding="utf-8") as f:
        json.dump(json_list, f, ensure_ascii=False, indent=2)
        
    # Salvar Formato Saimo TXT
    saimo_lines = []
    for t in sorted(saimo_dict.keys()):
        parts = [t]
        if saimo_dict[t]["dub"]:
            parts.append("dub=" + ",".join(saimo_dict[t]["dub"]))
        if saimo_dict[t]["leg"]:
            parts.append("leg=" + ",".join(saimo_dict[t]["leg"]))
        saimo_lines.append("\t".join(parts))
        
    with open(OUT_DIR / "visioncine_filmes_saimo.txt", "w", encoding="utf-8") as f:
        f.write("\n".join(saimo_lines) + "\n")

def main():
    init_db()
    slugs = get_all_slugs()
    
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    already_done = set(row[0] for row in cur.execute("SELECT slug FROM movies;").fetchall())
    conn.close()
    
    pending = [s for s in slugs if s not in already_done]
    print(f"Total já no cache: {len(already_done)} | Pendentes para extrair: {len(pending)}")
    
    if not pending:
        print("Todos os filmes já foram extraídos!")
        export_catalogs()
        return

    workers = 12
    batch_size = 50
    completed = len(already_done)
    total = len(slugs)
    
    print(f"Iniciando extração paralela com {workers} workers...")
    t0 = time.time()
    
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    
    batch = []
    with ThreadPoolExecutor(max_workers=workers) as executor:
        futures = {executor.submit(resolve_single_movie, s): s for s in pending}
        for future in as_completed(futures):
            res = future.result()
            slug, title, year, tmdb_id, r2_url, status = res
            now = int(time.time())
            batch.append((slug, title, year, tmdb_id, r2_url, status, now))
            completed += 1
            
            if len(batch) >= batch_size:
                cur.executemany("INSERT OR REPLACE INTO movies VALUES (?,?,?,?,?,?,?);", batch)
                conn.commit()
                batch = []
                elapsed = time.time() - t0
                rate = (completed - len(already_done)) / max(1, elapsed)
                print(f"Progresso: {completed}/{total} ({(completed/total)*100:.1f}%) | Velocidade: {rate:.1f} filmes/s")
                export_catalogs()
                
    if batch:
        cur.executemany("INSERT OR REPLACE INTO movies VALUES (?,?,?,?,?,?,?);", batch)
        conn.commit()
    conn.close()
    
    export_catalogs()
    print(f"Extração finalizada com sucesso em {time.time()-t0:.1f}s!")

if __name__ == "__main__":
    main()
