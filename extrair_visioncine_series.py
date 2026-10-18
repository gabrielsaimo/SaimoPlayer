#!/usr/bin/env python3
"""Extrator completo de séries e animes do VisionCine para o Cloudflare R2.

Baixa o sitemap de 10.176 séries, extrai todas as temporadas e episódios com links
diretos do Cloudflare R2 (https://pub-bda823ef358c448ea310cdf9539f9628.r2.dev/tv/...),
salva em SQLite com cache contínuo e gera:
1. visioncine_series.m3u
2. visioncine_series.json
3. visioncine_series_saimo.txt
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

OUT_DIR = Path("/Volumes/SSD 1TB/DEV/Saimo/arquivos-gerados/visioncine-series")
OUT_DIR.mkdir(parents=True, exist_ok=True)
DB_PATH = OUT_DIR / "cache.sqlite3"
SITEMAP_URL = "https://visioncine-1.lat/sitemap-series.xml"
USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"

def init_db():
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute("""
    CREATE TABLE IF NOT EXISTS series (
        slug TEXT PRIMARY KEY,
        title TEXT,
        year TEXT,
        tmdb_id TEXT,
        total_seasons INTEGER,
        total_episodes INTEGER,
        episodes_json TEXT,
        status TEXT,
        updated_at INTEGER
    );
    """)
    conn.commit()
    conn.close()

def get_all_series_slugs():
    print(f"Baixando sitemap oficial de séries: {SITEMAP_URL}...")
    req = urllib.request.Request(SITEMAP_URL, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=20) as res:
        content = res.read().decode("utf-8", "ignore")
    slugs = re.findall(r"<loc>https://visioncine-1\.lat/watch/([^<]+)</loc>", content)
    print(f"Total de séries no sitemap: {len(slugs)}")
    return slugs

def extract_single_series(slug):
    try:
        url = f"https://visioncine-1.lat/watch/{slug}"
        req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        html = urllib.request.urlopen(req, timeout=12).read().decode("utf-8", "ignore")
        
        # Extrair título e ano
        m_title = re.search(r"<title>VisionCine - Assistir (.*?) online", html)
        raw_title = m_title.group(1).strip() if m_title else slug.replace("-", " ").title()
        
        m_year = re.search(r"\b(19\d\d|20\d\d)\b", raw_title)
        year = m_year.group(1) if m_year else ""
        clean_title = re.sub(r"\s*\((?:dublado|legendado)\)\s*", "", raw_title, flags=re.I).strip()
        clean_title = re.sub(r"\s+\d{4}$", "", clean_title).strip()
        
        m_seasons = re.search(r"const allSeasons = (\{.*?\});", html)
        if not m_seasons:
            return slug, clean_title, year, "", 0, 0, "[]", "no_seasons"
            
        data = json.loads(m_seasons.group(1))
        episodes = []
        tmdb_id = ""
        
        for s_num, eps in data.items():
            try:
                season_int = int(s_num)
            except ValueError:
                season_int = 1
                
            for ep in eps:
                ep_url = ep.get("url_video") or ""
                if not ep_url or "r2.dev" not in ep_url:
                    continue
                if not tmdb_id and ep.get("id_tmdb"):
                    tmdb_id = str(ep.get("id_tmdb"))
                    
                is_leg = "legendad" in slug.lower()
                audio = "leg" if is_leg else "dub"
                
                episodes.append({
                    "season": season_int,
                    "episode": int(ep.get("episodio") or 1),
                    "name": ep.get("nome") or f"Episódio {ep.get('episodio')}",
                    "image": ep.get("imagem") or "",
                    "audio": audio,
                    "url": ep_url
                })
                
        if not episodes:
            return slug, clean_title, year, tmdb_id, len(data), 0, "[]", "no_r2_eps"
            
        return slug, clean_title, year, tmdb_id, len(data), len(episodes), json.dumps(episodes), "found"
    except Exception as e:
        return slug, "", "", "", 0, 0, "[]", f"error: {str(e)[:50]}"

def export_catalogs():
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    rows = cur.execute("SELECT slug, title, year, tmdb_id, episodes_json FROM series WHERE status='found' ORDER BY title ASC;").fetchall()
    conn.close()
    
    if not rows:
        return
        
    m3u_lines = ["#EXTM3U"]
    saimo_lines = []
    json_series = {}
    total_eps_count = 0
    
    for slug, title, year, tmdb_id, eps_json in rows:
        try:
            episodes = json.loads(eps_json)
        except Exception:
            continue
            
        if not episodes:
            continue
            
        total_eps_count += len(episodes)
        json_series[title] = {
            "title": title,
            "slug": slug,
            "year": year,
            "tmdb_id": tmdb_id,
            "episodes": episodes
        }
        
        # Formato Saimo: @Título\tAno
        header = f"@{title}" + (f"\t{year}" if year else "")
        saimo_lines.append(header)
        for ep in episodes:
            s_num = ep["season"]
            e_num = ep["episode"]
            audio = ep["audio"]
            u = ep["url"]
            name = ep.get("name") or f"Episódio {e_num}"
            
            saimo_lines.append(f"{s_num}\t{e_num}\t{audio}\t{u}")
            m3u_lines.append(f'#EXTINF:-1 tvg-name="{title} S{s_num:02d}E{e_num:02d}" group-title="Series",{title} S{s_num:02d}E{e_num:02d} - {name}')
            m3u_lines.append(u)
        saimo_lines.append("")
        
    # Salvar M3U
    with open(OUT_DIR / "visioncine_series.m3u", "w", encoding="utf-8") as f:
        f.write("\n".join(m3u_lines) + "\n")
        
    # Salvar JSON
    with open(OUT_DIR / "visioncine_series.json", "w", encoding="utf-8") as f:
        json.dump(json_series, f, ensure_ascii=False, indent=2)
        
    # Salvar TXT
    with open(OUT_DIR / "visioncine_series_saimo.txt", "w", encoding="utf-8") as f:
        f.write("\n".join(saimo_lines) + "\n")

def main():
    init_db()
    slugs = get_all_series_slugs()
    
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    already_done = set(row[0] for row in cur.execute("SELECT slug FROM series;").fetchall())
    conn.close()
    
    pending = [s for s in slugs if s not in already_done]
    print(f"Séries já no cache: {len(already_done)} | Pendentes para extrair: {len(pending)}")
    
    if not pending:
        print("Todas as séries já foram extraídas!")
        export_catalogs()
        return

    workers = 16
    batch_size = 50
    completed = len(already_done)
    total = len(slugs)
    
    print(f"Iniciando extração de séries com {workers} workers paralelos...")
    t0 = time.time()
    
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    
    batch = []
    with ThreadPoolExecutor(max_workers=workers) as executor:
        futures = {executor.submit(extract_single_series, s): s for s in pending}
        for future in as_completed(futures):
            res = future.result()
            slug, title, year, tmdb_id, total_seasons, total_eps, episodes_json, status = res
            now = int(time.time())
            batch.append((slug, title, year, tmdb_id, total_seasons, total_eps, episodes_json, status, now))
            completed += 1
            
            if len(batch) >= batch_size:
                cur.executemany("INSERT OR REPLACE INTO series VALUES (?,?,?,?,?,?,?,?,?);", batch)
                conn.commit()
                batch = []
                elapsed = time.time() - t0
                rate = (completed - len(already_done)) / max(1, elapsed)
                print(f"Séries: {completed}/{total} ({(completed/total)*100:.1f}%) | Velocidade: {rate:.1f} series/s")
                export_catalogs()
                
    if batch:
        cur.executemany("INSERT OR REPLACE INTO series VALUES (?,?,?,?,?,?,?,?,?);", batch)
        conn.commit()
    conn.close()
    
    export_catalogs()
    print(f"Extração de séries concluída em {time.time()-t0:.1f}s!")

if __name__ == "__main__":
    main()
