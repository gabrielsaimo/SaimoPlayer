import Foundation

/// A fonte que a pessoa vinha assistindo numa série, para o episódio seguinte
/// tocar pela mesma. Cada episódio tem a própria lista de fontes, e a ordem
/// muda de um para o outro: o que se guarda é o provedor (o host) e a posição.
enum FontePreferida {

    struct Memoria: Equatable {
        let serie: String
        let host: String
        let posicao: Int
    }

    /// O host sem "www.", em minúsculas, para comparar provedores.
    static func host(de url: String) -> String {
        guard let host = URL(string: url)?.host?.lowercased() else { return "" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Qual fonte da lista tocar primeiro: a do mesmo provedor (a primeira que
    /// bater), senão a da mesma posição, senão a primeira — a ordem de hoje.
    static func indice(urls: [String], host: String, posicao: Int) -> Int {
        guard !urls.isEmpty else { return 0 }
        if !host.isEmpty, let igual = urls.firstIndex(where: { Self.host(de: $0) == host }) {
            return igual
        }
        return urls.indices.contains(posicao) ? posicao : 0
    }

    /// A lista com a preferida na frente e as outras atrás, na ordem original,
    /// para o player descer sozinho se ela não abrir.
    static func ordenar(_ urls: [String], host: String, posicao: Int) -> [String] {
        let i = indice(urls: urls, host: host, posicao: posicao)
        guard i > 0, urls.indices.contains(i) else { return urls }
        var out = urls
        out.insert(out.remove(at: i), at: 0)
        return out
    }
}
