import re
from pathlib import Path
from collections import defaultdict

VOD_DIR = Path("/Volumes/SSD 1TB/DEV/Saimo/SaimoPlayer/vod")

def normalize(title: str) -> str:
    import unicodedata
    s = ''.join(c for c in unicodedata.normalize('NFD', title) if unicodedata.category(c) != 'Mn')
    s = re.sub(r'[^a-zA-Z0-9]+', '', s.lower())
    return s

def extract_year(title: str) -> tuple[str, str]:
    m = re.search(r'\(\s*(\d{4})\s*\)$', title.strip())
    if m:
        return title[:m.start()].strip(), m.group(1)
    return title.strip(), ""

def parse_line(line: str):
    parts = line.split("\t")
    title = parts[0].strip()
    langs = {"dub": [], "leg": []}
    extras = []
    for p in parts[1:]:
        m = re.match(r"^(dub|leg)=(.+)$", p.strip())
        if m:
            langs[m.group(1)] = [u.strip() for u in m.group(2).split(",") if u.strip()]
        else:
            if p.strip(): extras.append(p.strip())
    return title, langs, extras

def build_line(title, langs, extras):
    parts = [title]
    for l in ("dub", "leg"):
        if langs[l]:
            seen = set()
            urls = []
            for u in langs[l]:
                if u not in seen:
                    seen.add(u)
                    urls.append(u)
            parts.append(f"{l}=" + ",".join(urls))
    parts.extend(extras)
    return "\t".join(parts)

def process_file(path):
    with open(path, "r", encoding="utf-8") as f:
        lines = f.read().splitlines()
    
    groups = defaultdict(list)
    for line in lines:
        if not line.strip(): continue
        t, l, e = parse_line(line)
        clean_t, yr = extract_year(t)
        norm = normalize(clean_t)
        if norm:
            groups[norm].append((t, yr, l, e, line))
        else:
            groups[t].append((t, yr, l, e, line))
            
    new_lines = []
    changes = 0
    
    for norm, items in groups.items():
        if len(items) == 1:
            new_lines.append(items[0][4])
            continue
            
        by_year = defaultdict(list)
        for t, yr, l, e, raw in items:
            by_year[yr].append((t, yr, l, e, raw))
            
        years_present = [y for y in by_year.keys() if y != ""]
        
        if len(years_present) == 1:
            target_year = years_present[0]
            main_t = ""
            main_e = []
            all_langs = {"dub": [], "leg": []}
            
            # Pega o titulo base (com ano)
            for t, yr, l, e, raw in by_year[target_year]:
                main_t = t
                main_e.extend(e)
                for lang in l: all_langs[lang].extend(l[lang])
            
            # Junta as fontes das duplicatas (sem ano) no fim (reserva)
            for t, yr, l, e, raw in by_year[""]:
                main_e.extend(e)
                for lang in l: all_langs[lang].extend(l[lang])
            
            seen_e = set()
            dedup_e = [ex for ex in main_e if not (ex in seen_e or seen_e.add(ex))]
                    
            new_lines.append(build_line(main_t, all_langs, dedup_e))
            changes += len(items) - 1
            print(f"[{path.name}] Fusão: " + " + ".join(x[0] for x in items) + f" -> {main_t}")
        else:
            for yr, sub_items in by_year.items():
                if len(sub_items) > 1:
                    main_t = sub_items[0][0]
                    main_e = []
                    all_langs = {"dub": [], "leg": []}
                    for t, y, l, e, raw in sub_items:
                        main_e.extend(e)
                        for lang in l: all_langs[lang].extend(l[lang])
                    seen_e = set()
                    dedup_e = [ex for ex in main_e if not (ex in seen_e or seen_e.add(ex))]
                    new_lines.append(build_line(main_t, all_langs, dedup_e))
                    changes += len(sub_items) - 1
                    print(f"[{path.name}] Fusão: " + " + ".join(x[0] for x in sub_items) + f" -> {main_t}")
                else:
                    new_lines.append(sub_items[0][4])

    if changes > 0:
        new_lines.sort(key=lambda x: x.split('\t')[0].lower())
        with open(path, "w", encoding="utf-8") as f:
            f.write("\n".join(new_lines) + "\n")
    return changes

total = 0
for p in VOD_DIR.glob("filmes-*.txt"):
    total += process_file(p)
print(f"Total de títulos duplicados removidos em filmes: {total}")
