import Foundation

/// The channel line-up, downloaded on every launch.
///
/// Publishing the list means a dead link is fixed by editing one file, with
/// nothing to recompile or reinstall. The built-in catalogue stays as the floor:
/// the app opens on the last list it managed to read — cached from the previous
/// run, or the compiled one — and swaps in the fresh one when it arrives, so a
/// missing network never costs the user their channels.
enum RemoteCatalog {

    private static let base = "https://raw.githubusercontent.com/gabrielsaimo/SaimoPlayer/main/"
    /// The whole catalogue, with ClearKey, Referer and User-Agent. This is the
    /// list that rules: editing this file swaps a link with nothing to rebuild.
    static let url = URL(string: base + "catalogo.txt")!
    /// Extras published separately, as M3U. An M3U has nowhere to keep a key or
    /// a header, so it joins as a spare and never replaces the catalogue.
    static let extrasURL = URL(string: base + "canais.txt")!

    /// Whatever is available right now, without touching the network.
    static func cached() -> [Channel] {
        let base = read("catalogo.txt")
        let extras = read("canais.txt")
        guard !base.isEmpty || !extras.isEmpty else { return defaultChannels }
        return merge(base: base, published: extras)
    }

    private static func read(_ name: String) -> [Channel] {
        guard let text = try? String(contentsOf: cacheFile(name), encoding: .utf8) else {
            return []
        }
        return parse(text)
    }

    /// Joins the published list to the catalogue instead of replacing it.
    ///
    /// The catalogue carries what the published list has no way of carrying:
    /// the ClearKey of the DRM channels, the Referer and User-Agent some CDNs
    /// demand, and the order the sources should be tried in. Replacing one with
    /// the other would throw all of that away. Matching by name, each channel
    /// keeps its catalogue sources first and gains the published ones behind
    /// them as spares; anything that exists only in the published list joins the
    /// end as a new channel.
    static func merge(base: [Channel], published: [Channel]) -> [Channel] {
        let principal = base.isEmpty ? defaultChannels : base
        var extra: [String: Channel] = [:]
        for channel in published { extra[chaveDeCanal(channel.name)] = channel }

        var used: Set<String> = []
        let merged = principal.map { channel -> Channel in
            let key = chaveDeCanal(channel.name)
            guard let incoming = extra[key] else { return channel }
            used.insert(key)
            let known = Set(channel.variants.map(\.url))
            let novos = incoming.variants.filter { !known.contains($0.url) }
            guard !novos.isEmpty else { return channel }
            var copy = channel
            copy.variants += novos
            return copy
        }
        return merged + published.filter { !used.contains(chaveDeCanal($0.name)) }
    }

    /// Nome reduzido ao que identifica o canal, para casar as duas listas.
    ///
    /// As duas fontes escrevem o mesmo canal de jeitos diferentes: "Cinemax" e
    /// "Cinemax HD", "SporTV 2" e "SPORTV2". Casando só pelo nome normalizado
    /// do EPG, esses pares não se encontravam e o canal aparecia duas vezes na
    /// lista. Aqui a marca de qualidade sai e o número gruda separado da
    /// palavra, que é o bastante para os dois lados chegarem na mesma chave.
    ///
    /// Fica separado do `XMLTVParser.normalise` de propósito: aquele casa nome
    /// de canal com programação, onde "HD" às vezes é o que distingue duas
    /// grades diferentes.
    static func chaveDeCanal(_ nome: String) -> String {
        var texto = XMLTVParser.normalise(nome)
        texto = texto.replacingOccurrences(
            of: #"\b(hd|sd|fhd|uhd|4k|hq)\b"#, with: " ", options: .regularExpression)
        texto = texto.replacingOccurrences(
            of: #"([a-z])(\d)"#, with: "$1 $2", options: .regularExpression)
        texto = texto.replacingOccurrences(
            of: #"(\d)([a-z])"#, with: "$1 $2", options: .regularExpression)
        return texto.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Downloads the published list. Returns nil when it cannot be read, so the
    /// caller keeps what it already had rather than emptying the list.
    static func fetch() async -> [Channel]? {
        async let baixado = download(url, into: "catalogo.txt")
        async let extras = download(extrasURL, into: "canais.txt")
        let (base, publicados) = await (baixado, extras)
        guard !base.isEmpty || !publicados.isEmpty else { return nil }

        let merged = merge(base: base.isEmpty ? read("catalogo.txt") : base,
                           published: publicados.isEmpty ? read("canais.txt") : publicados)
        return merged.isEmpty ? nil : merged
    }

    /// Downloads and keeps a copy. Returns empty when nothing usable came back,
    /// so the caller falls back to what is already on disk.
    private static func download(_ from: URL, into name: String) async -> [Channel] {
        var request = URLRequest(url: from)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        request.setValue(Upstream.userAgent, forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode)
        else { return [] }

        let channels = parse(String(decoding: data, as: UTF8.self))
        guard !channels.isEmpty else { return [] }
        try? data.write(to: cacheFile(name), options: .atomic)
        return channels
    }

    // MARK: - Parsing

    /// One `chave: valor` per line. `canal:` opens a channel, `fonte:` adds a
    /// source, and referer/agente/chave belong to the source above them.
    static func parse(_ text: String) -> [Channel] {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#EXTM3U") {
            return parseM3u(text)
        }
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

    private static func parseM3u(_ text: String) -> [Channel] {
        var out: [String: Channel] = [:]
        
        var currentTvgId: String?
        var currentName: String?
        var currentLogo: String?
        var currentLabel: String?

        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line == "#EXTM3U" { continue }

            if line.hasPrefix("#EXTINF:") {
                if let range = line.range(of: "tvg-id=\"([^\"]+)\"", options: .regularExpression) {
                    let match = String(line[range])
                    let start = match.index(match.startIndex, offsetBy: 8)
                    let end = match.index(before: match.endIndex)
                    currentTvgId = String(match[start..<end])
                    if currentTvgId?.isEmpty == true { currentTvgId = nil }
                } else {
                    currentTvgId = nil
                }

                if let range = line.range(of: "tvg-logo=\"([^\"]+)\"", options: .regularExpression) {
                    let match = String(line[range])
                    let start = match.index(match.startIndex, offsetBy: 10)
                    let end = match.index(before: match.endIndex)
                    currentLogo = String(match[start..<end])
                } else {
                    currentLogo = nil
                }

                var inQuotes = false
                var commaIdx: String.Index? = nil
                for i in line.indices {
                    if line[i] == "\"" { inQuotes.toggle() }
                    if line[i] == "," && !inQuotes {
                        commaIdx = i
                        break
                    }
                }
                
                let rawName: String
                if let commaIdx = commaIdx {
                    rawName = String(line[line.index(after: commaIdx)...]).trimmingCharacters(in: .whitespaces)
                } else if let lastComma = line.lastIndex(of: ",") {
                    rawName = String(line[line.index(after: lastComma)...]).trimmingCharacters(in: .whitespaces)
                } else {
                    rawName = line
                }
                
                let cleanedName = rawName.replacingOccurrences(of: "\\s*\\([^)]+\\)$", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
                currentName = currentTvgId ?? cleanedName
                
                if let match = rawName.range(of: "\\(([^)]+)\\)$", options: .regularExpression) {
                    currentLabel = String(rawName[match])
                } else {
                    currentLabel = nil
                }
                
            } else if !line.hasPrefix("#") {
                if let name = currentName, let url = URL(string: line) {
                    if var existing = out[name] {
                        existing.variants.append(Variant(url: url, label: currentLabel))
                        if existing.logo == nil, let currentLogo = currentLogo {
                            existing.logo = URL(string: currentLogo)
                        }
                        out[name] = existing
                    } else {
                        out[name] = Channel(name: name, variants: [Variant(url: url, label: currentLabel)], logo: currentLogo.flatMap(URL.init(string:)))
                    }
                }
                currentLabel = nil
            }
        }
        return withKnownLogos(Array(out.values))
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

    private static func cacheFile(_ name: String) -> URL {
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SaimoTV", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(name)
    }
}
