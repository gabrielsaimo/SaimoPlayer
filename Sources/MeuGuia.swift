import Foundation

/// Programme guide scraped from meuguia.tv.
///
/// The XMLTV feeds carry the wrong schedule for several channels — HBO was
/// showing a line-up that did not match what was actually on air — so this
/// takes priority for the channels it covers and the feeds only fill the gaps.
///
/// One page per channel, listing a couple of weeks of programming under day
/// headers, so a fetch is cheap and the parse is a single pass over the markup.
enum MeuGuia {
    /// Catalog name -> meuguia channel code.
    static let codes: [String: String] = [
        "A&E": "MDO", "Animal Planet": "APL", "Band": "BAN", "Cartoon Network": "CAR",
        "Cinemax": "MNX", "Combate": "135", "Discovery Kids": "DIK",
        "Discovery World": "DIW", "ESPN": "ESP", "ESPN 2": "ES2", "ESPN 4": "ES4",
        "GNT": "GNT", "Globo RJ": "GRD", "Globo SP": "GRD", "GloboNews": "GLN",
        "Gloob": "GOB", "HBO": "HBO", "HBO Family": "HFA", "HBO Plus": "HPL",
        "HBO2": "HB2", "History": "HIS", "Megapix": "MPX", "Record": "REC",
        "SBT": "SBT", "Space": "SPA",
        "SporTV": "SPO", "SporTV 2": "SP2", "SporTV 3": "SP3",
        "TNT": "TNT", "TNT Séries": "TBS", "Telecine Action": "TC2", "Telecine Pipoca": "TC4",
        "Telecine Premium": "TC1", "Universal TV": "USA", "Warner": "WBT",
    ]

    private static let timeZone = TimeZone(identifier: "America/Sao_Paulo") ?? .current

    static func fetch(wanted: [(id: UUID, name: String)],
                      from: Date, to: Date) async -> [UUID: [Programme]] {
        let targets = wanted.compactMap { entry -> (UUID, String)? in
            guard let code = codes[entry.name] else { return nil }
            return (entry.id, code)
        }
        guard !targets.isEmpty else { return [:] }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25
        config.httpMaximumConnectionsPerHost = 4
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config)

        var out: [UUID: [Programme]] = [:]
        await withTaskGroup(of: (UUID, [Programme]).self) { group in
            for (id, code) in targets {
                group.addTask {
                    guard let url = URL(string: "https://meuguia.tv/programacao/canal/\(code)") else {
                        return (id, [])
                    }
                    var request = URLRequest(url: url)
                    request.setValue(Upstream.userAgent, forHTTPHeaderField: "User-Agent")
                    guard let (data, response) = try? await session.data(for: request),
                          let http = response as? HTTPURLResponse,
                          (200...299).contains(http.statusCode) else { return (id, []) }
                    let html = String(decoding: data, as: UTF8.self)
                    return (id, parse(html).filter { $0.stop > from && $0.start < to })
                }
            }
            for await (id, programmes) in group where !programmes.isEmpty {
                out[id] = programmes
            }
        }
        return out
    }

    /// The page is a flat list of `<li>` items: day headers followed by their
    /// programmes, each carrying a start time, a title and a genre. End times
    /// are not published, so a programme runs until the next one starts.
    ///
    /// Parsing item by item rather than scanning the whole document keeps ads
    /// and dividers between entries from swallowing the ones that follow.
    static func parse(_ html: String) -> [Programme] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.dateComponents([.year, .month, .day], from: Date())

        var day = today
        var partial: [(start: Date, title: String, category: String)] = []

        for item in html.components(separatedBy: "<li") {
            if item.contains("subheader") {
                if let parsed = readDay(item, today: today) { day = parsed }
                continue
            }
            guard let clock = between(item, "lileft time'>", "<") ?? between(item, "lileft time\">", "<")
            else { continue }
            let hm = clock.trimmingCharacters(in: .whitespaces).split(separator: ":")
            guard hm.count == 2, let hour = Int(hm[0]), let minute = Int(hm[1]),
                  let title = between(item, "<h2>", "</h2>")?
                    .trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty
            else { continue }

            var components = day
            components.hour = hour
            components.minute = minute
            guard let start = calendar.date(from: components) else { continue }

            let category = between(item, "<h3>", "</h3>")?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            partial.append((start,
                            XMLTVParser.decodeEntities(title),
                            XMLTVParser.decodeEntities(category)))
        }

        // nowNext() binary-searches this list, so ordering is an invariant the
        // page layout happens to satisfy but must not be trusted to.
        partial.sort { $0.start < $1.start }

        return partial.enumerated().map { index, item in
            let stop = index + 1 < partial.count
                ? partial[index + 1].start
                : item.start.addingTimeInterval(3600)
            return Programme(title: item.title, desc: "", category: item.category,
                             start: item.start, stop: stop)
        }
    }

    // MARK: - Pieces

    /// Day headers read "domingo, 9/8" — no year, so it comes from the calendar
    /// with a rollover when the listing crosses into January.
    private static func readDay(_ item: String, today: DateComponents) -> DateComponents? {
        guard let text = between(item, ">", "<", after: "subheader"),
              let comma = text.firstIndex(of: ","),
              let currentMonth = today.month, let currentYear = today.year
        else { return nil }

        let parts = text[text.index(after: comma)...]
            .trimmingCharacters(in: .whitespaces)
            .split(separator: "/")
        guard parts.count == 2, let d = Int(parts[0]), let m = Int(parts[1]) else { return nil }

        var day = DateComponents()
        day.day = d
        day.month = m
        day.year = m < currentMonth ? currentYear + 1 : currentYear
        return day
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
