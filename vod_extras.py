#!/usr/bin/env python3
"""Resolvedores neutros para fontes VOD adicionais do Saimo.

Não executa JavaScript e não depende do Kodi. Todas as consultas usam IDs
exatos (IMDb/TMDB), limitam resposta/tempo e recusam endereços locais.
"""

from __future__ import annotations

import base64
import html
import ipaddress
import json
import re
import socket
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import asdict, dataclass


USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/152.0 Safari/537.36"
)
FENIX_ROOT = (
    "https://fenixflix.fenixhub.online/"
    "qualities=4k,1080p,720p,sd,cam%7Caudio=dublado,legendado%7C"
    "catalogs=populares_movie,populares_series,recentes_movie,recentes_series"
)
MGEB_ROOT = "https://mgeb.top"
NHD_ROOT = "https://nhdapi.com"
IMDB_RE = re.compile(r"^tt\d{5,10}$", re.I)
TMDB_RE = re.compile(r"^\d+$")
URL_RE = re.compile(r'''(?i)https?:\\?/\\?/[^\s"'<>\\]{8,4096}''')
ATTR_RE = re.compile(
    r'''(?is)(?:src|file|source|url|hls|playlist|manifest)\s*[:=]\s*["']([^"']{4,4096})["']'''
)
IFRAME_RE = re.compile(r'''(?is)<iframe[^>]+(?:src|data-src)\s*=\s*["']([^"']+)["']''')
ATOB_RE = re.compile(r'''(?is)atob\(\s*["']([A-Za-z0-9+/=_-]{20,8192})["']\s*\)''')
MEDIA_RE = re.compile(r"(?i)\.(?:m3u8|mpd|mp4|mkv|webm|avi|mov|m4v|ts)(?:$|[?#&])")
SAFE_HEADERS = {
    "user-agent": "User-Agent", "referer": "Referer", "origin": "Origin",
    "accept": "Accept", "accept-language": "Accept-Language", "cookie": "Cookie",
    "authorization": "Authorization", "x-api-key": "X-Api-Key", "x-auth-token": "X-Auth-Token",
}


@dataclass(frozen=True)
class VodSource:
    provider: str
    url: str
    language: str
    quality: str
    kind: str
    title: str = ""
    headers: tuple[tuple[str, str], ...] = ()
    online: bool | None = None

    def json(self) -> dict:
        value = asdict(self)
        value["headers"] = dict(self.headers)
        return value


def _safe_url(value: str, base: str = "") -> str:
    value = html.unescape(str(value or "")).strip().strip('"\'')
    value = value.replace("\\/", "/").replace("\\u002F", "/").replace("\\u003A", ":")
    if value.startswith("//"):
        value = "https:" + value
    elif base and value.startswith("/"):
        value = urllib.parse.urljoin(base, value)
    parsed = urllib.parse.urlsplit(value)
    if parsed.scheme not in {"http", "https"} or not parsed.hostname or parsed.username:
        return ""
    host = parsed.hostname.lower().rstrip(".")
    if host == "localhost" or host.endswith((".localhost", ".local")):
        return ""
    try:
        if not ipaddress.ip_address(host).is_global:
            return ""
    except ValueError:
        pass
    return value


def _request(url: str, headers: dict[str, str] | None = None, limit: int = 2_000_000) -> tuple[bytes, str, dict]:
    merged = {"User-Agent": USER_AGENT, "Accept": "*/*", "Accept-Language": "pt-BR,pt;q=0.9,en;q=0.7"}
    merged.update(headers or {})
    request = urllib.request.Request(url, headers=merged)
    with urllib.request.urlopen(request, timeout=10) as response:
        body = response.read(limit + 1)
        if len(body) > limit:
            raise ValueError("resposta-grande")
        return body, response.geturl(), dict(response.headers.items())


def _json(url: str) -> dict:
    body, _, _ = _request(url, {"Accept": "application/json"}, 6_000_000)
    value = json.loads(body.decode("utf-8", "replace"))
    return value if isinstance(value, dict) else {"items": value}


def _language(*values: str, fallback: str = "dub") -> str:
    text = " ".join(str(value or "") for value in values).lower()
    if "legendado" in text or re.search(r"(^|\W)leg(\W|$)", text):
        return "leg"
    if "dublado" in text or re.search(r"(^|\W)dub(\W|$)", text):
        return "dub"
    return fallback


def _quality(*values: str) -> str:
    text = " ".join(str(value or "") for value in values).lower()
    match = re.search(r"(?<!\d)(4k|2160p|1080p|720p|480p|360p|sd|cam)(?!\d)", text)
    return match.group(1).upper().replace("2160P", "4K") if match else ""


def _kind(url: str, content_type: str = "") -> str:
    probe = (url + " " + content_type).lower()
    if ".m3u8" in probe or "mpegurl" in probe:
        return "hls"
    if ".mpd" in probe or "dash+xml" in probe:
        return "dash"
    if MEDIA_RE.search(probe) or content_type.lower().startswith(("video/", "audio/")):
        return "progressive"
    return "unknown"


def probe(source: VodSource) -> VodSource:
    headers = dict(source.headers)
    headers.setdefault("Range", "bytes=0-8191")
    try:
        body, final_url, response_headers = _request(source.url, headers, 131_072)
        ctype = response_headers.get("Content-Type", "")
        clean = body.lstrip()
        kind = _kind(final_url, ctype)
        if clean.startswith(b"#EXTM3U"):
            kind, online = "hls", True
        elif b"<MPD" in clean[:8192] or "dash+xml" in ctype.lower():
            kind, online = "dash", True
        elif (
            ctype.lower().startswith(("video/", "audio/"))
            or (len(body) >= 12 and body[4:8] == b"ftyp")
            or body.startswith(b"\x1aE\xdf\xa3")
        ):
            kind, online = "progressive", True
        else:
            online = kind in {"hls", "dash", "progressive"} and not clean.lower().startswith((b"<html", b"<!doctype", b"{"))
        return VodSource(**{**source.__dict__, "kind": kind, "online": online})
    except Exception:
        return VodSource(**{**source.__dict__, "online": False})


def fenix_sources(imdb: str, media_type: str = "movie", season: int = 0, episode: int = 0,
                  validate: bool = False) -> list[VodSource]:
    if not IMDB_RE.fullmatch(imdb or ""):
        raise ValueError("IMDb inválido")
    if media_type == "series":
        suffix = f"series/{imdb}:{int(season)}:{int(episode)}.json"
    else:
        suffix = f"movie/{imdb}.json"
    payload = _json(f"{FENIX_ROOT}/stream/{suffix}")
    output: list[VodSource] = []
    seen: set[str] = set()
    for raw in payload.get("streams") or []:
        if not isinstance(raw, dict):
            continue
        url = _safe_url(raw.get("url"))
        if not url or url in seen:
            continue
        seen.add(url)
        hints = raw.get("behaviorHints") or {}
        proxy_headers = hints.get("proxyHeaders") if isinstance(hints, dict) else {}
        request_headers = proxy_headers.get("request") if isinstance(proxy_headers, dict) else {}
        safe: list[tuple[str, str]] = []
        if isinstance(request_headers, dict):
            for name, value in request_headers.items():
                canonical = SAFE_HEADERS.get(str(name).lower())
                value = str(value or "").strip()
                if canonical and value and "\r" not in value and "\n" not in value and len(value) <= 4096:
                    safe.append((canonical, value))
        title = " ".join(str(raw.get(key) or "") for key in ("name", "title", "description")).strip()
        source = VodSource(
            "FenixFlix", url, _language(title), _quality(title), _kind(url),
            title=title, headers=tuple(safe),
        )
        checked = probe(source) if validate else source
        if not validate or checked.online:
            output.append(checked)
    return output


def _decoded_variants(text: str) -> list[str]:
    text = html.unescape(text)
    variants = [text, text.replace("\\/", "/").replace("\\u002F", "/").replace("\\u003A", ":")]
    for match in ATOB_RE.finditer(text):
        try:
            token = match.group(1) + "=" * ((4 - len(match.group(1)) % 4) % 4)
            variants.append(base64.b64decode(token).decode("utf-8", "replace"))
        except Exception:
            pass
    return list(dict.fromkeys(variants))


def _extract_page(text: str, page_url: str) -> tuple[list[str], list[str]]:
    media: list[str] = []
    pages: list[str] = []
    for variant in _decoded_variants(text):
        iframe_values = {_safe_url(match.group(1), page_url) for match in IFRAME_RE.finditer(variant)}
        for value in iframe_values:
            if value and value not in pages:
                pages.append(value)
        for pattern in (ATTR_RE, URL_RE):
            for match in pattern.finditer(variant):
                raw = match.group(1) if pattern is ATTR_RE else match.group(0)
                value = _safe_url(raw, page_url)
                if not value or value in iframe_values or value in media:
                    continue
                parsed = urllib.parse.urlsplit(value)
                lower = value.lower()
                strong = bool(MEDIA_RE.search(lower) or any(word in lower for word in ("playlist", "manifest", "hls.php")))
                page_like = parsed.path.startswith(("/embed/", "/movie/", "/tv/", "/dl/"))
                if strong and not page_like:
                    media.append(value)
    return media[:16], pages[:3]


def _embed_routes(provider: str, media_type: str, identifier: str, season: int, episode: int) -> list[str]:
    root = MGEB_ROOT if provider == "mgeb" else NHD_ROOT
    if provider == "mgeb":
        if media_type == "movie":
            base = f"{root}/embed/{identifier}"
            return [base, base + "?player=clappr", base + "?player=vidstack"]
        slash = f"{root}/embed/{identifier}/{season}/{episode}"
        return [slash, f"{root}/embed/{identifier}-{season}-{episode}", slash + "?player=clappr"]
    if media_type == "movie":
        return [f"{root}/dl/movie/{identifier}", f"{root}/movie/{identifier}", f"{root}/embed/movie/{identifier}"]
    return [
        f"{root}/dl/tv/{identifier}/{season}/{episode}",
        f"{root}/tv/{identifier}/{season}/{episode}",
        f"{root}/embed/tv/{identifier}/{season}/{episode}",
    ]


def _nhd_api_sources(page_text: str, page_url: str, validate: bool) -> list[VodSource]:
    """Reproduz o fetchStream público declarado pela própria página NHD."""
    path_match = re.search(r'''(?m)\bvar\s+API_PATH\s*=\s*["']([^"']+)["']''', page_text)
    key_match = re.search(r'''(?m)\bvar\s+API_KEY\s*=\s*["']([^"']*)["']''', page_text)
    providers_match = re.search(r"(?m)\bvar\s+PROVIDER_LIST\s*=\s*(\[[^;]+\])", page_text)
    if not path_match:
        return []
    api_path = _safe_url(path_match.group(1), page_url)
    api_key = key_match.group(1) if key_match else ""
    try:
        providers = json.loads(providers_match.group(1)) if providers_match else []
    except Exception:
        providers = []
    attempts: list[str | None] = [None] + [str(item) for item in providers[:10]]
    output: list[VodSource] = []
    seen: set[str] = set()
    for provider_name in attempts:
        if not api_path or len(output) >= 5:
            break
        parts = urllib.parse.urlsplit(api_path)
        query = urllib.parse.parse_qsl(parts.query, keep_blank_values=True)
        query.append(("_ts", "1"))
        if api_key:
            query.append(("key", api_key))
        if provider_name:
            query.extend((("provider", provider_name), ("fresh", "1")))
        endpoint = urllib.parse.urlunsplit(
            (parts.scheme, parts.netloc, parts.path, urllib.parse.urlencode(query), "")
        )
        try:
            payload = _json(endpoint)
        except Exception:
            continue
        if not payload.get("success"):
            continue
        rows: list[tuple[str, str, str]] = []
        rows.append((str(payload.get("playUrl") or ""), "leg", str(payload.get("provider") or provider_name or "NHD")))
        audio_tracks = payload.get("audioTracks") or []
        if isinstance(audio_tracks, list):
            for track in audio_tracks:
                if not isinstance(track, dict):
                    continue
                track_url = str(track.get("url") or track.get("playUrl") or track.get("file") or "")
                track_label = " ".join(str(track.get(key) or "") for key in ("label", "name", "language", "title"))
                rows.append((track_url, _language(track_label, fallback="leg"), track_label))
        for raw_url, language, label in rows:
            url = _safe_url(raw_url, page_url)
            if not url or url in seen:
                continue
            seen.add(url)
            kind = str(payload.get("kind") or "hls").lower()
            source = VodSource(
                "NHD", url, language, _quality(label), "progressive" if kind == "mp4" else kind,
                title=label or str(payload.get("provider") or "NHD"),
                headers=(("Referer", page_url),),
            )
            checked = probe(source) if validate else source
            if not validate or checked.online:
                output.append(checked)
    return output


def embed_sources(provider: str, tmdb: str = "", imdb: str = "", media_type: str = "movie",
                  season: int = 0, episode: int = 0, validate: bool = True) -> list[VodSource]:
    provider = provider.lower()
    if provider not in {"mgeb", "nhd"}:
        raise ValueError("provider deve ser mgeb ou nhd")
    identifiers = []
    if TMDB_RE.fullmatch(tmdb or ""):
        identifiers.append(tmdb)
    if IMDB_RE.fullmatch(imdb or "") and imdb not in identifiers:
        identifiers.append(imdb)
    if not identifiers:
        raise ValueError("TMDB/IMDb exato ausente")
    if media_type == "series" and (int(season) < 0 or int(episode) < 1):
        raise ValueError("episódio inválido")

    candidates: list[tuple[str, str]] = []
    seen_pages: set[str] = set()
    for identifier in identifiers:
        for route in _embed_routes(provider, media_type, identifier, season, episode):
            queue = [(route, (MGEB_ROOT if provider == "mgeb" else NHD_ROOT) + "/")]
            while queue and len(seen_pages) < 12:
                page, referer = queue.pop(0)
                if page in seen_pages:
                    continue
                seen_pages.add(page)
                try:
                    body, final_url, _ = _request(page, {"Referer": referer})
                except Exception:
                    continue
                page_text = body.decode("utf-8", "replace")
                if provider == "nhd":
                    api_sources = _nhd_api_sources(page_text, final_url, validate)
                    if api_sources:
                        return api_sources
                media, nested = _extract_page(page_text, final_url)
                for url in media:
                    if all(existing[0] != url for existing in candidates):
                        candidates.append((url, final_url))
                if media:
                    break
                queue.extend((url, final_url) for url in nested if url not in seen_pages)
            if candidates:
                break
        if candidates:
            break

    name = "MegaEmbed" if provider == "mgeb" else "NHD"
    language = "dub" if provider == "mgeb" else "leg"
    output: list[VodSource] = []
    for url, referer in candidates[:12]:
        source = VodSource(
            name, url, language, "", _kind(url), title=name,
            headers=(("Referer", referer),),
        )
        checked = probe(source) if validate else source
        if not validate or checked.online:
            output.append(checked)
        if len(output) >= 5:
            break
    return output
