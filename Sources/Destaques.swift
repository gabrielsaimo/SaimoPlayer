import Foundation

/// As fileiras da tela inicial do acervo, prontas para desenhar.
///
/// O acervo tem trinta e quatro mil filmes e nenhuma data de entrada, então não
/// há como o aplicativo descobrir sozinho o que é novidade — e perguntar a capa
/// de cada título ao TMDB, a cada abertura, seria uma tela que demora para
/// aparecer. A conta é feita no repositório (`gerar_destaques.py`) e chega aqui
/// pronta: seis fileiras, cento e vinte títulos, sete quilobytes, com o caminho
/// do pôster junto.
///
/// O formato de cada item é o mesmo de um resultado de busca — tipo, título,
/// letra, ano —, então abrir um destaque passa pelo caminho que já abre um
/// título procurado. É o mesmo arquivo que a TV Box e o Windows leem.
enum Destaques {

    struct Item: Identifiable, Hashable {
        let titulo: String
        /// "f" filme, "s" série, "a" anime, "d" dorama.
        let tipo: Character
        let letra: String
        let ano: String
        /// Endereço inteiro da capa, ou vazio quando o gerador não achou uma.
        let capa: String

        var serie: Bool { tipo != "f" }
        var daColecao: Bool { tipo == "a" || tipo == "d" }
        var colecao: VodSecao { tipo == "a" ? .animes : .doramas }
        var nomeCompleto: String { ano.isEmpty ? titulo : "\(titulo) (\(ano))" }
        var id: String { "\(tipo):\(nomeCompleto)" }
    }

    struct Fila: Identifiable, Hashable {
        let titulo: String
        let itens: [Item]
        var id: String { titulo }
    }

    private static let endereco = URL(
        string: "https://raw.githubusercontent.com/gabrielsaimo/SaimoPlayer/main/vod/destaques.txt")!
    /// A lista muda quando o gerador roda; um dia em disco abre instantâneo sem
    /// ficar semanas desatualizado.
    private static let validade: TimeInterval = 24 * 60 * 60

    private static var emMemoria: [Fila]?

    static func filas() async -> [Fila] {
        if let prontas = emMemoria { return prontas }
        guard let texto = await texto() else { return [] }
        let lidas = ler(texto)
        emMemoria = lidas
        return lidas
    }

    private static var arquivo: URL {
        let pasta = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SaimoTV", isDirectory: true)
        try? FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        return pasta.appendingPathComponent("destaques.txt")
    }

    private static func texto() async -> String? {
        let local = arquivo
        if let atributos = try? FileManager.default.attributesOfItem(atPath: local.path),
           let quando = atributos[.modificationDate] as? Date,
           Date().timeIntervalSince(quando) < validade,
           let guardado = try? String(contentsOf: local, encoding: .utf8),
           !guardado.isEmpty {
            return guardado
        }

        var pedido = URLRequest(url: endereco)
        pedido.setValue(Upstream.userAgent, forHTTPHeaderField: "User-Agent")
        pedido.setValue("*/*", forHTTPHeaderField: "Accept")
        if let (dados, resposta) = try? await URLSession.shared.data(for: pedido),
           let http = resposta as? HTTPURLResponse, (200...299).contains(http.statusCode),
           let baixado = String(data: dados, encoding: .utf8), !baixado.isEmpty {
            try? baixado.write(to: local, atomically: true, encoding: .utf8)
            return baixado
        }
        // Rede fora: o que está em disco, mesmo vencido, é melhor que nada.
        return try? String(contentsOf: local, encoding: .utf8)
    }

    private static func ler(_ texto: String) -> [Fila] {
        var filas: [Fila] = []
        var titulo: String?
        var itens: [Item] = []
        var base = ""

        func fechar() {
            guard let nome = titulo, !itens.isEmpty else { itens = []; return }
            filas.append(Fila(titulo: nome, itens: itens))
            itens = []
        }

        for linha in texto.split(separator: "\n", omittingEmptySubsequences: false) {
            if linha.isEmpty || linha.hasPrefix("#") { continue }
            if linha.hasPrefix("capa:") {
                base = linha.dropFirst("capa:".count).trimmingCharacters(in: .whitespaces)
                continue
            }
            if linha.hasPrefix("fila\t") {
                fechar()
                titulo = String(linha.dropFirst("fila\t".count))
                    .trimmingCharacters(in: .whitespaces)
                continue
            }
            let campos = linha.split(separator: "\t", omittingEmptySubsequences: false)
                .map(String.init)
            guard campos.count >= 3 else { continue }
            let poster = campos.count > 4 ? campos[4] : ""
            itens.append(Item(
                titulo: campos[1],
                tipo: campos[0].first ?? "f",
                letra: campos[2],
                ano: campos.count > 3 ? campos[3] : "",
                capa: poster.isEmpty ? "" : base + poster))
        }
        fechar()
        return filas
    }
}
