import Foundation

/// Onde começa e acaba a abertura, a recapitulação e os créditos.
///
/// Os tempos vêm do TheIntroDB (theintrodb.org), um banco aberto em que quem
/// assiste marca esses trechos. A consulta é pelo id do TMDB que o arquivo de
/// fichas já traz — sem adivinhação: ou o trecho foi marcado para aquele
/// episódio, ou o botão não aparece. Mesma fonte da TV Box, do celular, do
/// site e do Windows.
enum Pulos {

    enum Tipo {
        case abertura, recapitulacao, creditos, previa

        var rotulo: String {
            switch self {
            case .abertura: return "Pular abertura"
            case .recapitulacao: return "Pular recapitulação"
            case .creditos: return "Pular créditos"
            case .previa: return "Pular prévia"
            }
        }
    }

    /// Um trecho em segundos. `fim` nulo quer dizer "até o fim do vídeo".
    struct Trecho: Equatable {
        let tipo: Tipo
        let inicio: Double
        let fim: Double?
    }

    struct Marcas: Equatable {
        let trechos: [Trecho]

        var creditos: Double? { trechos.first { $0.tipo == .creditos }?.inicio }

        /// O trecho pulável em que a posição está agora, se houver.
        func em(_ posicao: Double, duracao: Double) -> Trecho? {
            trechos.first {
                $0.tipo != .creditos && posicao >= $0.inicio && posicao < ($0.fim ?? duracao) - 1
            }
        }
    }

    private static let base = "https://api.theintrodb.org/v3/media"
    @MainActor private static var guardadas: [String: Marcas] = [:]

    @MainActor
    static func buscar(tmdb: Int, temporada: Int = 0, episodio: Int = 0) async -> Marcas? {
        guard tmdb > 0 else { return nil }
        let chave = "\(tmdb)|\(temporada)|\(episodio)"
        if let m = guardadas[chave] { return m }
        var texto = "\(base)?tmdb_id=\(tmdb)"
        if temporada > 0 { texto += "&season=\(temporada)&episode=\(episodio)" }
        guard let url = URL(string: texto) else { return nil }
        var pedido = URLRequest(url: url, timeoutInterval: 15)
        pedido.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (dados, resposta) = try? await URLSession.shared.data(for: pedido),
              (resposta as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: dados) as? [String: Any]
        else { return nil }
        let marcas = Marcas(trechos: ler(json))
        guardadas[chave] = marcas
        return marcas
    }

    static func ler(_ json: [String: Any]) -> [Trecho] {
        var saida: [Trecho] = []
        let campos: [(String, Tipo)] = [
            ("intro", .abertura), ("recap", .recapitulacao), ("credits", .creditos), ("preview", .previa),
        ]
        for (campo, tipo) in campos {
            for item in json[campo] as? [[String: Any]] ?? [] {
                let inicio = ((item["start_ms"] as? NSNumber)?.doubleValue ?? 0) / 1000
                let fim = (item["end_ms"] as? NSNumber).map { $0.doubleValue / 1000 }
                // Trecho de menos de três segundos é marcação errada.
                if let fim, fim - inicio < 3 { continue }
                saida.append(Trecho(tipo: tipo, inicio: inicio, fim: fim))
            }
        }
        return saida
    }
}
