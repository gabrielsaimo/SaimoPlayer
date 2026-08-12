import Foundation

/// The channel line-up, downloaded on every launch.
///
/// Publishing the list means a dead link is fixed by editing one file, with
/// nothing to recompile or reinstall. The built-in catalogue stays as the floor:
/// the app opens on the last list it managed to read — cached from the previous
/// run, or the compiled one — and swaps in the fresh one when it arrives, so a
/// missing network never costs the user their channels.
enum RemoteCatalog {

    static let url = URL(string:
        "https://raw.githubusercontent.com/gabrielsaimo/SaimoPlayer/main/canais.txt")!

    /// Whatever is available right now, without touching the network.
    static func cached() -> [Channel] {
        guard let text = try? String(contentsOf: cacheFile, encoding: .utf8) else {
            return defaultChannels
        }
        let parsed = parse(text)
        return parsed.isEmpty ? defaultChannels : parsed
    }

    /// Downloads the published list. Returns nil when it cannot be read, so the
    /// caller keeps what it already had rather than emptying the list.
    static func fetch() async -> [Channel]? {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        request.setValue(Upstream.userAgent, forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode)
        else { return nil }

        let channels = parse(String(decoding: data, as: UTF8.self))
        guard !channels.isEmpty else { return nil }
        try? data.write(to: cacheFile, options: .atomic)
        return channels
    }

    // MARK: - Parsing

    /// One `chave: valor` per line. `canal:` opens a channel, `fonte:` adds a
    /// source, and referer/agente/chave belong to the source above them.
    static func parse(_ text: String) -> [Channel] {
        var channels: [Channel] = []
        var name: String?
        var logo: String?
        var variants: [Variant] = []

        func flush() {
            if let name, !variants.isEmpty {
                channels.append(Channel(name: name, variants: variants,
                                        logo: logo.flatMap(URL.init(string:))))
            }
            name = nil; logo = nil; variants = []
        }

        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let field = line[line.startIndex..<colon].lowercased()
            let value = line[line.index(after: colon)...]
                .trimmingCharacters(in: .whitespaces)
            if value.isEmpty { continue }

            switch field {
            case "canal":
                flush()
                name = value
            case "logo":
                logo = value
            case "fonte":
                guard let url = URL(string: value) else { continue }
                variants.append(Variant(url: url))
            case "referer":
                if !variants.isEmpty { variants[variants.count - 1].referer = value }
            case "agente":
                if !variants.isEmpty { variants[variants.count - 1].userAgent = value }
            case "chave":
                // KID:CHAVE — o AVFoundation só precisa da chave, mas o arquivo
                // carrega o par porque o lado Android exige os dois.
                guard !variants.isEmpty else { continue }
                variants[variants.count - 1].clearKey =
                    value.contains(":") ? String(value.split(separator: ":").last!) : value
            default:
                continue
            }
        }
        flush()
        return withKnownLogos(channels)
    }

    /// A published entry without a `logo:` line falls back to the compiled one.
    /// The list is edited by hand, and a channel losing its icon because a line
    /// was dropped would be a silent regression on every screen at once.
    private static func withKnownLogos(_ channels: [Channel]) -> [Channel] {
        let known = Dictionary(defaultChannels.compactMap { channel in
            channel.logo.map { (channel.name.lowercased(), $0) }
        }, uniquingKeysWith: { first, _ in first })
        return channels.map { channel in
            guard channel.logo == nil, let logo = known[channel.name.lowercased()] else {
                return channel
            }
            var copy = channel
            copy.logo = logo
            return copy
        }
    }

    // MARK: - Cache

    private static var cacheFile: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SaimoTV", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("canais.txt")
    }
}
