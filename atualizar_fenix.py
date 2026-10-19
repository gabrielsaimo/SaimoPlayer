#!/usr/bin/env python3
"""Fontes a mais do FenixFlix para os filmes e séries que o acervo já tem.

O FenixFlix responde diretamente por id do TMDB ou IMDb:

    /stream/movie/tmdb:550.json
    /stream/series/tmdb:1396:1:1.json

As fontes aproveitáveis (Malfoy, Zunder MP4/HLS) entram sempre como FONTE RESERVA
(no final da lista de fontes), preservando a fonte pub- (Cloudflare R2) como a
1ª opção primária absoluta. Links Koyeb instáveis (404) e com token expirável
são descartados automaticamente após teste real de vídeo.

Uso:
    python3 atualizar_fenix.py --limite 1000 --aplicar
    python3 atualizar_fenix.py --so-filmes --limite 500 --aplicar
    python3 atualizar_fenix.py --so-series --limite 500 --aplicar
"""

from __future__ import annotations

import argparse
import json
import re
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

ROOT = Path(__file__).resolve().parent
VOD = ROOT / "vod"
SAIDA = VOD / "fenix"
CACHE = ROOT / "arquivos-gerados" / "fenix"

FENIX = "https://fenixflix.fenixhub.online"
AGENTE = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
          "(KHTML, like Gecko) Chrome/140.0 Safari/537.36")

VALIDADE_ACHADO = 3 * 24 * 3600
VALIDADE_VAZIO = 14 * 24 * 3600

TOKEN_DE_TEMPO = re.compile(r"/t/\d{9,11}\.[0-9a-f]{16,}/", re.I)
VENCIMENTO = re.compile(r"[?&](?:expires|exp|e|expiry|validto|until)=\d{9,11}(?:&|$)", re.I)

VERSAO = 3


def vence(url: str) -> bool:
    """Link com prazo curto ou Koyeb caído: não serve para a lista."""
    if "koyeb.app" in url:
        return True
    return bool(TOKEN_DE_TEMPO.search(url) or VENCIMENTO.search(url))


# MARK: - Rede

def pedir_json(url: str, tentativas: int = 3):
    """GET com tentativas: o Fenix às vezes responde vazio."""
    for tentativa in range(tentativas):
        try:
            pedido = urllib.request.Request(url, headers={"User-Agent": AGENTE, "Accept": "application/json"})
            with urllib.request.urlopen(pedido, timeout=20) as resposta:
                corpo = resposta.read(2_000_000)
            if corpo.strip():
                return json.loads(corpo)
        except urllib.error.HTTPError as erro:
            if erro.code == 404:
                return None
        except Exception:
            pass
        time.sleep(1.0 * (tentativa + 1))
    return None


def toca(url: str) -> bool:
    """Pede o começo do arquivo e confere que é vídeo de verdade."""
    try:
        pedido = urllib.request.Request(url, headers={"User-Agent": AGENTE, "Range": "bytes=0-2047"})
        with urllib.request.urlopen(pedido, timeout=12) as resposta:
            if resposta.status not in (200, 206):
                return False
            tipo = (resposta.headers.get("Content-Type") or "").lower().split(";")[0].strip()
            inicio = resposta.read(2048)
    except Exception:
        return False
    if b"#EXTM3U" in inicio[:64] or "mpegurl" in tipo:
        return inicio.lstrip().startswith(b"#EXTM3U")
    return tipo.startswith("video/") or tipo in (
        "application/octet-stream", "binary/octet-stream", "application/mp4",
        "application/x-matroska", "")


# MARK: - Cache em disco

class Guardado:
    """Um dicionário gravado em JSON, seguro entre threads."""

    def __init__(self, nome: str):
        self.caminho = CACHE / nome
        self.trava = threading.Lock()
        try:
            self.dados = json.loads(self.caminho.read_text(encoding="utf-8"))
        except Exception:
            self.dados = {}

    def get(self, chave, padrao=None):
        with self.trava:
            return self.dados.get(chave, padrao)

    def put(self, chave, valor):
        with self.trava:
            self.dados[chave] = valor

    def gravar(self):
        with self.trava:
            CACHE.mkdir(parents=True, exist_ok=True)
            temporario = self.caminho.with_suffix(".tmp")
            temporario.write_text(json.dumps(self.dados, ensure_ascii=False), encoding="utf-8")
            temporario.replace(self.caminho)


# MARK: - O acervo

def sem_ano(titulo: str) -> str:
    return re.sub(r"\s*\(\d{4}\)\s*$", "", titulo).strip()


def ler_fichas() -> dict[tuple[str, str], int]:
    """(tipo, título) -> id do TMDB, do arquivo que os apps já leem."""
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


def filmes_do_acervo(fichas: dict[tuple[str, str], int]) -> list[str]:
    """Os publicados e os que têm ficha mas saíram do acervo sem fonte."""
    titulos = []
    for arquivo in sorted(VOD.glob("filmes-*.txt")):
        for linha in arquivo.read_text(encoding="utf-8").splitlines():
            titulo = linha.split("\t", 1)[0]
            if titulo:
                titulos.append(titulo)
    titulos += [titulo for tipo, titulo in fichas if tipo == "f"]
    return list(dict.fromkeys(titulos))


def series_do_acervo() -> dict[str, dict]:
    """Título -> {ano, episódios [(temporada, número)]}, dos pedaços publicados."""
    anos = {}
    for indice in VOD.glob("series-*.txt"):
        if re.search(r"series-.+-\d+\.txt$", indice.name):
            continue
        for linha in indice.read_text(encoding="utf-8").splitlines():
            campos = linha.split("\t")
            if campos and campos[0]:
                anos[campos[0]] = campos[1] if len(campos) > 1 else ""
    series: dict[str, dict] = {}
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
            except (ValueError, IndexError):
                pass
    return series


# MARK: - Fenix

def idioma(texto: str) -> str:
    t = texto.lower()
    if "legendado" in t and "dual" not in t and "dublado" not in t:
        return "leg"
    return "dub"


def consultar(caminho: str, respostas: Guardado, contador: dict) -> list[list[str]]:
    """As fontes aproveitáveis de um filme ou episódio: [[idioma, url], ...]."""
    agora = time.time()
    guardada = respostas.get(caminho)
    if guardada and guardada.get("v") == VERSAO:
        validade = VALIDADE_ACHADO if guardada["f"] else VALIDADE_VAZIO
        if agora - guardada["t"] < validade:
            return [f for f in guardada["f"] if not vence(f[1])]
    with contador["trava"]:
        if contador["feitas"] >= contador["limite"]:
            return guardada["f"] if guardada else []
        contador["feitas"] += 1
    try:
        dados = pedir_json(f"{FENIX}/stream/{caminho}.json") or {}
    except Exception:
        return guardada["f"] if guardada else []

    fontes: list[list[str]] = []
    vistos = set()
    antigas = {url for _, url in (guardada or {}).get("f", [])}
    for bruto in dados.get("streams") or []:
        if not isinstance(bruto, dict):
            continue
        url = str(bruto.get("url") or "")
        if not url.startswith("http") or url in vistos:
            continue
        vistos.add(url)
        if vence(url):
            continue
        dicas = bruto.get("behaviorHints") or {}
        if isinstance(dicas, dict) and (dicas.get("proxyHeaders") or {}).get("request"):
            continue
        if url not in antigas and not toca(url):
            continue
        texto = " ".join(str(bruto.get(k) or "") for k in ("name", "title", "description"))
        fontes.append([idioma(texto), url])
    respostas.put(caminho, {"t": agora, "f": fontes, "v": VERSAO})
    return fontes


# MARK: - Andamento

class Andamento:
    def __init__(self, nome: str, total: int, a_cada: int = 50):
        self.nome, self.total, self.a_cada = nome, total, a_cada
        self.inicio = time.time()

    def linha(self, feitos: int, extra: str) -> None:
        if feitos % self.a_cada and feitos != self.total:
            return
        passou = max(time.time() - self.inicio, 0.001)
        ritmo = feitos / passou
        falta = (self.total - feitos) / ritmo if ritmo else 0
        h, m = divmod(int(falta) // 60, 60)
        print(f"[{time.strftime('%H:%M:%S')}] {self.nome}: {feitos}/{self.total} "
              f"({100 * feitos / max(self.total, 1):.1f}%) · {extra} · "
              f"{ritmo * 60:.0f}/min · falta ~{h}h{m:02d}", flush=True)


# MARK: - Aplicação como Fonte Reserva (Final da Lista)

def aplicar_filmes_reserva():
    links_file = SAIDA / "links-filmes.txt"
    if not links_file.exists():
        return
    fenix_filmes = {}
    for line in links_file.read_text(encoding="utf-8").splitlines():
        parts = line.strip().split("\t")
        if not parts or not parts[0]:
            continue
        t = parts[0]
        m = fenix_filmes.setdefault(t, {})
        for field in parts[1:]:
            if "=" in field:
                lang, urls_str = field.split("=", 1)
                m.setdefault(lang, []).extend(urls_str.split(","))

    changed_files = 0
    total_injected = 0
    for p in sorted(VOD.glob("filmes-*.txt")):
        lines = p.read_text(encoding="utf-8").splitlines()
        new_lines = []
        file_changed = False
        for line in lines:
            parts = line.strip().split("\t")
            if not parts or not parts[0]:
                new_lines.append(line)
                continue
            t = parts[0]
            if t in fenix_filmes:
                f_map = {}
                for field in parts[1:]:
                    if "=" in field:
                        l, u = field.split("=", 1)
                        f_map[l] = [x.strip() for x in u.split(",") if x.strip()]

                for lang, fenix_urls in fenix_filmes[t].items():
                    current = f_map.setdefault(lang, [])
                    for fu in fenix_urls:
                        # Adiciona SEMPRE ao final (reserva)
                        if fu not in current:
                            current.append(fu)
                            file_changed = True
                            total_injected += 1

                reconstructed = [t]
                for l in sorted(f_map.keys()):
                    reconstructed.append(f"{l}={','.join(f_map[l])}")
                new_lines.append("\t".join(reconstructed))
            else:
                new_lines.append(line)
        if file_changed:
            p.write_text("\n".join(new_lines) + "\n", encoding="utf-8")
            changed_files += 1

    print(f"Filmes: {total_injected} fontes reserva do Fenix aplicadas ao final das fontes em {changed_files} arquivos.")


def aplicar_series_reserva():
    links_file = SAIDA / "links-series.txt"
    if not links_file.exists():
        return
    fenix_series = {}
    cur_title = None
    for line in links_file.read_text(encoding="utf-8").splitlines():
        if line.startswith("@"):
            cur_title = line[1:].split("\t")[0].strip()
            continue
        parts = line.strip().split("\t")
        if len(parts) >= 4 and cur_title:
            try:
                s_num = int(parts[0])
                e_num = int(parts[1])
                audio = parts[2]
                urls = [u.strip() for u in parts[3].split(",") if u.strip()]
                fenix_series[(cur_title, s_num, e_num, audio)] = urls
            except ValueError:
                pass

    changed_files = 0
    total_injected = 0
    for p in sorted(VOD.glob("series-*-*.txt")):
        lines = p.read_text(encoding="utf-8").splitlines()
        new_lines = []
        cur_title = None
        file_changed = False
        for line in lines:
            if line.startswith("@"):
                cur_title = line[1:].split("\t")[0].strip()
                new_lines.append(line)
                continue
            parts = line.strip().split("\t")
            if len(parts) >= 4 and cur_title:
                try:
                    s_num = int(parts[0])
                    e_num = int(parts[1])
                    audio = parts[2]
                    current_srcs = [u.strip() for u in parts[3].split(",") if u.strip()]
                    key = (cur_title, s_num, e_num, audio)
                    if key in fenix_series:
                        added = False
                        for fu in fenix_series[key]:
                            # Adiciona SEMPRE ao final (reserva)
                            if fu not in current_srcs:
                                current_srcs.append(fu)
                                added = True
                                total_injected += 1
                        if added:
                            file_changed = True
                            new_lines.append(f"{s_num}\t{e_num}\t{audio}\t{','.join(current_srcs)}")
                            continue
                except ValueError:
                    pass
            new_lines.append(line)
        if file_changed:
            p.write_text("\n".join(new_lines) + "\n", encoding="utf-8")
            changed_files += 1

    print(f"Séries: {total_injected} episódios atualizados com fontes reserva do Fenix em {changed_files} arquivos.")


# MARK: - Principal

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--limite", type=int, default=1500, help="perguntas ao Fenix nesta rodada")
    parser.add_argument("--workers", type=int, default=32)
    parser.add_argument("--so-filmes", action="store_true")
    parser.add_argument("--so-series", action="store_true")
    parser.add_argument("--amostra", type=int, default=0, help="só os N primeiros títulos")
    parser.add_argument("--aplicar", action="store_true", help="aplica fontes aos arquivos VOD como reserva")
    args = parser.parse_args()

    fichas = ler_fichas()
    respostas = Guardado("respostas.json")
    contador = {"feitas": 0, "limite": args.limite, "trava": threading.Lock()}
    SAIDA.mkdir(parents=True, exist_ok=True)

    def gravar_caches():
        respostas.gravar()

    # ── Séries ──
    if not args.so_filmes:
        series = series_do_acervo()
        if args.amostra:
            series = dict(list(series.items())[:args.amostra])
        print(f"séries no acervo: {len(series)}", flush=True)

        def tmdb_da_serie(titulo: str) -> str:
            tmdb = fichas.get(("s", titulo)) or fichas.get(("s", sem_ano(titulo)))
            return str(tmdb) if tmdb else ""

        def sondar(titulo: str):
            eps = sorted(series[titulo]["eps"])
            if not eps or contador["feitas"] >= contador["limite"]:
                return titulo, "", []
            tmdb = tmdb_da_serie(titulo)
            if not tmdb:
                return titulo, "", []
            t, e = eps[0]
            return titulo, tmdb, consultar(f"series/tmdb:{tmdb}:{t}:{e}", respostas, contador)

        com_fonte: dict[str, str] = {}
        resultado: dict[str, dict] = {}
        andamento = Andamento("séries (1º episódio)", len(series))
        with ThreadPoolExecutor(args.workers) as grupo:
            futuros = [grupo.submit(sondar, t) for t in series]
            for n, futuro in enumerate(as_completed(futuros), 1):
                titulo, tmdb, fontes = futuro.result()
                if fontes:
                    com_fonte[titulo] = tmdb
                    primeiro = sorted(series[titulo]["eps"])[0]
                    resultado.setdefault(titulo, {})[primeiro] = fontes
                andamento.linha(n, f"o Fenix tem: {len(com_fonte)} · perguntas ao Fenix: {contador['feitas']}")
                if n % 500 == 0:
                    gravar_caches()
                if contador["feitas"] >= contador["limite"]:
                    break
        print(f"séries que o Fenix tem: {len(com_fonte)}", flush=True)

        def episodio(titulo: str, tmdb: str, t: int, e: int):
            return titulo, (t, e), consultar(f"series/tmdb:{tmdb}:{t}:{e}", respostas, contador)

        tarefas = [(titulo, tmdb, t, e) for titulo, tmdb in com_fonte.items()
                   for (t, e) in sorted(series[titulo]["eps"])[1:]]
        if tarefas and contador["feitas"] < contador["limite"]:
            andamento = Andamento("episódios", len(tarefas))
            with ThreadPoolExecutor(args.workers) as grupo:
                futuros = [grupo.submit(episodio, *tarefa) for tarefa in tarefas]
                for n, futuro in enumerate(as_completed(futuros), 1):
                    titulo, alvo, fontes = futuro.result()
                    if fontes:
                        resultado.setdefault(titulo, {})[alvo] = fontes
                    com = sum(len(v) for v in resultado.values())
                    andamento.linha(n, f"episódios com fonte: {com} · perguntas ao Fenix: {contador['feitas']}")
                    if n % 500 == 0:
                        gravar_caches()
                    if contador["feitas"] >= contador["limite"]:
                        break

        linhas = []
        for titulo in sorted(resultado):
            linhas.append(f"@{titulo}\t{series[titulo]['ano']}")
            for (temporada, numero), fontes in sorted(resultado[titulo].items()):
                por_idioma: dict[str, list[str]] = {}
                for lingua, url in fontes:
                    por_idioma.setdefault(lingua, []).append(url)
                for lingua, urls in sorted(por_idioma.items()):
                    linhas.append(f"{temporada}\t{numero}\t{lingua}\t{','.join(urls)}")
        if linhas:
            (SAIDA / "links-series.txt").write_text("\n".join(linhas) + "\n", encoding="utf-8")
        eps = sum(len(v) for v in resultado.values())
        print(f"séries com fonte do Fenix: {len(resultado)} ({eps} episódios)", flush=True)
        gravar_caches()

    # ── Filmes ──
    if not args.so_series and contador["feitas"] < contador["limite"]:
        titulos = filmes_do_acervo(fichas)
        if args.amostra:
            titulos = titulos[:args.amostra]
        print(f"filmes no acervo: {len(titulos)}", flush=True)

        def fontes_do_filme(titulo: str):
            if contador["feitas"] >= contador["limite"]:
                return titulo, []
            tmdb = fichas.get(("f", titulo)) or fichas.get(("f", sem_ano(titulo)))
            if not tmdb:
                return titulo, []
            return titulo, consultar(f"movie/tmdb:{tmdb}", respostas, contador)

        achados: dict[str, list[list[str]]] = {}
        andamento = Andamento("filmes", len(titulos))
        with ThreadPoolExecutor(args.workers) as grupo:
            futuros = [grupo.submit(fontes_do_filme, t) for t in titulos]
            for n, futuro in enumerate(as_completed(futuros), 1):
                titulo, fontes = futuro.result()
                if fontes:
                    achados[titulo] = fontes
                andamento.linha(n, f"com fonte: {len(achados)} · perguntas ao Fenix: {contador['feitas']}")
                if n % 500 == 0:
                    gravar_caches()
                if contador["feitas"] >= contador["limite"]:
                    break

        linhas = []
        for titulo in sorted(achados):
            por_idioma: dict[str, list[str]] = {}
            for lingua, url in achados[titulo]:
                por_idioma.setdefault(lingua, []).append(url)
            campos = [titulo] + [f"{l}={','.join(u)}" for l, u in sorted(por_idioma.items())]
            linhas.append("\t".join(campos))
        if linhas:
            (SAIDA / "links-filmes.txt").write_text("\n".join(linhas) + "\n", encoding="utf-8")
        print(f"filmes com fonte do Fenix: {len(achados)}", flush=True)
        gravar_caches()

    print(f"Perguntas ao Fenix nesta rodada: {contador['feitas']}")

    if args.aplicar:
        print("Aplicando fontes como reserva no acervo VOD...")
        if not args.so_series:
            aplicar_filmes_reserva()
        if not args.so_filmes:
            aplicar_series_reserva()
        print("Fontes reservas aplicadas com sucesso (sempre ao final da lista).")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
