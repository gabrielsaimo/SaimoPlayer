#!/usr/bin/env python3
"""
Injeta links Cloudflare R2 como fonte primária (opção 1) nas séries do SaimoPlayer,
remove completamente todas as referências ao servidor morto hubby-dmca (base 19),
e atualiza os índices de séries (series-<LETRA>.txt, busca.txt e indice.txt).
"""

import json
import re
import glob
import sqlite3
import unicodedata
import urllib.parse
from pathlib import Path

ROOT = Path(__file__).resolve().parent
VOD_DIR = ROOT / "vod"
VC_JSON = ROOT.parent / "arquivos-gerados" / "visioncine-series" / "visioncine_series.json"
CACHE_DB = ROOT / "arquivos-gerados" / "embedplayer-series" / "cache.sqlite3"

def norm_str(s):
    s = urllib.parse.unquote(s)
    s = re.sub(r"[\(\[]\d{4}[\)\]]", "", s)
    s = unicodedata.normalize("NFKD", s).encode("ASCII", "ignore").decode("utf-8").lower()
    return re.sub(r"[^a-z0-9]", "", s)

def clean_vc_title(raw):
    t = urllib.parse.unquote(raw).strip()
    t = re.sub(r"\s*[\(\[]?(dublado|legendado|completo)[\)\]]?\s*$", "", t, flags=re.I)
    t = re.sub(r"\s+\d{3,8}$", "", t)
    t = re.sub(r"\s+(?=[a-zA-Z0-9]*[0-9])(?=[a-zA-Z0-9]*[a-zA-Z])[0-9a-zA-Z]{4,8}$", "", t)
    t = re.sub(r"\s*[\(\[]?(dublado|legendado|completo)[\)\]]?\s*$", "", t, flags=re.I)
    return t.strip()

def main(dry_run=True):
    print(f"=== Injetando Séries VisionCine R2 (dry_run={dry_run}) ===")
    
    # 1. Carregar mapeamento TMDB -> bloco
    tmdb_to_block = {}
    if CACHE_DB.exists():
        con = sqlite3.connect(CACHE_DB)
        cur = con.cursor()
        for key, title, status, tmdb_id in cur.execute("SELECT key, title, status, tmdb_id FROM series WHERE tmdb_id != ''"):
            if "\x1f" in key:
                fn, t = key.split("\x1f", 1)
                clean_tmdb = tmdb_id.strip("'\"").strip()
                tmdb_to_block[clean_tmdb] = (fn, t)
        con.close()
    print(f"Mapeamentos TMDB carregados: {len(tmdb_to_block)}")

    # 2. Carregar todos os títulos do VOD
    vod_all = {}
    for p in sorted(VOD_DIR.glob("series-*-*.txt")):
        fn = p.name
        with open(p, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                if line.startswith("@"):
                    t = line[1:].split("\t")[0].strip()
                    vod_all[norm_str(t)] = (fn, t)
    print(f"Títulos do VOD indexados: {len(vod_all)}")

    # 3. Carregar dados do VisionCine
    with open(VC_JSON, "r", encoding="utf-8") as f:
        vc_data = json.load(f)
    print(f"Séries VisionCine carregadas: {len(vc_data)}")

    # 4. Mapear cada série para (arquivo, titulo)
    target_episodes = {}
    matched_series = 0

    for k, v in vc_data.items():
        raw_title = v.get("title", k)
        eps = v.get("episodes", [])
        if not eps:
            continue
        
        tmdb = v.get("tmdb_id", "").strip().strip("'\"")
        if not tmdb:
            m = re.search(r"_tmdb_(\d+)_", eps[0]["url"])
            if m:
                tmdb = m.group(1)
            
        target = None
        if tmdb and tmdb in tmdb_to_block:
            target = tmdb_to_block[tmdb]
            
        if not target:
            t1 = urllib.parse.unquote(raw_title)
            n1 = norm_str(t1)
            target = vod_all.get(n1)
            
        if not target:
            t2 = clean_vc_title(raw_title)
            n2 = norm_str(t2)
            target = vod_all.get(n2)
            
        if not target:
            slug = v.get("slug", "")
            slug_clean = re.sub(r"-(dublado|legendado)$", "", slug)
            slug_clean = re.sub(r"-[0-9a-zA-Z]{4,8}$", "", slug_clean)
            n3 = norm_str(slug_clean.replace("-", " "))
            target = vod_all.get(n3)

        if target:
            matched_series += 1
            fn, t = target
            m = target_episodes.setdefault((fn, t), {})
            for ep in eps:
                m[(ep["season"], ep["episode"], ep.get("audio", "dub"))] = ep["url"]

    print(f"Séries casadas com sucesso: {matched_series}")
    print(f"Blocos únicos de destino: {len(target_episodes)}")

    # 5. Processar arquivos series-*-*.txt
    modified_files = 0
    total_injected_r2 = 0
    total_purged_19 = 0
    
    series_episode_counts = {}

    for p in sorted(VOD_DIR.glob("series-*-*.txt")):
        fn = p.name
        m_letra = re.match(r"series-([A-Z#])-\d+\.txt", fn)
        letra = m_letra.group(1) if m_letra else ""

        with open(p, "r", encoding="utf-8", errors="ignore") as f:
            lines = f.readlines()

        new_lines = []
        cur_title = None
        cur_year = ""
        cur_ep_count = 0
        file_changed = False
        cur_header_line = None

        def flush_series():
            nonlocal cur_title, cur_year, cur_ep_count, cur_header_line
            if cur_title is not None:
                series_episode_counts[(letra, cur_title, cur_year)] = cur_ep_count

        for line in lines:
            line_s = line.strip()
            if line_s.startswith("@"):
                flush_series()
                cur_header_line = line_s
                parts = line_s[1:].split("\t")
                cur_title = parts[0].strip()
                cur_year = parts[1].strip() if len(parts) > 1 else ""
                cur_ep_count = 0
                new_lines.append(line_s + "\n")
                continue

            parts = line_s.split("\t")
            if len(parts) < 4:
                new_lines.append(line_s + "\n")
                continue

            try:
                s_num = int(parts[0])
                e_num = int(parts[1])
                audio = parts[2]
            except ValueError:
                new_lines.append(line_s + "\n")
                continue

            raw_sources = parts[3].split(",")
            valid_sources = []
            for src in raw_sources:
                s = src.strip()
                if not s:
                    continue
                if s.startswith("19:"):
                    total_purged_19 += 1
                    file_changed = True
                else:
                    valid_sources.append(s)

            ep_map = target_episodes.get((fn, cur_title))
            r2_url = None
            if ep_map:
                r2_url = ep_map.get((s_num, e_num, audio)) or ep_map.get((s_num, e_num, "dub"))

            if r2_url:
                total_injected_r2 += 1
                file_changed = True
                merged = [r2_url] + [s for s in valid_sources if s != r2_url]
            else:
                merged = valid_sources

            if merged:
                cur_ep_count += 1
                new_line = f"{s_num}\t{e_num}\t{audio}\t{','.join(merged)}\n"
                new_lines.append(new_line)
                if new_line != line:
                    file_changed = True
            else:
                # O episódio só tinha 19: e nenhum substituto R2
                file_changed = True

        flush_series()

        if file_changed:
            modified_files += 1
            if not dry_run:
                with open(p, "w", encoding="utf-8") as f:
                    f.writelines(new_lines)

    print(f"Arquivos series-*-*.txt modificados: {modified_files}")
    print(f"Links R2 injetados como primários: {total_injected_r2}")
    print(f"Ocorrências de 19: purgadas: {total_purged_19}")

    # 6. Atualizar series-<LETRA>.txt com as contagens reais
    updated_index_files = 0
    contagem_series = {}

    for p in sorted(VOD_DIR.glob("series-[A-Z#].txt")):
        letra = p.stem.replace("series-", "")
        with open(p, "r", encoding="utf-8", errors="ignore") as f:
            lines = f.readlines()

        new_index_lines = []
        index_changed = False
        for line in lines:
            line_s = line.strip()
            if not line_s:
                continue
            parts = line_s.split("\t")
            if len(parts) >= 4:
                titulo = parts[0]
                ano = parts[1]
                pedaco = parts[2]
                old_count = parts[3]
                
                key = (letra, titulo, ano)
                new_count_int = series_episode_counts.get(key, int(old_count) if old_count.isdigit() else 0)
                
                # Omitir séries com 0 episódios restantes
                if new_count_int == 0:
                    index_changed = True
                    continue
                    
                new_count = str(new_count_int)
                if new_count != old_count:
                    index_changed = True
                    parts[3] = new_count
                new_index_lines.append("\t".join(parts) + "\n")
            else:
                new_index_lines.append(line_s + "\n")

        contagem_series[letra] = len(new_index_lines)

        if index_changed:
            updated_index_files += 1
            if not dry_run:
                with open(p, "w", encoding="utf-8") as f:
                    f.writelines(new_index_lines)

    print(f"Arquivos de índice series-<LETRA>.txt atualizados: {updated_index_files}")

    # 7. Reconstruir busca.txt
    print("Reconstruindo busca.txt...")
    busca = []
    for p in sorted(VOD_DIR.glob("filmes-*.txt")):
        l = p.name.replace("filmes-", "").replace(".txt", "")
        with open(p, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                parts = line.strip().split("\t")
                if parts and parts[0]:
                    busca.append(f"{parts[0]}\tf\t{l}")

    for p in sorted(VOD_DIR.glob("series-[A-Z#].txt")):
        l = p.name.replace("series-", "").replace(".txt", "")
        with open(p, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                parts = line.strip().split("\t")
                if parts and parts[0]:
                    t = parts[0]
                    ano = parts[1] if len(parts) > 1 and parts[1] else ""
                    if ano:
                        busca.append(f"{t}\ts\t{l}\t{ano}")
                    else:
                        busca.append(f"{t}\ts\t{l}")

    busca.sort(key=lambda x: x.split("\t")[0].lower())
    if not dry_run:
        with open(VOD_DIR / "busca.txt", "w", encoding="utf-8") as f:
            f.write("\n".join(busca) + "\n")
    print(f"busca.txt total de registros: {len(busca)}")

    # 8. Reconstruir indice.txt com as contagens atualizadas
    print("Atualizando indice.txt...")
    with open(VOD_DIR / "indice.txt", "r", encoding="utf-8") as f:
        old_indice_lines = [l.strip() for l in f if l.strip()]

    new_indice = []
    # Preservar bases
    for line in old_indice_lines:
        if line.startswith("base:"):
            new_indice.append(line)

    # Letras
    for l in ["#"] + [chr(c) for c in range(ord("A"), ord("Z") + 1)]:
        f_file = VOD_DIR / f"filmes-{l}.txt"
        cnt_f = sum(1 for line in open(f_file, "r", encoding="utf-8", errors="ignore") if line.strip()) if f_file.exists() else 0
        cnt_s = contagem_series.get(l, 0)
        r_file = VOD_DIR / f"reservado-{l}.txt"
        cnt_r = sum(1 for line in open(r_file, "r", encoding="utf-8", errors="ignore") if line.strip()) if r_file.exists() else 0
        new_indice.append(f"{l}\t{cnt_f}\t{cnt_s}\t{cnt_r}")

    if not dry_run:
        with open(VOD_DIR / "indice.txt", "w", encoding="utf-8") as f:
            f.write("\n".join(new_indice) + "\n")
    print("indice.txt atualizado.")
    print("=== Concluído com sucesso! ===")

if __name__ == "__main__":
    import sys
    dry = "--run" not in sys.argv
    main(dry_run=dry)
