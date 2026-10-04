#!/usr/bin/env python3
import json
import re
import urllib.request
import urllib.error
import time
import csv
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VOD = ROOT / "vod"
SAIDA = VOD / "mgeb_extraido"
RELATORIO = ROOT / "arquivos-gerados" / "mgeb_extraido"

MGEB = "https://mgeb.top/embed"
NHD = "https://nhdapi.com/embed"
AGENTE = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"

def url_filme(tmdb: int) -> tuple[str, str]:
    return f"{MGEB}/{tmdb}", f"{NHD}/movie/{tmdb}"

def url_episodio(tmdb: int, temporada: int, episodio: int) -> tuple[str, str]:
    return f"{MGEB}/{tmdb}/{temporada}/{episodio}", f"{NHD}/tv/{tmdb}/{temporada}/{episodio}"

def ler_fichas() -> dict[tuple[str, str], int]:
    ids = {}
    for linha in (VOD / "fichas.txt").read_text(encoding="utf-8").splitlines():
        campos = linha.split("\t")
        if len(campos) < 3 or campos[0] not in ("f", "s"):
            continue
        try:
            ids[(campos[0], campos[1])] = int(campos[2])
        except ValueError:
            pass
    return ids

def extrair_fontes(html: str) -> list[str]:
    match = re.search(r'var sources = (\[.*?\]);', html)
    if not match:
        return []
    try:
        sources = json.loads(match.group(1))
        return [s.get('file') for s in sources if s.get('file')]
    except Exception:
        return []

def buscar_url(url: str) -> str:
    for tentativa in range(1):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": AGENTE})
            with urllib.request.urlopen(req, timeout=3) as r:
                html = r.read().decode('utf-8')
                fontes = extrair_fontes(html)
                return fontes[0] if fontes else ""
        except urllib.error.HTTPError as erro:
            if erro.code in (429, 502, 503):
                time.sleep(1)
                continue
            return ""
        except Exception:
            return ""
    return ""

def series_do_acervo() -> dict[str, dict]:
    anos = {}
    for indice in VOD.glob("series-*.txt"):
        if re.search(r"series-.+-\d+\.txt$", indice.name):
            continue
        for linha in indice.read_text(encoding="utf-8").splitlines():
            campos = linha.split("\t")
            if campos and campos[0]:
                anos[campos[0]] = campos[1] if len(campos) > 1 else ""
    series = {}
    for pedaco in sorted(VOD.glob("series-*-*.txt")):
        atual = None
        for linha in pedaco.read_text(encoding="utf-8").splitlines():
            if linha.startswith("@"):
                atual = linha[1:].split("\t")[0].strip()
                series.setdefault(atual, {"ano": anos.get(atual, ""), "eps": set()})
                continue
            if atual is None:
                continue
            campos = linha.split("\t")
            try:
                series[atual]["eps"].add((int(campos[0]), int(campos[1])))
            except Exception:
                pass
    return series

def main():
    SAIDA.mkdir(parents=True, exist_ok=True)
    RELATORIO.mkdir(parents=True, exist_ok=True)
    fichas = ler_fichas()
    
    filmes = {}
    for arquivo in sorted(VOD.glob("filmes-*.txt")):
        for linha in arquivo.read_text(encoding="utf-8").splitlines():
            t = linha.split("\t", 1)[0]
            if t: filmes[t] = True

    series = series_do_acervo()
    
    alvo_filmes = []
    for titulo in filmes:
        titulo_limpo = re.sub(r"\s*\(\d{4}\)\s*$", "", titulo).strip()
        tmdb = fichas.get(("f", titulo)) or fichas.get(("f", titulo_limpo))
        if tmdb:
            dub, leg = url_filme(tmdb)
            alvo_filmes.append((titulo, tmdb, "", "", "dub", dub))
            alvo_filmes.append((titulo, tmdb, "", "", "leg", leg))
            
    alvo_series = []
    for titulo, dados in series.items():
        titulo_limpo = re.sub(r"\s*\(\d{4}\)\s*$", "", titulo).strip()
        tmdb = fichas.get(("s", titulo)) or fichas.get(("s", titulo_limpo))
        if tmdb:
            for t, e in sorted(dados["eps"]):
                dub, leg = url_episodio(tmdb, t, e)
                alvo_series.append((titulo, tmdb, t, e, "dub", dub))
                alvo_series.append((titulo, tmdb, t, e, "leg", leg))
            
    alvos_totais = alvo_filmes + alvo_series
    print(f"Iniciando raspagem profunda de {len(alvos_totais)} links totais (MGEB e NHD)...")
    
    def processar(item):
        titulo, tmdb, t, e, idioma, url = item
        real_url = buscar_url(url)
        return (titulo, tmdb, t, e, idioma, url, real_url)
        
    sucessos = 0
    linhas_filmes = {}
    linhas_series = {}
    csv_rows = []
    
    with ThreadPoolExecutor(50) as executor:
        for idx, (titulo, tmdb, t, e, idioma, url, extraido) in enumerate(executor.map(processar, alvos_totais)):
            if extraido:
                sucessos += 1
                if not t: # filme
                    if titulo not in linhas_filmes:
                        linhas_filmes[titulo] = []
                    linhas_filmes[titulo].append(f"{idioma}={extraido}")
                    csv_rows.append(["filme", titulo, tmdb, "", "", idioma, extraido])
                else: # serie
                    if titulo not in linhas_series:
                        linhas_series[titulo] = []
                    linhas_series[titulo].append(f"{t}\t{e}\t{idioma}\t{extraido}")
                    csv_rows.append(["serie", titulo, tmdb, t, e, idioma, extraido])
                    
            if (idx + 1) % 50 == 0:
                print(f"Processado {idx + 1}/{len(alvos_totais)}... Encontrados diretos: {sucessos}")
                
    # Salvar Filmes
    texto_filmes = []
    for titulo, links in linhas_filmes.items():
        texto_filmes.append(f"{titulo}\t" + "\t".join(links))
    (SAIDA / "links-filmes-extraidos.txt").write_text("\n".join(texto_filmes) + "\n", encoding="utf-8")
    
    # Salvar Series
    texto_series = []
    for titulo in sorted(linhas_series.keys()):
        ano = series.get(titulo, {}).get("ano", "")
        texto_series.append(f"@{titulo}\t{ano}")
        texto_series.extend(linhas_series[titulo])
    (SAIDA / "links-series-extraidas.txt").write_text("\n".join(texto_series) + "\n", encoding="utf-8")
    
    # Relatorio
    with (RELATORIO / "mgeb-nhd-extraido.csv").open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["tipo", "titulo", "tmdb_id", "temporada", "episodio", "idioma", "url_extraida"])
        w.writerows(csv_rows)
        
    print(f"Concluido! {sucessos} arquivos mp4/m3u8 puros extraidos.")

if __name__ == "__main__":
    main()
