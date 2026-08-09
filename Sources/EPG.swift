import Foundation
import Combine

struct Programme: Codable, Hashable, Identifiable {
    var title: String
    var desc: String
    var category: String
    var start: Date
    var stop: Date

    var id: String { "\(start.timeIntervalSince1970)-\(title)" }
    var duration: TimeInterval { stop.timeIntervalSince(start) }

    func progress(at now: Date = Date()) -> Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, now.timeIntervalSince(start) / duration))
    }
}

struct NowNext {
    var current: Programme
    var next: Programme?
    var progress: Double
    var remainingMinutes: Int
}

/// Electronic programme guide.
///
/// The reference implementation re-parsed a 16 MB XMLTV document on every
/// launch — and again whenever a channel registered — which is what made it
/// slow. Here the document is parsed exactly once, in the background, and only
/// the programmes belonging to our own channels inside a short window are kept.
/// The *parsed* result is what gets cached, so later launches skip parsing
/// entirely and the guide is on screen immediately.
@MainActor
final class EPGService: ObservableObject {
    static let shared = EPGService()

    enum State: Equatable {
        case idle, loading, ready, failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var updatedAt: Date?
    /// Bumped whenever the schedule changes, so views refresh.
    @Published private(set) var revision = 0
    @Published private(set) var matchedChannels = 0
    /// Ticks every 15s. Views read it so the "now" programme rolls over on its
    /// own — without it a row only refreshed when something else redrew it.
    @Published private(set) var clock = Date()

    private var byChannel: [UUID: [Programme]] = [:]
    private var refreshTimer: Timer?
    private var clockTimer: Timer?

    /// Tried in order; the first source carrying a channel wins, so the later
    /// ones only fill the gaps (Adult Swim, CNN Money, Universal…).
    private static let sourceURLs = [
        URL(string: "https://iptv-epg.org/files/epg-br.xml")!,
        URL(string: "https://www.open-epg.com/files/brazil3.xml")!,
    ]
    private static let cacheTTL: TimeInterval = 6 * 3600
    /// Kept deliberately short: a guide only ever shows a couple of days.
    private static let pastWindow: TimeInterval = 6 * 3600
    private static let futureWindow: TimeInterval = 3 * 86400

    private var cacheFile: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("dev.saimo.player", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("epg.json.z")
    }

    private init() {
        clockTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in
            Task { @MainActor in EPGService.shared.clock = Date() }
        }
    }

    // MARK: - Queries

    func programmes(for channel: Channel) -> [Programme] {
        byChannel[channel.id] ?? []
    }

    func hasGuide(for channel: Channel) -> Bool {
        !(byChannel[channel.id] ?? []).isEmpty
    }

    func nowNext(for channel: Channel, at now: Date = Date()) -> NowNext? {
        let list = byChannel[channel.id] ?? []
        guard !list.isEmpty else { return nil }

        // Programmes are stored sorted, so the current one is a binary search.
        var low = 0, high = list.count - 1, found = -1
        while low <= high {
            let mid = (low + high) / 2
            if list[mid].stop <= now {
                low = mid + 1
            } else if list[mid].start > now {
                high = mid - 1
            } else {
                found = mid
                break
            }
        }
        guard found >= 0 else { return nil }
        let current = list[found]
        return NowNext(
            current: current,
            next: found + 1 < list.count ? list[found + 1] : nil,
            progress: current.progress(at: now),
            remainingMinutes: max(0, Int(current.stop.timeIntervalSince(now) / 60)))
    }

    // MARK: - Loading

    func load(channels: [Channel]) {
        guard state != .loading else { return }

        if let cached = readCache(), !cached.isEmpty {
            byChannel = cached
            matchedChannels = cached.count
            state = .ready
            revision += 1
        }

        let expired = updatedAt.map { Date().timeIntervalSince($0) > Self.cacheTTL } ?? true
        let lineUpChanged = cachedSignature != Self.signature(of: channels)
        if expired || lineUpChanged { refresh(channels: channels) }
        scheduleRefresh(channels: channels)
    }

    func refresh(channels: [Channel]) {
        guard state != .loading else { return }
        if byChannel.isEmpty { state = .loading }

        let wanted = channels.map { (id: $0.id, name: $0.name) }
        Task.detached(priority: .utility) {
            do {
                let from = Date().addingTimeInterval(-EPGService.pastWindow)
                let to = Date().addingTimeInterval(EPGService.futureWindow)

                // Fetch every source at once, then merge in declared order.
                let payloads = try await withThrowingTaskGroup(of: (Int, Data?).self) { group in
                    for (index, url) in EPGService.sourceURLs.enumerated() {
                        group.addTask {
                            (index, try? await EPGService.download(url))
                        }
                    }
                    var result = [Int: Data]()
                    for try await (index, data) in group where data != nil {
                        result[index] = data
                    }
                    return result
                }
                guard !payloads.isEmpty else {
                    throw UpstreamError.transport("nenhuma fonte de EPG respondeu")
                }

                var merged: [UUID: [Programme]] = [:]
                for index in EPGService.sourceURLs.indices {
                    guard let data = payloads[index] else { continue }
                    let parsed = XMLTVParser.parse(data, wanted: wanted, from: from, to: to)
                    for (channel, programmes) in parsed where merged[channel] == nil {
                        merged[channel] = programmes
                    }
                }
                let signature = wanted.map(\.id.uuidString).sorted().joined(separator: ",")
                await MainActor.run {
                    EPGService.shared.apply(merged, signature: signature)
                }
            } catch {
                await MainActor.run {
                    Log.shared.write("EPG falhou: \(error.localizedDescription)")
                    if EPGService.shared.byChannel.isEmpty {
                        EPGService.shared.state = .failed(error.localizedDescription)
                    } else {
                        EPGService.shared.state = .ready
                    }
                }
            }
        }
    }

    private func apply(_ parsed: [UUID: [Programme]], signature: String) {
        byChannel = parsed
        matchedChannels = parsed.count
        updatedAt = Date()
        cachedSignature = signature
        state = .ready
        revision += 1
        writeCache(parsed, signature: signature)
        let total = parsed.values.reduce(0) { $0 + $1.count }
        Log.shared.write("EPG: \(total) programas em \(parsed.count) canais")
    }

    private func scheduleRefresh(channels: [Channel]) {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: Self.cacheTTL, repeats: true) { _ in
            Task { @MainActor in EPGService.shared.refresh(channels: channels) }
        }
    }

    /// gzip is requested explicitly: the payload drops from 16 MB to 4 MB.
    private static func download(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
        request.setValue(Upstream.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 60

        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession(configuration: config).data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw UpstreamError.transport("EPG HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        return data
    }

    // MARK: - Cache

    private struct CacheFile: Codable {
        var updatedAt: Date
        /// Identifies the channel line-up the cache was matched against; a new
        /// or removed channel invalidates it even while it is still fresh.
        var signature: String?
        var channels: [String: [Programme]]
    }

    private var cachedSignature: String?

    private static func signature(of channels: [Channel]) -> String {
        channels.map(\.id.uuidString).sorted().joined(separator: ",")
    }

    private func readCache() -> [UUID: [Programme]]? {
        guard let raw = try? Data(contentsOf: cacheFile),
              let json = try? (raw as NSData).decompressed(using: .zlib) as Data,
              let file = try? JSONDecoder().decode(CacheFile.self, from: json)
        else { return nil }

        updatedAt = file.updatedAt
        cachedSignature = file.signature
        var out: [UUID: [Programme]] = [:]
        let cutoff = Date().addingTimeInterval(-Self.pastWindow)
        for (key, list) in file.channels {
            guard let id = UUID(uuidString: key) else { continue }
            let fresh = list.filter { $0.stop > cutoff }
            if !fresh.isEmpty { out[id] = fresh }
        }
        return out
    }

    private func writeCache(_ data: [UUID: [Programme]], signature: String) {
        var channels: [String: [Programme]] = [:]
        for (id, list) in data { channels[id.uuidString] = list }
        let file = CacheFile(updatedAt: Date(), signature: signature, channels: channels)
        guard let json = try? JSONEncoder().encode(file),
              let squeezed = try? (json as NSData).compressed(using: .zlib) as Data
        else { return }
        try? squeezed.write(to: cacheFile, options: .atomic)
    }
}

// MARK: - XMLTV parsing

/// Byte-level scanner over the XMLTV document. It never builds a String for the
/// whole 16 MB payload and only materialises text for programmes that belong to
/// a channel we actually carry.
enum XMLTVParser {
    /// Display names in the feed that differ from ours.
    static let aliases: [String: String] = [
        "history": "history channel",
        "sony channel": "sony",
        "sportv 2": "sportv2",
        "sportv 3": "sportv3",
        "gnt": "gnt hd",
        "band": "band sp",
        "warner": "warner channel",
        "sbt": "sbt sp",
        "globo rj": "globo rj",
        "globonews": "globonews",
    ]

    static func normalise(_ s: String) -> String {
        var text = decodeEntities(s)
        if let range = text.range(of: #"^[A-Z]{2}\s*[-|]\s*"#, options: .regularExpression) {
            text.removeSubrange(range)
        }
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                  locale: Locale(identifier: "pt_BR"))
        var out = ""
        var lastWasSpace = true
        for ch in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(ch) {
                out.unicodeScalars.append(ch)
                lastWasSpace = false
            } else if !lastWasSpace {
                out.append(" ")
                lastWasSpace = true
            }
        }

        // Feeds decorate names with quality/country suffixes — "Adult Swim HD BR",
        // "CNN Brasil Money HD BR". Dropping them makes one alias table work
        // across every source. "brasil" is kept: it is part of real names.
        var tokens = out.trimmingCharacters(in: .whitespaces).split(separator: " ")
        let noise: Set<String> = ["hd", "sd", "fhd", "uhd", "4k", "br"]
        while let last = tokens.last, noise.contains(String(last)), tokens.count > 1 {
            tokens.removeLast()
        }
        return tokens.joined(separator: " ")
    }

    static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        return s.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
    }

    static func parse(_ data: Data, wanted: [(id: UUID, name: String)],
                      from: Date, to: Date) -> [UUID: [Programme]] {
        let bytes = [UInt8](data)

        // 1. display-name -> xmltv id
        var nameToXML: [String: String] = [:]
        var cursor = 0
        while let open = find(bytes, "<channel id=\"", from: cursor) {
            guard let idEnd = find(bytes, "\"", from: open + 13),
                  let close = find(bytes, "</channel>", from: idEnd) else { break }
            let xmlID = string(bytes, open + 13, idEnd)
            if let dnOpen = find(bytes, "<display-name", from: idEnd, before: close),
               let dnText = find(bytes, ">", from: dnOpen, before: close),
               let dnEnd = find(bytes, "</display-name>", from: dnText, before: close) {
                let key = normalise(string(bytes, dnText + 1, dnEnd))
                if nameToXML[key] == nil { nameToXML[key] = xmlID }
            }
            cursor = close + 10
        }

        // 2. our channels -> xmltv id
        var xmlToChannel: [String: UUID] = [:]
        var matched = 0
        for entry in wanted {
            let key = normalise(entry.name)
            var xmlID = nameToXML[key]
            if xmlID == nil, let alias = aliases[key] { xmlID = nameToXML[alias] }
            if xmlID == nil {
                // Last resort: a feed name that starts with ours (or the reverse).
                xmlID = nameToXML.first { $0.key.hasPrefix(key) || key.hasPrefix($0.key) }?.value
            }
            if let xmlID {
                xmlToChannel[xmlID] = entry.id
                matched += 1
            }
        }
        guard matched > 0 else { return [:] }

        // 3. programmes, filtered to those channels and the time window
        var out: [UUID: [Programme]] = [:]
        cursor = 0
        while let open = find(bytes, "<programme ", from: cursor) {
            guard let attrsEnd = find(bytes, ">", from: open + 11),
                  let close = find(bytes, "</programme>", from: attrsEnd) else { break }
            cursor = close + 12

            guard let chOpen = find(bytes, "channel=\"", from: open, before: attrsEnd),
                  let chEnd = find(bytes, "\"", from: chOpen + 9, before: attrsEnd) else { continue }
            let xmlID = string(bytes, chOpen + 9, chEnd)
            guard let channelID = xmlToChannel[xmlID] else { continue }

            guard let sOpen = find(bytes, "start=\"", from: open, before: attrsEnd),
                  let sEnd = find(bytes, "\"", from: sOpen + 7, before: attrsEnd),
                  let eOpen = find(bytes, "stop=\"", from: open, before: attrsEnd),
                  let eEnd = find(bytes, "\"", from: eOpen + 6, before: attrsEnd),
                  let start = parseXMLTVDate(string(bytes, sOpen + 7, sEnd)),
                  let stop = parseXMLTVDate(string(bytes, eOpen + 6, eEnd)),
                  stop > from, start < to
            else { continue }

            guard let tOpen = find(bytes, "<title", from: attrsEnd, before: close),
                  let tText = find(bytes, ">", from: tOpen, before: close),
                  let tEnd = find(bytes, "</title>", from: tText, before: close) else { continue }
            let title = decodeEntities(string(bytes, tText + 1, tEnd))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }

            var desc = ""
            if let dOpen = find(bytes, "<desc", from: attrsEnd, before: close),
               let dText = find(bytes, ">", from: dOpen, before: close),
               let dEnd = find(bytes, "</desc>", from: dText, before: close) {
                desc = decodeEntities(string(bytes, dText + 1, dEnd))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            var category = ""
            if let cOpen = find(bytes, "<category", from: attrsEnd, before: close),
               let cText = find(bytes, ">", from: cOpen, before: close),
               let cEnd = find(bytes, "</category>", from: cText, before: close) {
                category = decodeEntities(string(bytes, cText + 1, cEnd))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }

            out[channelID, default: []].append(
                Programme(title: title, desc: desc, category: category, start: start, stop: stop))
        }

        for key in out.keys {
            out[key]?.sort { $0.start < $1.start }
        }
        return out
    }

    // MARK: Byte helpers

    private static func find(_ bytes: [UInt8], _ needle: String,
                             from: Int, before limit: Int = .max) -> Int? {
        let pattern = [UInt8](needle.utf8)
        guard !pattern.isEmpty else { return nil }
        let end = min(limit, bytes.count) - pattern.count
        guard from <= end else { return nil }
        let first = pattern[0]
        var i = from
        while i <= end {
            if bytes[i] == first {
                var match = true
                for k in 1..<pattern.count where bytes[i + k] != pattern[k] {
                    match = false
                    break
                }
                if match { return i }
            }
            i += 1
        }
        return nil
    }

    private static func string(_ bytes: [UInt8], _ start: Int, _ end: Int) -> String {
        guard start < end, end <= bytes.count else { return "" }
        return String(decoding: bytes[start..<end], as: UTF8.self)
    }

    /// XMLTV timestamps look like `20260809153000 -0300`.
    static func parseXMLTVDate(_ s: String) -> Date? {
        let digits = s.prefix(14)
        guard digits.count == 14 else { return nil }
        func number(_ lower: Int, _ upper: Int) -> Int? {
            let start = digits.index(digits.startIndex, offsetBy: lower)
            let end = digits.index(digits.startIndex, offsetBy: upper)
            return Int(digits[start..<end])
        }
        guard let year = number(0, 4), let month = number(4, 6), let day = number(6, 8),
              let hour = number(8, 10), let minute = number(10, 12), let second = number(12, 14)
        else { return nil }

        var offset = 0
        let tail = s.dropFirst(14).trimmingCharacters(in: .whitespaces)
        if tail.count >= 5, let sign = tail.first, sign == "+" || sign == "-" {
            let body = tail.dropFirst()
            if let hh = Int(body.prefix(2)), let mm = Int(body.dropFirst(2).prefix(2)) {
                offset = (hh * 3600 + mm * 60) * (sign == "-" ? -1 : 1)
            }
        }

        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        components.hour = hour; components.minute = minute; components.second = second
        components.timeZone = TimeZone(secondsFromGMT: offset)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: components)
    }
}
