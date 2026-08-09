import Foundation
import CryptoKit

/// One playable source for a channel. A channel keeps several in preference
/// order so a dead or expired link can fall back to the next one.
struct Variant: Hashable {
    var url: URL
    var referer: String?
    var userAgent: String?
    /// ClearKey (hex) for CENC-encrypted DASH sources.
    var clearKey: String?

    /// AVFoundation cannot play DASH at all, so those always go through the
    /// ffmpeg gateway.
    var isDASH: Bool { url.absoluteString.lowercased().contains(".mpd") }
}

struct Channel: Identifiable, Hashable {
    let id: UUID
    var name: String
    var logo: URL?
    var variants: [Variant]

    var primary: Variant { variants[0] }
    var source: URL { variants[0].url }

    /// The id is derived from the primary source so the generated proxy link
    /// stays the same across app launches.
    init(name: String, variants: [Variant], logo: URL? = nil) {
        precondition(!variants.isEmpty, "channel needs at least one source")
        self.id = Channel.stableID(for: variants[0].url)
        self.name = name
        self.variants = variants
        self.logo = logo
    }

    init(name: String, source: URL, logo: URL? = nil, referer: String? = nil,
         userAgent: String? = nil, clearKey: String? = nil) {
        self.init(name: name,
                  variants: [Variant(url: source, referer: referer,
                                     userAgent: userAgent, clearKey: clearKey)],
                  logo: logo)
    }

    static func stableID(for source: URL) -> UUID {
        let digest = Array(Insecure.MD5.hash(data: Data(source.absoluteString.utf8)))
        var bytes = digest
        bytes[6] = (bytes[6] & 0x0F) | 0x30   // version 3
        bytes[8] = (bytes[8] & 0x3F) | 0x80   // RFC 4122 variant
        let uuid = (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5],
                    bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11],
                    bytes[12], bytes[13], bytes[14], bytes[15])
        return UUID(uuid: uuid)
    }
}

enum Base64URL {
    static func encode(_ s: String) -> String {
        Data(s.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ s: String) -> String? {
        var t = s.replacingOccurrences(of: "-", with: "+")
                 .replacingOccurrences(of: "_", with: "/")
        while t.count % 4 != 0 { t += "=" }
        guard let d = Data(base64Encoded: t) else { return nil }
        return String(data: d, encoding: .utf8)
    }
}

/// Parses an .m3u/.m3u8 *channel list* (not a media playlist).
enum M3UList {
    static func parse(_ text: String) -> [Channel] {
        var out: [Channel] = []
        var pendingName: String?
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            if line.hasPrefix("#EXTINF") {
                if let comma = line.range(of: ",") {
                    pendingName = String(line[comma.upperBound...])
                        .trimmingCharacters(in: .whitespaces)
                }
                continue
            }
            if line.hasPrefix("#") { continue }
            guard let url = URL(string: line), url.scheme != nil else { continue }
            let name = pendingName?.isEmpty == false
                ? pendingName!
                : (url.host ?? "Canal \(out.count + 1)")
            out.append(Channel(name: name, source: url))
            pendingName = nil
        }
        return out
    }
}
