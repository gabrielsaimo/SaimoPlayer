import SwiftUI
import AppKit

/// Capa de um filme ou série, procurada pelo nome no TMDB.
///
/// As listas de origem não trazem imagem nenhuma. A busca acontece só para o
/// que está na tela: são algumas dezenas de títulos visíveis, não trinta mil.
///
/// Antes vinha do Cinemeta e ficava com o primeiro resultado, sem comparar
/// nome nenhum — "A 13ª Emenda" batia com qualquer coisa que a busca por esse
/// texto trouxesse primeiro. Agora vem do TMDB, com o mesmo algoritmo de
/// pontuação do `api-saimo-tv`: título exato, título contido, ano de
/// lançamento, popularidade — e um resultado único da busca também conta,
/// porque a busca do TMDB já casa por apelido traduzido que nem `title` nem
/// `original_title` revelam de volta.
///
/// Nada disso vai para o disco — nem o endereço, nem a imagem. O que se guarda
/// vive na memória e morre com o app, então cada abertura busca de novo.
@MainActor
final class Capas: ObservableObject {
    static let shared = Capas()

    private static let chave = "15d2ea6d0dc1d476efbca3eba2b9bbfb"
    private static let base = "https://api.themoviedb.org/3"
    private static let pontuacaoMinima = 10

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
        guard let caminho = await Self.melhorPoster(titulo, serie: serie),
              let url = URL(string: "https://image.tmdb.org/t/p/w500\(caminho)")
        else { return }

        var pedido = URLRequest(url: url)
        pedido.timeoutInterval = 20
        // Sem cache: a imagem não pode sobrar em disco nem entre aberturas.
        pedido.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        pedido.setValue(Upstream.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (dados, _) = try? await URLSession.shared.data(for: pedido),
              let imagem = NSImage(data: dados) else { return }
        imagens[chave] = imagem
    }

    // MARK: - Busca no TMDB

    private struct Resultado {
        let id: Int
        let titulo: String?
        let original: String?
        let data: String?
        let posterPath: String?
        let votos: Int
    }

    private static func buscarUmaVez(_ query: String, tv: Bool, idioma: String) async -> [Resultado] {
        let endpoint = tv ? "search/tv" : "search/movie"
        guard let termo = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(base)/\(endpoint)?query=\(termo)&api_key=\(chave)&language=\(idioma)")
        else { return [] }

        var pedido = URLRequest(url: url)
        pedido.timeoutInterval = 8
        pedido.setValue(Upstream.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (dados, _) = try? await URLSession.shared.data(for: pedido),
              let raiz = try? JSONSerialization.jsonObject(with: dados) as? [String: Any],
              let brutos = raiz["results"] as? [[String: Any]]
        else { return [] }

        return brutos.map { item in
            Resultado(
                id: item["id"] as? Int ?? 0,
                titulo: (tv ? item["name"] : item["title"]) as? String,
                original: (tv ? item["original_name"] : item["original_title"]) as? String,
                data: (tv ? item["first_air_date"] : item["release_date"]) as? String,
                posterPath: item["poster_path"] as? String,
                votos: item["vote_count"] as? Int ?? 0)
        }
    }

    /// pt-BR primeiro; sem resultado, tenta en-US.
    private static func buscar(_ query: String, tv: Bool) async -> [Resultado] {
        let pt = await buscarUmaVez(query, tv: tv, idioma: "pt-BR")
        if !pt.isEmpty { return pt }
        return await buscarUmaVez(query, tv: tv, idioma: "en-US")
    }

    private static func pontuar(_ nomeLocal: String, _ resultado: Resultado, ano: Int?, unico: Bool) -> Int {
        let localNorm = normalizar(limpar(nomeLocal))
        let tituloNorm = normalizar(resultado.titulo ?? "")
        let originalNorm = normalizar(resultado.original ?? "")

        var pontos = 0
        if localNorm == tituloNorm || localNorm == originalNorm {
            pontos += 100
        } else if tituloNorm.hasPrefix(localNorm) || localNorm.hasPrefix(tituloNorm) {
            pontos += 70
        } else if originalNorm.hasPrefix(localNorm) || localNorm.hasPrefix(originalNorm) {
            pontos += 65
        } else if tituloNorm.contains(localNorm) || localNorm.contains(tituloNorm) {
            pontos += 50
        } else if originalNorm.contains(localNorm) || localNorm.contains(originalNorm) {
            pontos += 45
        } else if unico {
            // A busca do TMDB já casa por título traduzido que nem `titulo`
            // nem `original` revelam de volta — um resultado único já é
            // sinal suficiente de que a relevância deles achou o certo.
            pontos += 12
        }

        let votos = resultado.votos
        if votos > 1000 { pontos += 15 } else if votos > 100 { pontos += 8 }

        if let ano, let data = resultado.data, data.count >= 4,
           let anoTmdb = Int(data.prefix(4)) {
            let diff = abs(ano - anoTmdb)
            if diff == 0 { pontos += 25 }
            else if diff == 1 { pontos += 10 }
            else if diff > 2 { pontos -= 25 }
        }

        return pontos
    }

    /// Tenta o tipo pedido em todas as variantes do nome; sem sorte, tenta o
    /// tipo oposto — um "anime" catalogado como filme às vezes é uma série no
    /// TMDB, e vice-versa.
    private static func melhorPoster(_ nome: String, serie: Bool) async -> String? {
        let ano = extrairAno(nome)
        let variantes = variantesDeBusca(nome)

        var melhor: Resultado?
        var melhorPontos = 0

        for variante in variantes {
            let resultados = await buscar(variante, tv: serie)
            let unico = resultados.count == 1
            for r in resultados.prefix(5) {
                let pontos = pontuar(nome, r, ano: ano, unico: unico)
                if pontos > melhorPontos { melhorPontos = pontos; melhor = r }
            }
            if melhorPontos >= 90 { break }
        }

        if melhorPontos < pontuacaoMinima {
            for variante in variantes {
                let resultados = await buscar(variante, tv: !serie)
                let unico = resultados.count == 1
                for r in resultados.prefix(5) {
                    let pontos = pontuar(nome, r, ano: ano, unico: unico)
                    if pontos > melhorPontos { melhorPontos = pontos; melhor = r }
                }
                if melhorPontos >= 90 { break }
            }
        }

        guard melhorPontos >= pontuacaoMinima, let vencedor = melhor,
              let caminho = vencedor.posterPath, !caminho.isEmpty
        else { return nil }
        return caminho
    }

    // MARK: - Limpeza de título

    private static func normalizar(_ texto: String) -> String {
        let semAcento = texto.folding(options: .diacriticInsensitive, locale: .current)
        let apenasAlfanum = semAcento.lowercased().replacingOccurrences(
            of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
        return apenasAlfanum.replacingOccurrences(
            of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private static func extrairAno(_ titulo: String) -> Int? {
        guard let intervalo = titulo.range(of: #"\b(19|20)\d{2}\b"#, options: .regularExpression)
        else { return nil }
        return Int(titulo[intervalo])
    }

    /// Nome de busca: sem marcas de idioma, qualidade nem ano entre parênteses.
    private static func limpar(_ titulo: String) -> String {
        var texto = titulo.replacingOccurrences(
            of: #"(?i)\s*[\(\[]\s*(leg|dub|dublado|legendado|dual|national|pt-br|pt-pt|eng|legendada)\s*[\)\]]"#,
            with: "", options: .regularExpression)
        texto = texto.replacingOccurrences(
            of: #"(?i)\b(4k|uhd|hd|fhd|sd|bluray|bdrip|web-dl|webrip|hdtv|dvdrip|cam|hdr|sdr)\b"#,
            with: "", options: .regularExpression)
        texto = texto.replacingOccurrences(
            of: #"\s*[\(\[]\d{4}[\)\]]\s*"#, with: " ", options: .regularExpression)
        return texto.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// As variações que valem tentar: título limpo, sem artigo inicial, sem
    /// subtítulo depois de ":" ou "-", sem acento, sem algarismo romano no fim.
    private static func variantesDeBusca(_ nome: String) -> [String] {
        let limpo = limpar(nome)
        var variantes = [limpo]

        func adicionar(_ s: String?) {
            guard let s, s.count > 1, !variantes.contains(s) else { return }
            variantes.append(s)
        }

        let semArtigo = limpo.replacingOccurrences(
            of: #"(?i)^(o|a|os|as|um|uma|the|an?)\s+"#, with: "", options: .regularExpression)
        adicionar(semArtigo != limpo ? semArtigo : nil)

        if let intervalo = limpo.range(of: #"\s*[:\-]\s+"#, options: .regularExpression) {
            let semSubtitulo = String(limpo[limpo.startIndex..<intervalo.lowerBound])
                .trimmingCharacters(in: .whitespaces)
            adicionar(semSubtitulo.count > 2 ? semSubtitulo : nil)
        }

        let semAcento = limpo.folding(options: .diacriticInsensitive, locale: .current)
        adicionar(semAcento != limpo ? semAcento : nil)

        let semRomano = limpo.replacingOccurrences(
            of: #"(?i)\s+(II|III|IV|V|VI|VII|VIII|IX|X)$"#, with: "", options: .regularExpression)
        adicionar(semRomano != limpo ? semRomano : nil)

        return variantes
    }
}
