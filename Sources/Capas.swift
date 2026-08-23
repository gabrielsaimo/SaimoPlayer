import SwiftUI
import AppKit

/// Capa de um filme ou série, procurada pelo nome.
///
/// As listas de origem não trazem imagem nenhuma, então a capa vem do Cinemeta,
/// que é público e não pede chave. A busca acontece só para o que está na tela:
/// são algumas dezenas de títulos visíveis, não trinta mil.
///
/// Nada disso vai para o disco — nem o endereço, nem a imagem. O que se guarda
/// vive na memória e morre com o app, então cada abertura busca de novo.
@MainActor
final class Capas: ObservableObject {
    static let shared = Capas()

    @Published private(set) var imagens: [String: NSImage] = [:]
    private var procurados: Set<String> = []
    /// Três buscas por vez: rolar a lista depressa não pode virar cinquenta
    /// pedidos de uma vez.
    private var emVoo = 0
    private var fila: [(String, Bool)] = []

    private init() {}

    /// Capa do título, se já chegou. Se ainda não, agenda a busca.
    func imagem(para titulo: String, serie: Bool) -> NSImage? {
        let chave = (serie ? "s:" : "f:") + titulo
        if let pronta = imagens[chave] { return pronta }
        guard !procurados.contains(chave) else { return nil }
        procurados.insert(chave)
        fila.append((titulo, serie))
        bombear()
        return nil
    }

    private func bombear() {
        while emVoo < 3, !fila.isEmpty {
            let (titulo, serie) = fila.removeFirst()
            emVoo += 1
            Task { [weak self] in
                await self?.buscar(titulo, serie: serie)
                self?.emVoo -= 1
                self?.bombear()
            }
        }
    }

    private func buscar(_ titulo: String, serie: Bool) async {
        let chave = (serie ? "s:" : "f:") + titulo
        guard let endereco = await Self.endereco(titulo, serie: serie),
              let url = URL(string: endereco) else { return }

        var pedido = URLRequest(url: url)
        pedido.timeoutInterval = 20
        // Sem cache: a imagem não pode sobrar em disco nem entre aberturas.
        pedido.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        pedido.setValue(Upstream.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (dados, _) = try? await URLSession.shared.data(for: pedido),
              let imagem = NSImage(data: dados) else { return }
        imagens[chave] = imagem
    }

    /// Endereço da capa no índice do Cinemeta.
    ///
    /// Fica o primeiro resultado, sem conferir o nome: o índice é de títulos e
    /// conhece os apelidos em português — "A 13ª Emenda" é "13th" e "A 100
    /// Passos De Um Sonho" é "The Hundred-Foot Journey", que nenhuma comparação
    /// de palavras aceitaria.
    private static func endereco(_ titulo: String, serie: Bool) async -> String? {
        let busca = limpar(titulo)
        guard busca.count > 1,
              let termo = busca.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://v3-cinemeta.strem.io/catalog/"
                            + (serie ? "series" : "movie") + "/top/search=\(termo).json")
        else { return nil }

        var pedido = URLRequest(url: url)
        pedido.timeoutInterval = 20
        pedido.setValue(Upstream.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (dados, _) = try? await URLSession.shared.data(for: pedido),
              let raiz = try? JSONSerialization.jsonObject(with: dados) as? [String: Any],
              let metas = raiz["metas"] as? [[String: Any]],
              let primeiro = metas.first,
              let capa = primeiro["poster"] as? String, !capa.isEmpty
        else { return nil }
        return capa
    }

    /// Nome de busca: sem marca de qualidade, sem colchete, sem ano no fim.
    static func limpar(_ titulo: String) -> String {
        var texto = titulo.replacingOccurrences(
            of: #"[\[\(][^\]\)]*[\]\)]"#, with: " ", options: .regularExpression)
        texto = texto.replacingOccurrences(
            of: #"(?i)\b(4k|uhd|fhd|hd|sd|h265|hevc|hdr|dv|dual|remux|legendado|dublado|leg|dub)\b"#,
            with: " ", options: .regularExpression)
        texto = texto.replacingOccurrences(
            of: #"\s+((19|20)\d{2})\s*$"#, with: " ", options: .regularExpression)
        return texto.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}
