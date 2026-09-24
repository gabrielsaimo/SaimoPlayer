import Foundation

/// A ficha de um título: sinopse, duração, classificação, gêneros e elenco.
///
/// O catálogo publicado traz nome e endereço, e o arquivo de fichas acrescenta
/// o id do TMDB, o pôster e os gêneros — o bastante para desenhar a grade, e
/// pouco demais para quem parou num cartaz e quer saber do que se trata antes
/// de gastar dois minutos abrindo o filme.
///
/// O resto — sinopse, duração, classificação indicativa, quem dirigiu, quem
/// está no elenco — só existe no endereço do próprio título no TMDB, e é um
/// pedido por título aberto, não por título listado. Com o id vindo da ficha
/// não há busca nem desempate: pergunta-se direto pelo número certo.
///
/// Os mesmos campos, com os mesmos nomes, são o que o celular, a TV Box, o
/// Windows e o site mostram — para a ficha de um filme ser a mesma ficha em
/// qualquer tela.
struct Ficha: Sendable {
    struct Pessoa: Identifiable, Sendable {
        let id: Int
        let nome: String
        let papel: String
        let foto: String?
    }

    var titulo: String = ""
    var sinopse: String = ""
    var frase: String = ""
    /// Minutos: do filme, ou de um episódio da série.
    var duracao: Int?
    /// Classificação indicativa brasileira, quando o TMDB a conhece.
    var classificacao: String?
    var nota: Double = 0
    var votos: Int = 0
    var ano: String = ""
    var generos: [String] = []
    /// Quem dirigiu o filme, ou quem criou a série.
    var assinatura: String = ""
    var roteiro: String = ""
    var produtora: String = ""
    var elenco: [Pessoa] = []
    var capa: String?
    var fundo: String?

    var vazia: Bool {
        sinopse.isEmpty && elenco.isEmpty && generos.isEmpty && duracao == nil
    }
}

@MainActor
enum Fichas {

    private static let chave = "15d2ea6d0dc1d476efbca3eba2b9bbfb"
    private static let base = "https://api.themoviedb.org/3"
    private static let imagens = "https://image.tmdb.org/t/p/"

    /// Uma ficha por título aberto, guardada enquanto o app viver.
    private static var guardadas: [String: Ficha] = [:]
    private static var emVoo: Set<String> = []

    /// A ficha de um título, pelo nome do acervo. Nula enquanto não chega.
    static func de(_ titulo: String, serie: Bool) async -> Ficha? {
        let marca = (serie ? "s:" : "f:") + titulo
        if let pronta = guardadas[marca] { return pronta }
        guard !emVoo.contains(marca) else { return nil }
        guard let id = Generos.id(titulo, serie: serie) else { return nil }
        emVoo.insert(marca)
        defer { emVoo.remove(marca) }
        guard let ficha = await baixar(id: id, serie: serie) else { return nil }
        guardadas[marca] = ficha
        return ficha
    }

    private static func baixar(id: Int, serie: Bool) async -> Ficha? {
        let tipo = serie ? "tv" : "movie"
        let extras = serie ? "credits,content_ratings" : "credits,release_dates"
        guard let url = URL(string:
            "\(base)/\(tipo)/\(id)?api_key=\(chave)&language=pt-BR&append_to_response=\(extras)")
        else { return nil }

        var pedido = URLRequest(url: url)
        pedido.timeoutInterval = 8
        pedido.setValue(Upstream.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (dados, resposta) = try? await URLSession.shared.data(for: pedido),
              let http = resposta as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: dados) as? [String: Any]
        else { return nil }

        var ficha = Ficha()
        ficha.titulo = (json[serie ? "name" : "title"] as? String) ?? ""
        ficha.sinopse = (json["overview"] as? String) ?? ""
        ficha.frase = (json["tagline"] as? String) ?? ""
        ficha.nota = (json["vote_average"] as? Double) ?? 0
        ficha.votos = (json["vote_count"] as? Int) ?? 0
        let data = (json[serie ? "first_air_date" : "release_date"] as? String) ?? ""
        ficha.ano = String(data.prefix(4))
        ficha.generos = (json["genres"] as? [[String: Any]] ?? [])
            .compactMap { $0["name"] as? String }
        ficha.duracao = serie
            ? (json["episode_run_time"] as? [Int])?.first
            : json["runtime"] as? Int
        ficha.classificacao = classificacaoBR(json, serie: serie)
        ficha.produtora = ((json["production_companies"] as? [[String: Any]])?
            .first?["name"] as? String) ?? ""
        if let caminho = json["poster_path"] as? String {
            ficha.capa = imagens + "w500" + caminho
        }
        if let caminho = json["backdrop_path"] as? String {
            ficha.fundo = imagens + "w780" + caminho
        }

        let creditos = json["credits"] as? [String: Any] ?? [:]
        let equipe = creditos["crew"] as? [[String: Any]] ?? []
        let direcao = equipe.filter { ($0["job"] as? String) == "Director" }
            .compactMap { $0["name"] as? String }
        // Série não tem diretor único: quem a assina é quem a criou.
        let criadores = (json["created_by"] as? [[String: Any]] ?? [])
            .compactMap { $0["name"] as? String }
        ficha.assinatura = (direcao.isEmpty ? criadores : direcao).prefix(2)
            .joined(separator: ", ")
        let roteiro = equipe
            .filter { ["Screenplay", "Writer", "Story"].contains($0["job"] as? String ?? "") }
            .compactMap { $0["name"] as? String }
        ficha.roteiro = Array(NSOrderedSet(array: roteiro)).prefix(2)
            .compactMap { $0 as? String }.joined(separator: ", ")

        ficha.elenco = (creditos["cast"] as? [[String: Any]] ?? []).prefix(20).map { pessoa in
            Ficha.Pessoa(
                id: pessoa["id"] as? Int ?? 0,
                nome: pessoa["name"] as? String ?? "",
                papel: pessoa["character"] as? String ?? "",
                foto: (pessoa["profile_path"] as? String).map { imagens + "w185" + $0 })
        }
        return ficha
    }

    /// O que um ator fez e que existe no acervo, já pronto para abrir.
    ///
    /// O cruzamento é pelo id do TMDB: o arquivo de fichas diz o id de cada
    /// título do acervo, e a filmografia do TMDB vem em ids. Nome igual não
    /// engana e refilmagem não vira o original.
    static func acervoDe(ator id: Int) async -> [Vod.Achado] {
        guard let url = URL(string:
            "\(base)/person/\(id)/combined_credits?api_key=\(chave)&language=pt-BR")
        else { return [] }
        var pedido = URLRequest(url: url)
        pedido.timeoutInterval = 8
        pedido.setValue(Upstream.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (dados, resposta) = try? await URLSession.shared.data(for: pedido),
              let http = resposta as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: dados) as? [String: Any]
        else { return [] }

        let trabalhos = (json["cast"] as? [[String: Any]] ?? [])
            + (json["crew"] as? [[String: Any]] ?? [])
        // Ordem de popularidade: o que a pessoa é mais conhecida por fazer
        // vem primeiro, e não a ordem em que o TMDB devolveu.
        let ordenados = trabalhos.sorted {
            (($0["popularity"] as? Double) ?? 0) > (($1["popularity"] as? Double) ?? 0)
        }

        let acervo = await Vod.todos()
        var porNome: [String: Vod.Achado] = [:]
        for achado in acervo {
            porNome[(achado.serie ? "s:" : "f:") + achado.titulo] = achado
        }

        var vistos = Set<String>()
        var saida: [Vod.Achado] = []
        for trabalho in ordenados {
            guard let idDoTitulo = trabalho["id"] as? Int else { continue }
            let serie = (trabalho["media_type"] as? String) == "tv"
            guard let titulo = Generos.titulo(paraId: idDoTitulo, serie: serie) else { continue }
            guard let achado = porNome[(serie ? "s:" : "f:") + titulo]
                ?? porNome[(serie ? "s:" : "f:") + Generos.semAno(titulo)] else { continue }
            if vistos.contains(achado.id) { continue }
            vistos.insert(achado.id)
            saida.append(achado)
        }
        return saida
    }

    private static func classificacaoBR(_ json: [String: Any], serie: Bool) -> String? {
        if serie {
            let listas = (json["content_ratings"] as? [String: Any])?["results"] as? [[String: Any]]
            return listas?.first { $0["iso_3166_1"] as? String == "BR" }?["rating"] as? String
        }
        let listas = (json["release_dates"] as? [String: Any])?["results"] as? [[String: Any]]
        let br = listas?.first { $0["iso_3166_1"] as? String == "BR" }
        let datas = br?["release_dates"] as? [[String: Any]] ?? []
        return datas.compactMap { $0["certification"] as? String }
            .first { !$0.isEmpty }
    }
}
