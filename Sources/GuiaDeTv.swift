import Foundation

/// Reserva do guia para o que o meuguia.tv não lista — Sony Movies é o caso
/// que motivou, e a mesma varredura das sete categorias do guiadetv.com achou
/// mais cinco. Só entra para quem `MeuGuia` já não trouxe nada.
enum GuiaDeTv {
    /// Catalog name -> slug do guiadetv.com.
    static let slugs: [String: String] = [
        "SONY Movies": "sony-movies",
        "SBT News": "sbt-news",
        "Terra Viva": "terra-viva",
        "Box Kids TV": "box-kids",
        "X Sports": "xsports",
        "N SPORTS": "nsports",
    ]

    private static let timeZone = TimeZone(identifier: "America/Sao_Paulo") ?? .current

    static func fetch(wanted: [(id: UUID, name: String)],
                      from: Date, to: Date) async -> [UUID: [Programme]] {
        let targets = wanted.compactMap { entry -> (UUID, String)? in
            guard let slug = slugs[entry.name] else { return nil }
            return (entry.id, slug)
        }
        guard !targets.isEmpty else { return [:] }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25
        config.httpMaximumConnectionsPerHost = 4
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config)

        var out: [UUID: [Programme]] = [:]
        await withTaskGroup(of: (UUID, [Programme]).self) { group in
            for (id, slug) in targets {
                group.addTask {
                    guard let url = URL(string: "https://www.guiadetv.com/canal/\(slug)") else {
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

    /// `data-dt="AAAA-MM-DD HH:MM:SS-03:00"` seguido, adiante, de um link
    /// `/programa/...` cujo texto é o título. O fim também não é publicado;
    /// mesma regra do meuguia — vai até o próximo começar.
    static func parse(_ html: String) -> [Programme] {
        guard let regex = try? NSRegularExpression(
            pattern: #"data-dt="(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):\d{2}[^"]*"[\s\S]*?<a[^>]*href="[^"]*programa/[^"]+"[^>]*>[\s\S]*?([A-Za-zÀ-ÿ0-9][^<]{2,150})"#,
            options: []
        ) else { return [] }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var vistos: [Date: String] = [:]
        var ordem: [Date] = []

        regex.enumerateMatches(in: html, options: [], range: range) { match, _, _ in
            guard let match, match.numberOfRanges == 7 else { return }
            func campo(_ index: Int) -> String? {
                guard let r = Range(match.range(at: index), in: html) else { return nil }
                return String(html[r])
            }
            guard let anoS = campo(1), let mesS = campo(2), let diaS = campo(3),
                  let horaS = campo(4), let minutoS = campo(5),
                  let ano = Int(anoS), let mes = Int(mesS), let dia = Int(diaS),
                  let hora = Int(horaS), let minuto = Int(minutoS)
            else { return }

            var components = DateComponents()
            components.year = ano; components.month = mes; components.day = dia
            components.hour = hora; components.minute = minuto
            guard let inicio = calendar.date(from: components) else { return }

            let bruto = campo(6) ?? ""
            let titulo = XMLTVParser.decodeEntities(bruto)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard titulo.count > 1 else { return }

            // O mesmo instante pode repetir na página — o link do programa
            // carrega metadados extras que também casam com o padrão.
            if vistos[inicio] == nil {
                vistos[inicio] = titulo
                ordem.append(inicio)
            }
        }

        ordem.sort()
        return ordem.enumerated().map { index, inicio in
            let fim = index + 1 < ordem.count ? ordem[index + 1] : inicio.addingTimeInterval(3600)
            return Programme(title: vistos[inicio] ?? "", desc: "", category: "",
                             start: inicio, stop: fim)
        }
    }
}
