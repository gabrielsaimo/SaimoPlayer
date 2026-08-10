import Foundation
import Darwin

/// Local HTTP server that re-serves any upstream HLS stream under a stable,
/// player-friendly URL:
///
///     http://127.0.0.1:<port>/proxy/<UUID>/<UUID>.m3u8
///
/// Playlists are rewritten so every segment / key / variant is routed back
/// through this server, which means the player never talks to the upstream
/// host directly and never has to resolve it.
final class ProxyServer {
    static let shared = ProxyServer()

    private(set) var port: UInt16 = 0
    private var listenFD: Int32 = -1
    private var channels: [UUID: Channel] = [:]
    private let lock = NSLock()

    private init() {}

    // MARK: - Registry

    func register(_ channel: Channel) {
        lock.lock(); channels[channel.id] = channel; lock.unlock()
    }

    /// HEVC inside MPEG-TS decodes to a black picture on AVFoundation, so those
    /// streams are routed through the ffmpeg remux. The verdict is cached per
    /// variant after the first look at the upstream playlist.
    private var remuxVerdict: [String: Bool] = [:]
    /// Which source of a channel is currently in use; advanced on failure.
    private var activeVariant: [UUID: Int] = [:]

    func variantIndex(_ channel: Channel) -> Int {
        lock.lock(); defer { lock.unlock() }
        return min(activeVariant[channel.id] ?? 0, channel.variants.count - 1)
    }

    func variant(_ channel: Channel) -> Variant {
        channel.variants[variantIndex(channel)]
    }

    private func setVariant(_ channel: Channel, _ index: Int) {
        lock.lock(); activeVariant[channel.id] = index; lock.unlock()
    }

    private func needsRemux(_ channel: Channel, _ variant: Variant) -> Bool {
        let key = "\(channel.id.uuidString)#\(variant.url.absoluteString)"
        lock.lock()
        if let cached = remuxVerdict[key] { lock.unlock(); return cached }
        lock.unlock()

        guard Remuxer.shared.isAvailable else { return false }
        var verdict = variant.isDASH
        if !verdict, let res = try? Upstream.shared.fetch(variant.url, referer: variant.referer) {
            let text = String(decoding: res.body.prefix(64_000), as: UTF8.self).lowercased()
            verdict = text.contains("hvc1") || text.contains("hev1")
        }
        lock.lock(); remuxVerdict[key] = verdict; lock.unlock()
        if verdict && !variant.isDASH {
            Log.shared.write("\(channel.name): HEVC em TS — usando remux")
        }
        return verdict
    }

    func channel(_ id: UUID) -> Channel? {
        lock.lock(); defer { lock.unlock() }
        return channels[id]
    }

    /// Address the generated links point at.
    ///
    /// AirPlay video hands the URL to the receiver, which then fetches it
    /// itself — a loopback address would send the Apple TV to its own port.
    /// The LAN address works for both the Mac and the receiver, and falls back
    /// to loopback when the machine is offline.
    var advertisedHost: String {
        ProxyServer.lanAddress() ?? "127.0.0.1"
    }

    /// The generated, playable link for a channel.
    ///
    /// Starts the server if it has not run yet: SwiftUI initialises the App's
    /// stored properties before its `init` body, so the model could ask for a
    /// link — and get port 0 — before `start()` had been called. The first
    /// channel then failed to play until the viewer switched away and back.
    func link(for channel: Channel) -> URL {
        if listenFD < 0 { try? start() }
        let id = channel.id.uuidString
        return URL(string: "http://\(advertisedHost):\(port)/proxy/\(id)/\(id).m3u8")!
    }

    /// First non-loopback IPv4 address of an active interface.
    static func lanAddress() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }

        var candidates: [(name: String, address: String)] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(pointer.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
                  let sa = pointer.pointee.ifa_addr,
                  sa.pointee.sa_family == UInt8(AF_INET) else { continue }

            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(sa, socklen_t(sa.pointee.sa_len), &buffer,
                              socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0
            else { continue }
            let address = String(cString: buffer)
            guard !address.hasPrefix("169.254.") else { continue }   // self-assigned
            candidates.append((String(cString: pointer.pointee.ifa_name), address))
        }
        // Wi-Fi/Ethernet first, then anything else (VPN, bridges…).
        return candidates.first { $0.name.hasPrefix("en") }?.address ?? candidates.first?.address
    }

    // MARK: - Lifecycle

    @discardableResult
    func start(preferredPort: UInt16 = 30002) throws -> UInt16 {
        if listenFD >= 0 { return port }

        // A player that closes a connection early must not kill the process.
        signal(SIGPIPE, SIG_IGN)

        for candidate in [preferredPort, 0] {
            let fd = socket(AF_INET, SOCK_STREAM, 0)
            guard fd >= 0 else { continue }
            var yes: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = candidate.bigEndian
            // Bound to every interface so an AirPlay receiver on the same
            // network can pull the stream; loopback alone would break it.
            addr.sin_addr.s_addr = INADDR_ANY.bigEndian
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)

            let bound = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            guard bound == 0, listen(fd, 32) == 0 else { close(fd); continue }

            var actual = sockaddr_in()
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            withUnsafeMutablePointer(to: &actual) { ptr in
                _ = ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    getsockname(fd, $0, &len)
                }
            }
            listenFD = fd
            port = UInt16(bigEndian: actual.sin_port)
            break
        }

        guard listenFD >= 0 else {
            throw UpstreamError.transport("não consegui abrir porta local")
        }

        Log.shared.write("proxy em http://\(advertisedHost):\(port)")
        Thread.detachNewThread { [weak self] in self?.acceptLoop() }
        return port
    }

    private func acceptLoop() {
        while listenFD >= 0 {
            let client = accept(listenFD, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                break
            }
            var yes: Int32 = 1
            setsockopt(client, IPPROTO_TCP, TCP_NODELAY, &yes, socklen_t(MemoryLayout<Int32>.size))
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.handle(client)
                close(client)
            }
        }
    }

    // MARK: - Connection handling

    private func handle(_ fd: Int32) {
        guard let head = readHead(fd) else { return }
        let firstLine = head.components(separatedBy: "\r\n").first ?? ""
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return }
        let method = String(parts[0])
        let target = String(parts[1])

        guard method == "GET" || method == "HEAD" else {
            send(fd, status: 405, headers: [:], body: Data(), headOnly: true)
            return
        }

        let segments = target.split(separator: "/").map(String.init)

        // /health
        if segments.first == "health" {
            send(fd, status: 200, headers: ["Content-Type": "text/plain"],
                 body: Data("ok\n".utf8), headOnly: method == "HEAD")
            return
        }

        // /channels — registered channels and their generated links
        if segments.first == "channels" {
            lock.lock()
            let list = channels.values.map { c in
                ["id": c.id.uuidString, "name": c.name,
                 "link": link(for: c).absoluteString, "source": c.source.absoluteString]
            }
            lock.unlock()
            let json = (try? JSONSerialization.data(withJSONObject: list,
                                                    options: [.prettyPrinted])) ?? Data()
            send(fd, status: 200, headers: ["Content-Type": "application/json"],
                 body: json, headOnly: method == "HEAD")
            return
        }

        // /proxy/<uuid>/<uuid>.m3u8   or   /proxy/<uuid>/s/<b64>
        guard segments.count >= 3, segments[0] == "proxy",
              let channelID = UUID(uuidString: segments[1]),
              let channel = channel(channelID) else {
            send(fd, status: 404, headers: [:], body: Data("not found".utf8),
                 headOnly: method == "HEAD")
            return
        }

        // /proxy/<uuid>/manifest.mpd — DASH manifest, normalised for ffmpeg.
        //
        // Several CDNs send the manifest chunked with no Content-Length, and
        // ffmpeg's dash demuxer calls avio_size() on it and gives up ("Unable
        // to read to manifest"). Serving our own copy fixes the length and an
        // injected absolute BaseURL keeps the segment references pointing at
        // the original CDN.
        if segments[2].hasPrefix("manifest") {
            do {
                let active = variant(channel)
                let res = try Upstream.shared.fetch(active.url, referer: active.referer)
                let xml = normaliseMPD(String(decoding: res.body, as: UTF8.self),
                                       source: res.finalURL)
                send(fd, status: 200,
                     headers: [
                        "Content-Type": "application/dash+xml",
                        "Cache-Control": "no-cache, no-store",
                     ],
                     body: Data(xml.utf8), headOnly: method == "HEAD")
            } catch {
                Log.shared.write("erro no manifest de \(channel.name): \(error)")
                send(fd, status: 502, headers: [:], body: Data(), headOnly: method == "HEAD")
            }
            return
        }

        // /proxy/<uuid>/f/<file> — a file produced by the ffmpeg remux session
        if segments[2] == "f", segments.count >= 4 {
            // Multi-audio sessions nest their renditions under stream_N/.
            let name = segments[3...].joined(separator: "/")
            guard let file = Remuxer.shared.file(for: channelID, named: name),
                  let data = try? Data(contentsOf: file) else {
                send(fd, status: 404, headers: [:], body: Data(), headOnly: method == "HEAD")
                return
            }
            let type = file.pathExtension.lowercased() == "m3u8"
                ? "application/vnd.apple.mpegurl"
                : "video/mp4"
            send(fd, status: 200,
                 headers: ["Content-Type": type, "Cache-Control": "no-cache"],
                 body: data, headOnly: method == "HEAD")
            return
        }

        // The canonical link tries each source in preference order and sticks
        // to the first one that answers; `raw.m3u8` is the untouched
        // passthrough that feeds ffmpeg and always uses the current source.
        let wantsRaw = segments[2].hasPrefix("raw")
        let isSegment = segments[2] == "s"
        if !wantsRaw, !isSegment {
            let start = variantIndex(channel)
            for offset in 0..<channel.variants.count {
                let index = (start + offset) % channel.variants.count
                // Committed before the attempt so /raw and /manifest resolve to
                // the same source the attempt is testing.
                setVariant(channel, index)
                if let payload = serveRoot(channel: channel, variant: channel.variants[index]) {
                    if offset > 0 {
                        Log.shared.write("\(channel.name): usando fonte \(index + 1)")
                    }
                    send(fd, status: 200,
                         headers: [
                            "Content-Type": payload.contentType,
                            "Cache-Control": "no-cache, no-store",
                            "Access-Control-Allow-Origin": "*",
                         ],
                         body: payload.body, headOnly: method == "HEAD")
                    return
                }
                Log.shared.write("\(channel.name): fonte \(index + 1) falhou")
            }
            setVariant(channel, start)
            send(fd, status: 502, headers: [:],
                 body: Data("todas as fontes falharam".utf8), headOnly: method == "HEAD")
            return
        }

        let active = variant(channel)
        let targetURL: URL
        if isSegment, segments.count >= 4,
           let decoded = Base64URL.decode(stripSyntheticExtension(segments[3])),
           let u = URL(string: decoded) {
            targetURL = u
        } else {
            targetURL = active.url
        }

        do {
            let origin = targetURL.scheme.flatMap { s in
                targetURL.host.map { "\(s)://\($0)/" }
            }
            let res = try Upstream.shared.fetch(targetURL, referer: active.referer ?? origin)
            guard (200...299).contains(res.status) else {
                Log.shared.write("upstream \(res.status) em \(targetURL.lastPathComponent)")
                send(fd, status: res.status, headers: [:], body: res.body,
                     headOnly: method == "HEAD")
                return
            }

            let looksLikePlaylist = res.body.prefix(7) == Data("#EXTM3U".utf8)
            if looksLikePlaylist {
                let text = String(decoding: res.body, as: UTF8.self)
                let rewritten = rewrite(playlist: text, base: res.finalURL, channelID: channelID)
                send(fd, status: 200,
                     headers: [
                        "Content-Type": "application/vnd.apple.mpegurl",
                        "Cache-Control": "no-cache, no-store",
                        "Access-Control-Allow-Origin": "*",
                     ],
                     body: Data(rewritten.utf8), headOnly: method == "HEAD")
            } else {
                // Upstream disguises TS segments as images/docs/octet-stream;
                // only trust an explicit video/* or audio/* content type.
                var ct = res.contentType
                if res.body.prefix(6) == Data("WEBVTT".utf8) {
                    ct = "text/vtt"
                } else if !(ct.hasPrefix("video/") || ct.hasPrefix("audio/")) {
                    ct = "video/mp2t"
                }
                send(fd, status: 200,
                     headers: [
                        "Content-Type": ct,
                        "Cache-Control": "no-cache",
                        "Access-Control-Allow-Origin": "*",
                     ],
                     body: res.body, headOnly: method == "HEAD")
            }
        } catch {
            Log.shared.write("erro: \(error)")
            send(fd, status: 502, headers: [:],
                 body: Data("upstream error: \(error)".utf8), headOnly: method == "HEAD")
        }
    }

    // MARK: - Serving one source

    private struct Payload {
        let contentType: String
        let body: Data
    }

    /// Produces the playlist for a single source, or nil when that source is
    /// unusable and the next one should be tried.
    private func serveRoot(channel: Channel, variant: Variant) -> Payload? {
        let id = channel.id.uuidString

        if needsRemux(channel, variant) {
            let base = "http://\(advertisedHost):\(port)/proxy/\(id)/f/"
            // Both feed ffmpeg from our own server: the DASH route repairs the
            // manifest, the HLS one keeps the DoH fallback.
            let route = variant.isDASH ? "manifest.mpd" : "raw.m3u8"
            guard let input = URL(string: "http://127.0.0.1:\(port)/proxy/\(id)/\(route)"),
                  let text = Remuxer.shared.playlist(for: channel, variant: variant,
                                                     sourceURL: input, rewriteBase: base)
            else { return nil }
            return Payload(contentType: "application/vnd.apple.mpegurl", body: Data(text.utf8))
        }

        guard let res = try? Upstream.shared.fetch(variant.url, referer: variant.referer),
              (200...299).contains(res.status),
              res.body.prefix(7) == Data("#EXTM3U".utf8)
        else { return nil }

        let rewritten = rewrite(playlist: String(decoding: res.body, as: UTF8.self),
                                base: res.finalURL, channelID: channel.id)
        return Payload(contentType: "application/vnd.apple.mpegurl", body: Data(rewritten.utf8))
    }

    // MARK: - Playlist rewriting

    /// Proxied links carry a synthetic extension because extension-sniffing
    /// players (ffmpeg, VLC) reject a variant playlist served as `.ts` and a
    /// segment served with no extension at all. Upstream hides its segments
    /// behind .php/.ico/.ppt/.class, so anything unrecognised becomes `.ts`.
    private static let passthroughExtensions: Set<String> =
        ["ts", "aac", "mp3", "mp4", "m4s", "m4a", "key"]

    private func syntheticExtension(for absolute: URL) -> String {
        let full = absolute.absoluteString.lowercased()
        if full.contains(".m3u8") || full.contains(".m3u") { return ".m3u8" }
        if full.contains(".vtt") || full.contains(".webvtt") { return ".vtt" }
        let ext = absolute.pathExtension.lowercased()
        return Self.passthroughExtensions.contains(ext) ? ".\(ext)" : ".ts"
    }

    private func proxyURL(for absolute: URL, channelID: UUID) -> String {
        let token = Base64URL.encode(absolute.absoluteString)
        return "http://\(advertisedHost):\(port)/proxy/\(channelID.uuidString)/s/\(token)\(syntheticExtension(for: absolute))"
    }

    /// Gives the manifest an absolute MPD-level BaseURL so its relative
    /// SegmentTemplate references still resolve against the origin CDN once the
    /// document is served from localhost. Existing relative BaseURLs are made
    /// absolute instead, since two MPD-level BaseURLs would read as
    /// alternatives rather than a prefix.
    func normaliseMPD(_ xml: String, source: URL) -> String {
        let base = source.deletingLastPathComponent().absoluteString

        if xml.contains("<BaseURL>") {
            var out = xml
            var searchStart = out.startIndex
            while let open = out.range(of: "<BaseURL>", range: searchStart..<out.endIndex),
                  let close = out.range(of: "</BaseURL>", range: open.upperBound..<out.endIndex) {
                let value = String(out[open.upperBound..<close.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.lowercased().hasPrefix("http"),
                   let absolute = URL(string: value, relativeTo: source)?.absoluteString {
                    out.replaceSubrange(open.upperBound..<close.lowerBound, with: absolute)
                    searchStart = out.index(open.upperBound, offsetBy: absolute.count)
                } else {
                    searchStart = close.upperBound
                }
            }
            return out
        }

        guard let tagStart = xml.range(of: "<MPD"),
              let tagEnd = xml.range(of: ">", range: tagStart.upperBound..<xml.endIndex) else {
            return xml
        }
        var out = xml
        out.insert(contentsOf: "\n  <BaseURL>\(base)</BaseURL>", at: tagEnd.upperBound)
        return out
    }

    /// base64url never contains a dot, so everything from the first one is ours.
    private func stripSyntheticExtension(_ s: String) -> String {
        guard let dot = s.firstIndex(of: ".") else { return s }
        return String(s[s.startIndex..<dot])
    }

    func rewrite(playlist: String, base: URL, channelID: UUID) -> String {
        var out: [String] = []
        for raw in playlist.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(raw)
            if line.hasSuffix("\r") { line.removeLast() }
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                out.append(line)
            } else if trimmed.hasPrefix("#") {
                out.append(rewriteURIAttribute(in: line, base: base, channelID: channelID))
            } else if let abs = URL(string: trimmed, relativeTo: base)?.absoluteURL {
                out.append(proxyURL(for: abs, channelID: channelID))
            } else {
                out.append(line)
            }
        }
        return prioritiseHighestVariant(out).joined(separator: "\n")
    }

    /// Puts the highest-bandwidth variant first in a master playlist.
    ///
    /// With no throughput estimate yet, AVFoundation starts on the first
    /// variant listed — which on most feeds is the lowest, so a channel opens
    /// visibly soft before adaptive switching catches up. Listing the best one
    /// first makes it open sharp; ABR is untouched and still free to step down.
    func prioritiseHighestVariant(_ lines: [String]) -> [String] {
        guard lines.contains(where: { $0.hasPrefix("#EXT-X-STREAM-INF") }) else { return lines }

        var header: [String] = []
        var variants: [(bandwidth: Int, lines: [String])] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            guard line.hasPrefix("#EXT-X-STREAM-INF") else {
                header.append(line)
                index += 1
                continue
            }
            // The URI is the next non-comment, non-empty line.
            var cursor = index + 1
            var block = [line]
            while cursor < lines.count {
                let candidate = lines[cursor]
                block.append(candidate)
                let trimmed = candidate.trimmingCharacters(in: .whitespaces)
                cursor += 1
                if !trimmed.isEmpty && !trimmed.hasPrefix("#") { break }
            }
            var bandwidth = 0
            if let range = line.range(of: "BANDWIDTH=") {
                let digits = line[range.upperBound...].prefix { $0.isNumber }
                bandwidth = Int(digits) ?? 0
            }
            variants.append((bandwidth, block))
            index = cursor
        }

        guard variants.count > 1 else { return lines }
        variants.sort { $0.bandwidth > $1.bandwidth }
        return header + variants.flatMap(\.lines)
    }

    /// Rewrites `URI="..."` inside tags such as EXT-X-KEY / EXT-X-MAP / EXT-X-MEDIA.
    private func rewriteURIAttribute(in line: String, base: URL, channelID: UUID) -> String {
        guard let uriRange = line.range(of: "URI=\"") else { return line }
        let valueStart = uriRange.upperBound
        guard let closing = line[valueStart...].firstIndex(of: "\"") else { return line }
        let value = String(line[valueStart..<closing])
        guard let abs = URL(string: value, relativeTo: base)?.absoluteURL else { return line }
        return line.replacingCharacters(
            in: valueStart..<closing,
            with: proxyURL(for: abs, channelID: channelID))
    }

    // MARK: - Socket I/O

    private func readHead(_ fd: Int32) -> String? {
        var buf = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while buf.range(of: Data("\r\n\r\n".utf8)) == nil {
            let n = recv(fd, &chunk, chunk.count, 0)
            if n <= 0 { return nil }
            buf.append(contentsOf: chunk[0..<n])
            if buf.count > 64 * 1024 { return nil }
        }
        return String(decoding: buf, as: UTF8.self)
    }

    private func send(_ fd: Int32, status: Int, headers: [String: String],
                      body: Data, headOnly: Bool) {
        var head = "HTTP/1.1 \(status) \(Self.reason(status))\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n"
        for (k, v) in headers { head += "\(k): \(v)\r\n" }
        head += "\r\n"

        var payload = Data(head.utf8)
        if !headOnly { payload.append(body) }

        payload.withUnsafeBytes { rawBuf in
            guard let base = rawBuf.baseAddress else { return }
            var sent = 0
            while sent < rawBuf.count {
                let n = Darwin.send(fd, base.advanced(by: sent), rawBuf.count - sent, 0)
                if n <= 0 { return }
                sent += n
            }
        }
    }

    private static func reason(_ code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 502: return "Bad Gateway"
        default: return "Status"
        }
    }
}
