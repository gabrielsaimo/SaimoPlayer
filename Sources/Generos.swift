import Foundation

/// O gênero de cada título: Ação, Terror, Animação, Comédia.
///
/// O catálogo não tem gênero — as listas de origem trazem nome e endereço,
/// nada mais. Quem quiser filtrar por gênero precisa que alguém pergunte ao
/// TMDB, e perguntar por trinta e quatro mil títulos, em cada aparelho, a cada
/// abertura, é uma tela que nunca abre.
///
/// A pergunta é feita uma vez no repositório (`gerar_generos.py`) e chega aqui
/// pronta, num arquivo que os cinco aplicativos leem igual.
///
/// Sem rede, o filtro simplesmente não aparece: melhor não oferecer do que
/// oferecer uma lista que devolve vazio.
enum Generos {

    private static let endereco = URL(
        string: "https://raw.githubusercontent.com/gabrielsaimo/SaimoPlayer/main/vod/generos.txt")!

    /// "f|Nome" ou "s|Nome" -> os gêneros dele.
    private static var mapa: [String: [String]] = [:]
    /// Todos os gêneros que aparecem no acervo, em ordem alfabética.
    private(set) static var todos: [String] = []
    private static var carregando = false

    static var prontos: Bool { !mapa.isEmpty }

    private static func chave(_ titulo: String, serie: Bool) -> String {
        (serie ? "s|" : "f|") + titulo
    }

    static func de(_ titulo: String, serie: Bool) -> [String] {
        mapa[chave(titulo, serie: serie)] ?? []
    }

    static func tem(_ titulo: String, serie: Bool, genero: String) -> Bool {
        de(titulo, serie: serie).contains(genero)
    }

    /// Baixa a lista uma vez por abertura, e guarda em disco para a seguinte.
    static func carregar() async {
        if prontos || carregando { return }
        carregando = true
        defer { carregando = false }

        let texto = await baixado() ?? (try? String(contentsOf: arquivo, encoding: .utf8))
        guard let texto, !texto.isEmpty else { return }

        var novo: [String: [String]] = [:]
        var vistos = Set<String>()
        for linha in texto.split(separator: "\n") {
            if linha.hasPrefix("#") { continue }
            let campos = linha.split(separator: "\t", omittingEmptySubsequences: false)
            guard campos.count >= 3 else { continue }
            let lista = campos[2].split(separator: ",").map(String.init)
            guard !lista.isEmpty else { continue }
            novo["\(campos[0])|\(campos[1])"] = lista
            lista.forEach { vistos.insert($0) }
        }
        mapa = novo
        todos = vistos.sorted()
    }

    private static var arquivo: URL {
        let pasta = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SaimoTV", isDirectory: true)
        try? FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        return pasta.appendingPathComponent("generos.txt")
    }

    private static func baixado() async -> String? {
        var pedido = URLRequest(url: endereco)
        pedido.setValue(Upstream.userAgent, forHTTPHeaderField: "User-Agent")
        pedido.setValue("*/*", forHTTPHeaderField: "Accept")
        guard let (dados, resposta) = try? await URLSession.shared.data(for: pedido),
              let http = resposta as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let texto = String(data: dados, encoding: .utf8), !texto.isEmpty
        else { return nil }
        try? texto.write(to: arquivo, atomically: true, encoding: .utf8)
        return texto
    }
}
