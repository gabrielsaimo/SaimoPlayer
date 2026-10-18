import Foundation

/// Guia de programação extraído de guiadetv.com.
///
/// Cobre 121+ canais da TV aberta, fechada, esportes e filmes com horários precisos no
/// fuso de Brasília, sem bloqueio 429 e com sinopse em 99,8% dos programas.
/// É a fonte primária rápida do aplicativo.
enum GuiaDeTv {
    private static let timeZone = TimeZone(identifier: "America/Sao_Paulo") ?? .current

    /// Nome normalizado -> endereço da página, da tabela `guia.txt`.
    static func slug(for name: String, em slugs: [String: String] = GuiaTabelas.atual.guiadetv) -> String? {
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
        let tabela = GuiaTabelas.atual.guiadetv
        for entry in wanted {
            guard let s = slug(for: entry.name, em: tabela) else { continue }
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
                    guard let url = GuiaTabelas.paginaDoGuiaDeTv(slug) else {
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
