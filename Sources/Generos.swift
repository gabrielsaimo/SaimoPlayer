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
        string: "https://raw.githubusercontent.com/gabrielsaimo/SaimoPlayer/main/vod/fichas.txt")!

    /// "f|Nome" ou "s|Nome" -> os gêneros dele.
    private static var mapa: [String: [String]] = [:]
    /// Título -> endereço inteiro do pôster, quando o TMDB conhece o título.
    private static var capas: [String: String] = [:]
    /// Título -> id do TMDB. O gerador já resolveu qual título é qual; com o
    /// id em mãos, a ficha completa é um pedido só, sem busca nem desempate.
    private static var ids: [String: Int] = [:]
    /// O caminho inverso: id do TMDB -> título do acervo.
    ///
    /// É assim que a filmografia de um ator vira uma lista clicável: o TMDB
    /// devolve os ids dos trabalhos dele, e só entram na tela os que este mapa
    /// conhece — ou seja, os que existem no acervo.
    private static var porId: [Int: String] = [:]
    /// Todos os gêneros que aparecem no acervo, em ordem alfabética.
    private(set) static var todos: [String] = []
    private static var carregando = false

    static var prontos: Bool { !mapa.isEmpty }

    private static func chave(_ titulo: String, serie: Bool) -> String {
        (serie ? "s|" : "f|") + titulo
    }

    /// Os gêneros de um título.
    ///
    /// A chave é o nome como o acervo o escreve — e o acervo escreve o ano
    /// dentro do nome do filme, mas guarda o da série num campo à parte. Quem
    /// chama nem sempre sabe de qual dos dois veio, então procura-se o nome
    /// como ele chegou e, não achando, sem o ano.
    static func de(_ titulo: String, serie: Bool) -> [String] {
        if let achados = mapa[chave(titulo, serie: serie)] { return achados }
        return mapa[chave(semAno(titulo), serie: serie)] ?? []
    }

    /// O pôster de um título, pelo id que o gerador já resolveu.
    ///
    /// Antes a capa era procurada pelo nome no TMDB, a cada abertura: lento, e
    /// errado quando dois filmes se chamam igual. Agora o endereço vem pronto
    /// do mesmo arquivo dos gêneros. Quem não tem ficha fica sem capa, e a tela
    /// põe uma marca no lugar.
    static func capa(_ titulo: String, serie: Bool) -> String? {
        capas[chave(titulo, serie: serie)] ?? capas[chave(semAno(titulo), serie: serie)]
    }

    /// O id do TMDB de um título, quando o gerador o resolveu.
    static func id(_ titulo: String, serie: Bool) -> Int? {
        ids[chave(titulo, serie: serie)] ?? ids[chave(semAno(titulo), serie: serie)]
    }

    /// O título do acervo que corresponde a um id do TMDB, se houver.
    static func titulo(paraId id: Int, serie: Bool) -> String? {
        porId[marca(id, serie: serie)]
    }

    private static func marca(_ id: Int, serie: Bool) -> Int {
        serie ? -id : id
    }

    static func semAno(_ titulo: String) -> String {
        titulo.replacingOccurrences(of: #"\s*\(\d{4}\)\s*$"#,
                                    with: "",
                                    options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
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
        var novasCapas: [String: String] = [:]
        var novosIds: [String: Int] = [:]
        var novoPorId: [Int: String] = [:]
        var vistos = Set<String>()
        var base = ""
        // tipo \t título \t id do TMDB \t pôster \t gêneros
        for linha in texto.split(separator: "\n") {
            if linha.hasPrefix("capa:") {
                base = linha.dropFirst("capa:".count).trimmingCharacters(in: .whitespaces)
                continue
            }
            if linha.hasPrefix("#") { continue }
            let campos = linha.split(separator: "\t", omittingEmptySubsequences: false)
            guard campos.count >= 5 else { continue }
            let chave = "\(campos[0])|\(campos[1])"
            if !campos[3].isEmpty { novasCapas[chave] = base + campos[3] }
            if let id = Int(campos[2]), id > 0 {
                novosIds[chave] = id
                let serie = campos[0] == "s"
                // Um mesmo id pode aparecer duas vezes no acervo (o mesmo
                // filme em duas grafias); o primeiro basta.
                let marcaDoId = serie ? -id : id
                if novoPorId[marcaDoId] == nil { novoPorId[marcaDoId] = String(campos[1]) }
            }
            let lista = campos[4].split(separator: ",").map(String.init)
            if !lista.isEmpty {
                novo[chave] = lista
                lista.forEach { vistos.insert($0) }
            }
        }
        mapa = novo
        capas = novasCapas
        ids = novosIds
        porId = novoPorId
        todos = vistos.sorted()
    }

    private static var arquivo: URL {
        let pasta = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SaimoTV", isDirectory: true)
        try? FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        return pasta.appendingPathComponent("fichas.txt")
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
