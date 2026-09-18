#!/usr/bin/env python3
"""Coleta fontes FenixFlix, MegaEmbed e NHD por IDs exatos."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path

from vod_extras import VodSource, embed_sources, fenix_sources


ROOT = Path(__file__).resolve().parent
DEFAULT_OUTPUT = ROOT / "arquivos-gerados" / "fontes-vod-extras"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--titulo", required=True)
    parser.add_argument("--imdb", required=True)
    parser.add_argument("--tmdb", default="")
    parser.add_argument("--tipo", choices=("movie", "series"), default="movie")
    parser.add_argument("--temporada", type=int, default=0)
    parser.add_argument("--episodio", type=int, default=0)
    parser.add_argument(
        "--provedores", default="fenix,mgeb,nhd",
        help="lista separada por vírgulas: fenix,mgeb,nhd",
    )
    parser.add_argument("--sem-validar", action="store_true")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    return parser.parse_args()


def compact_line(title: str, sources: list[VodSource]) -> str:
    fields = [title]
    for language in ("dub", "leg"):
        urls = list(dict.fromkeys(source.url for source in sources if source.language == language))
        if urls:
            fields.append(language + "=" + ",".join(urls))
    return "\t".join(fields)


def main() -> int:
    args = parse_args()
    requested = {item.strip().lower() for item in args.provedores.split(",") if item.strip()}
    invalid = requested - {"fenix", "mgeb", "nhd"}
    if invalid:
        raise SystemExit("Provedor desconhecido: " + ", ".join(sorted(invalid)))
    sources: list[VodSource] = []
    errors: dict[str, str] = {}
    validate = not args.sem_validar

    for provider in ("fenix", "mgeb", "nhd"):
        if provider not in requested:
            continue
        try:
            if provider == "fenix":
                found = fenix_sources(
                    args.imdb, args.tipo, args.temporada, args.episodio, validate=validate
                )
            else:
                found = embed_sources(
                    provider, args.tmdb, args.imdb, args.tipo,
                    args.temporada, args.episodio, validate=validate,
                )
            sources.extend(found)
            print(f"{provider}: {len(found)} fonte(s)")
        except Exception as exc:
            errors[provider] = f"{type(exc).__name__}: {exc}"
            print(f"{provider}: falhou ({type(exc).__name__})")

    # URLs iguais aparecem uma vez, preservando a ordem dos provedores.
    unique: list[VodSource] = []
    seen: set[str] = set()
    for source in sources:
        if source.url not in seen:
            seen.add(source.url)
            unique.append(source)
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "fontes-teste.txt").write_text(
        compact_line(args.titulo, unique) + ("\n" if unique else ""), encoding="utf-8"
    )
    (args.output / "fontes-teste.json").write_text(
        json.dumps(
            {
                "titulo": args.titulo, "imdb": args.imdb, "tmdb": args.tmdb,
                "tipo": args.tipo, "fontes": [source.json() for source in unique],
                "erros": errors,
            },
            ensure_ascii=False, indent=2,
        ) + "\n",
        encoding="utf-8",
    )
    m3u = ["#EXTM3U"]
    for index, source in enumerate(unique, 1):
        label = "Legendado" if source.language == "leg" else "Dublado"
        quality = f" {source.quality}" if source.quality else ""
        m3u.extend([
            f'#EXTINF:-1 group-title="Filmes" provider="{source.provider}" '
            f'audio="{source.language}",{args.titulo} — {label}{quality} — {source.provider} {index}',
            source.url,
        ])
    (args.output / "fontes-teste.m3u").write_text("\n".join(m3u) + "\n", encoding="utf-8")
    with (args.output / "fontes-teste.csv").open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["provider", "idioma", "qualidade", "tipo", "online", "url"])
        for source in unique:
            writer.writerow([
                source.provider, source.language, source.quality,
                source.kind, source.online, source.url,
            ])
    print(f"Total: {len(unique)} | saída: {args.output}")
    return 0 if unique else 1


if __name__ == "__main__":
    raise SystemExit(main())
