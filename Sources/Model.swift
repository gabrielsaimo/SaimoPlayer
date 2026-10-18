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
    /// O KID da chave acima. O AVFoundation não usa, mas o celular do Saimo
    /// Connect toca a fonte sozinho e precisa do par.
    var clearKeyId: String?
    var label: String?
    /// O que diferencia a fonte das outras do canal ("Temporada 3"), quando o
    /// catálogo sabe (campo `nome:`); senão aparece o número.
    var nome: String?

    /// AVFoundation cannot play DASH at all, so those always go through the
    /// ffmpeg gateway.
    var isDASH: Bool { url.absoluteString.lowercased().contains(".mpd") }
}

struct Channel: Identifiable, Hashable {
    let id: UUID
    var name: String
    var logo: URL?
    var variants: [Variant]
    /// Seção declarada no catálogo publicado. Vazia = "Outros" — ver `Categoria.de(_:)`.
    var categoria: String?

    var primary: Variant { variants[0] }
    var source: URL { variants[0].url }

    /// The id is derived from the primary source so the generated proxy link
    /// stays the same across app launches.
    init(name: String, variants: [Variant], logo: URL? = nil, categoria: String? = nil) {
        precondition(!variants.isEmpty, "channel needs at least one source")
        self.id = Channel.stableID(for: variants[0].url)
        self.name = name
        self.variants = variants
        self.logo = logo
        self.categoria = categoria
    }

    init(name: String, source: URL, logo: URL? = nil, referer: String? = nil,
         userAgent: String? = nil, clearKey: String? = nil, label: String? = nil) {
        self.init(name: name,
                  variants: [Variant(url: source, referer: referer,
                                     userAgent: userAgent, clearKey: clearKey, label: label)],
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

/// Como a lista de canais é dividida na tela.
///
/// A seção de cada canal vem do campo `categoria:` do catálogo publicado; canal
/// sem categoria (ou com uma que o app não conhece) vai para "Outros". Nenhuma
/// regra olha o nome do canal.
enum Categoria: String, CaseIterable, Identifiable {
    case favoritos = "Favoritos"
    case tvAberta = "TV Aberta"
    case filmes = "Filmes e Séries"
    case esportes = "Esportes"
    case noticias = "Notícias"
    case infantil = "Infantil"
    case documentarios = "Documentários"
    case plutoTV = "Pluto TV"
    case vinteQuatroHoras = "24 Horas"
    case musicas = "Músicas"
    case ppv = "PPV"
    case variedades = "Variedades"
    case adulto = "Adulto"
    case outros = "Outros"

    var id: String { rawValue }

    /// A seção do canal: a declarada no catálogo; senão "Outros".
    static func de(_ canal: Channel) -> Categoria {
        de(declarada: canal.categoria)
    }

    static func de(declarada: String?) -> Categoria {
        guard let declarada = declarada?.trimmingCharacters(in: .whitespaces), !declarada.isEmpty
        else { return .outros }
        return Categoria(rawValue: declarada)
            ?? allCases.first { $0.rawValue.compare(declarada, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
            ?? .outros
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
