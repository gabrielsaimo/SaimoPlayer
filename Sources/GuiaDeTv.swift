import Foundation

/// Guia de programação extraído de guiadetv.com.
///
/// Cobre 121+ canais da TV aberta, fechada, esportes e filmes com horários precisos no
/// fuso de Brasília, sem bloqueio 429 e com sinopse em 99,8% dos programas.
/// É a fonte primária rápida do aplicativo.
enum GuiaDeTv {
    /// Nome normalizado -> slug do guiadetv.com.
    static let slugs: [String: String] = [
        "a e": "ae",
        "ae": "ae",
        "agro": "agro",
        "agro mais": "agro",
        "canal agro": "agro",
        "amc": "amc",
        "animal planet": "animal-planet",
        "arte 1": "arte-1",
        "arte1": "arte-1",
        "axn": "axn",
        "band": "band",
        "band sp": "band",
        "band campinas": "band",
        "band curitiba": "band",
        "band mg": "band",
        "band para": "band",
        "band recife tv tribuna": "band",
        "band rn": "band",
        "band rs": "band",
        "band sergipe": "band",
        "band rj": "band-rj",
        "band news": "bandnews",
        "bandnews": "bandnews",
        "band sports": "bandsports",
        "bandsports": "bandsports",
        "bbc world": "bbc-world",
        "bbc world news": "bbc-world",
        "bis": "bis",
        "bloomberg": "bloomberg",
        "box kids": "box-kids",
        "box kids tv": "box-kids",
        "canal educacao": "canal-educacao",
        "canal rural": "canal-rural",
        "canal uol": "canal-uol",
        "cancao nova": "cancao-nova",
        "cartoon network": "cartoon-network",
        "cartoonito": "cartoonito",
        "cinemax": "cinemax",
        "cnn brasil": "cnn-brasil",
        "combate": "combate",
        "curta": "curta",
        "discovery channel": "discovery-channel",
        "discovery home health": "discovery-home-health",
        "discovery h h": "discovery-home-health",
        "discovery kids": "discovery-kids",
        "discovery science": "discovery-science",
        "discovery theater": "discovery-theater",
        "discovery turbo": "discovery-turbo",
        "discovery world": "discovery-world",
        "discovery id": "investigacao-discovery",
        "investigacao discovery": "investigacao-discovery",
        "investigation discovery": "investigacao-discovery",
        "e": "e",
        "espn": "espn",
        "espn 2": "espn-2",
        "espn 3": "espn-3",
        "espn 4": "espn-4",
        "espn 5": "espn-5",
        "espn 6": "espn-6",
        "film arts": "film-arts",
        "food network": "food-network",
        "fox news": "fox-news",
        "futura": "futura",
        "canal futura": "futura",
        "ge tv": "ge-tv",
        "getv": "ge-tv",
        "globo news": "globo-news",
        "globonews": "globo-news",
        "globo rj": "globo-rio-de-janeiro",
        "globo rio de janeiro": "globo-rio-de-janeiro",
        "globo": "globo-sp",
        "globo sp": "globo-sp",
        "globo am": "globo-sp",
        "globo ce": "globo-sp",
        "globo df": "globo-sp",
        "globo es": "globo-sp",
        "globo go": "globo-sp",
        "globo mg": "globo-sp",
        "globo pb": "globo-sp",
        "globo pe": "globo-sp",
        "globo rs": "globo-sp",
        "gloob": "gloob",
        "gloobinho": "gloobinho",
        "gnt": "gnt",
        "hbo": "hbo",
        "hbo 2": "hbo-2",
        "hbo2": "hbo-2",
        "hbo family": "hbo-family",
        "hbo mundi": "hbo-mundi",
        "hbo plus": "hbo-plus",
        "hbo pop": "hbo-pop",
        "hbo signature": "hbo-signature",
        "hbo xtreme": "hbo-xtreme",
        "hgtv": "hgtv",
        "history": "history",
        "history channel": "history",
        "history 2": "history-2",
        "h2": "history-2",
        "jovem pan news": "jovem-pan-news",
        "lifetime": "lifetime",
        "lifetime movies": "lifetime",
        "megapix": "megapix",
        "multishow": "multishow",
        "music box brazil": "music-box-brazil",
        "n sports": "nsports",
        "nsports": "nsports",
        "n sports jogo 1": "nsports",
        "off": "off",
        "canal off": "off",
        "premiere": "premiere-fc",
        "premiere clubes": "premiere-fc",
        "premiere fc": "premiere-fc",
        "premiere 2": "premiere-2",
        "premiere 3": "premiere-3",
        "premiere 4": "premiere-4",
        "premiere 5": "premiere-5",
        "premiere 6": "premiere-6",
        "premiere 7": "premiere-7",
        "prime box brazil": "prime-box-brazil",
        "record news": "record-news",
        "record": "record-tv",
        "record tv": "record-tv",
        "record sp": "record-tv",
        "record go": "record-tv",
        "record mg": "record-tv",
        "record rj": "record-tv",
        "record internacional": "record-tv",
        "recordtv": "record-tv",
        "rede brasil": "rede-brasil",
        "rede familia": "rede-familia",
        "rede gospel": "rede-gospel",
        "redetv": "rede-tv",
        "rede tv": "rede-tv",
        "rede vida": "rede-vida",
        "sbt": "sbt",
        "sbt sp": "sbt",
        "sbt alterosa": "sbt",
        "sbt ba": "sbt",
        "sbt go": "sbt",
        "sbt interior": "sbt",
        "sbt londrina": "sbt",
        "sbt maringa": "sbt",
        "sbt mg": "sbt",
        "sbt pi": "sbt",
        "sbt pr": "sbt",
        "sbt news": "sbt-news",
        "sbt rj": "sbt-rio-de-janeiro",
        "sbt rio de janeiro": "sbt-rio-de-janeiro",
        "sony": "sony",
        "sony channel": "sony",
        "sony movies": "sony-movies",
        "space": "space",
        "sportv": "sportv",
        "sportv 2": "sportv-2",
        "sportv2": "sportv-2",
        "sportv 3": "sportv-3",
        "sportv3": "sportv-3",
        "sportynet": "sportynet",
        "sportynet 01": "sportynet",
        "sportynet 4": "sportynet",
        "sportynet 1": "sportynet",
        "sportynet 2": "sportynet",
        "sportynet 3": "sportynet",
        "studio universal": "studio-universal",
        "syfy": "syfy",
        "usa network": "syfy",
        "tcm": "tcm",
        "telecine action": "telecine-action",
        "telecine cult": "telecine-cult",
        "telecine fun": "telecine-fun",
        "telecine pipoca": "telecine-pipoca",
        "telecine premium": "telecine-premium",
        "telecine touch": "telecine-touch",
        "terra viva": "terra-viva",
        "tlc": "tlc",
        "tnt": "tnt",
        "tnt novelas": "tnt-novelas",
        "tnt series": "tnt-series",
        "tooncast": "tooncast",
        "travel box brazil": "travel-box-brasil",
        "travel box brasil": "travel-box-brasil",
        "trutv": "trutv",
        "adult swim": "trutv",
        "tv aparecida": "tv-aparecida",
        "tv brasil": "tv-brasil",
        "tv camara": "tv-camara",
        "tv cultura": "tv-cultura",
        "cultura": "tv-cultura",
        "tv gazeta": "tv-gazeta",
        "gazeta": "tv-gazeta",
        "tv ra tim bum": "tv-ra-tim-bum",
        "ra tim bum": "tv-ra-tim-bum",
        "tv senado": "tv-senado",
        "universal tv": "universal-tv",
        "universal channel": "universal-tv",
        "viva": "viva",
        "canal viva": "viva",
        "globoplay novelas": "viva",
        "warner": "warner",
        "warner channel": "warner",
        "woohoo": "woohoo",
        "x sports": "xsports",
        "xsports": "xsports",
    ]

    private static let timeZone = TimeZone(identifier: "America/Sao_Paulo") ?? .current

    static func slug(for name: String) -> String? {
        let clean = name.replacingOccurrences(
            of: #"\s*\((?:s\d+|ot|rk|b\d+|alt)\)\s*$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        let key = XMLTVParser.normalise(clean)
        return slugs[key] ?? slugs[XMLTVParser.normalise(name)]
    }

    static func fetch(wanted: [(id: UUID, name: String)],
                      from: Date, to: Date) async -> [UUID: [Programme]] {
        // Agrupar canais por slug para baixar cada página apenas uma vez
        var slugToIDs: [String: [UUID]] = [:]
        for entry in wanted {
            guard let s = slug(for: entry.name) else { continue }
            slugToIDs[s, default: []].append(entry.id)
        }
        guard !slugToIDs.isEmpty else { return [:] }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25
        config.httpMaximumConnectionsPerHost = 6
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config)

        var out: [UUID: [Programme]] = [:]
        await withTaskGroup(of: (String, [Programme]).self) { group in
            for slug in slugToIDs.keys {
                group.addTask {
                    guard let url = URL(string: "https://www.guiadetv.com/canal/\(slug)") else {
                        return (slug, [])
                    }
                    var request = URLRequest(url: url)
                    request.setValue(Upstream.userAgent, forHTTPHeaderField: "User-Agent")
                    guard let (data, response) = try? await session.data(for: request),
                          let http = response as? HTTPURLResponse,
                          (200...299).contains(http.statusCode) else { return (slug, []) }
                    let html = String(decoding: data, as: UTF8.self)
                    return (slug, parse(html).filter { $0.stop > from && $0.start < to })
                }
            }
            for await (slug, programmes) in group where !programmes.isEmpty {
                if let ids = slugToIDs[slug] {
                    for id in ids {
                        out[id] = programmes
                    }
                }
            }
        }
        return out
    }

    /// `https://www.guiadetv.com/canal/<slug>`
    /// Cada programa é um `<li class="flex gap-4 ...">` com:
    /// - `<time datetime="AAAA-MM-DDTHH:MM:SS-03:00">HH:MM</time>`
    /// - `<span class="text-xs ...">1h30</span>`
    /// - `<a href="/programa/..." ...>Título</a>`
    /// - `<p class="mt-1 ...">Sinopse...</p>`
    static func parse(_ html: String) -> [Programme] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        var items: [(start: Date, duration: TimeInterval, title: String, desc: String)] = []

        for li in html.components(separatedBy: "<li") {
            guard let dt = between(li, "datetime=\"", "\"", after: "<time"),
                  dt.count >= 19 else { continue }

            // "2026-10-16T09:40:00-03:00"
            let ano = Int(dt.prefix(4)) ?? 0
            let mes = Int(dt.dropFirst(5).prefix(2)) ?? 0
            let dia = Int(dt.dropFirst(8).prefix(2)) ?? 0
            let hora = Int(dt.dropFirst(11).prefix(2)) ?? 0
            let minuto = Int(dt.dropFirst(14).prefix(2)) ?? 0
            guard ano > 2000, mes >= 1, mes <= 12, dia >= 1, dia <= 31 else { continue }

            var comps = DateComponents()
            comps.year = ano
            comps.month = mes
            comps.day = dia
            comps.hour = hora
            comps.minute = minuto
            comps.second = 0
            guard let start = calendar.date(from: comps) else { continue }

            guard let rawTitle = between(li, ">", "</a>", after: "/programa/") else { continue }
            let title = XMLTVParser.decodeEntities(rawTitle).trimmingCharacters(in: .whitespacesAndNewlines)
            guard title.count > 1 else { continue }

            var duration: TimeInterval = 3600
            if let durText = between(li, ">", "</span>", after: "</time>") {
                let trimmed = durText.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.contains("h") {
                    let parts = trimmed.split(separator: "h")
                    let h = Int(parts[0]) ?? 0
                    let m = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
                    duration = TimeInterval(h * 3600 + m * 60)
                } else if trimmed.hasSuffix("min") {
                    let mins = Int(trimmed.dropLast(3).trimmingCharacters(in: .whitespaces)) ?? 0
                    if mins > 0 { duration = TimeInterval(mins * 60) }
                }
            }

            let desc = between(li, ">", "</p>", after: "<p")
                .map { XMLTVParser.decodeEntities($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""

            items.append((start: start, duration: duration, title: title, desc: desc))
        }

        items.sort { $0.start < $1.start }

        // Deduplicar mesmo horário de início
        var unique: [(start: Date, duration: TimeInterval, title: String, desc: String)] = []
        for item in items {
            if let last = unique.last, last.start == item.start { continue }
            unique.append(item)
        }

        return unique.enumerated().map { index, item in
            var stop = item.start.addingTimeInterval(item.duration)
            if index + 1 < unique.count {
                let nextStart = unique[index + 1].start
                if stop > nextStart || abs(stop.timeIntervalSince(nextStart)) <= 60 {
                    stop = nextStart
                }
            }
            return Programme(title: item.title, desc: item.desc, category: "",
                             start: item.start, stop: stop)
        }
    }

    private static func between(_ text: String, _ open: String, _ close: String,
                                after marker: String? = nil) -> String? {
        var searchFrom = text.startIndex
        if let marker {
            guard let m = text.range(of: marker) else { return nil }
            searchFrom = m.upperBound
        }
        guard let a = text.range(of: open, range: searchFrom..<text.endIndex),
              let b = text.range(of: close, range: a.upperBound..<text.endIndex)
        else { return nil }
        return String(text[a.upperBound..<b.lowerBound])
    }
}
