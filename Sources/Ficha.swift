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
    /// Quantas temporadas a série tem, segundo o TMDB.
    var temporadas: Int?

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
        // w1280: no Mac o fundo ocupa a janela inteira, e em tela Retina o
        // w780 aparecia borrado.
        if let caminho = json["backdrop_path"] as? String {
            ficha.fundo = imagens + "w1280" + caminho
        }
        if serie, let n = json["number_of_seasons"] as? Int, n > 0 { ficha.temporadas = n }

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

    /// Um trabalho da pessoa que existe no acervo, com a capa que o TMDB já mandou.
    struct Trabalho: Identifiable, Sendable {
        let achado: Vod.Achado
        let capa: String?
        let papel: String
        var id: String { achado.id }
    }

    /// Nome -> título do acervo, montado uma vez: são 47 mil títulos, e
    /// remontar a cada ator aberto era o que deixava a tela lenta.
    private static var porNome: [String: Vod.Achado] = [:]

    /// Prepara o índice enquanto a pessoa lê a ficha: quando ela escolhe um
    /// ator, o cruzamento já não espera.
    static func aquecer() async {
        guard porNome.isEmpty else { return }
        var mapa: [String: Vod.Achado] = [:]
        for achado in await Vod.todos() {
            mapa[(achado.serie ? "s:" : "f:") + achado.titulo] = achado
        }
        porNome = mapa
    }

    /// O que um ator fez e que existe no acervo, já pronto para abrir.
    ///
    /// O cruzamento é pelo id do TMDB: o arquivo de fichas diz o id de cada
    /// título do acervo, e a filmografia do TMDB vem em ids. Nome igual não
    /// engana e refilmagem não vira o original. A capa vem da própria resposta
    /// do TMDB — a do arquivo de fichas falta para boa parte desses títulos.
    static func acervoDe(ator id: Int) async -> [Trabalho] {
        guard let json = await pedir("\(base)/person/\(id)/combined_credits?api_key=\(chave)&language=pt-BR")
        else { return [] }

        let trabalhos = (json["cast"] as? [[String: Any]] ?? [])
            + (json["crew"] as? [[String: Any]] ?? [])
        // Ordem de popularidade: o que a pessoa é mais conhecida por fazer
        // vem primeiro, e não a ordem em que o TMDB devolveu.
        let ordenados = trabalhos.sorted {
            (($0["popularity"] as? Double) ?? 0) > (($1["popularity"] as? Double) ?? 0)
        }

        await aquecer()
        var vistos = Set<String>()
        var saida: [Trabalho] = []
        for trabalho in ordenados {
            guard let idDoTitulo = trabalho["id"] as? Int else { continue }
            let serie = (trabalho["media_type"] as? String) == "tv"
            guard let titulo = Generos.titulo(paraId: idDoTitulo, serie: serie) else { continue }
            let marca = serie ? "s:" : "f:"
            guard let achado = porNome[marca + titulo] ?? porNome[marca + Generos.semAno(titulo)]
            else { continue }
            if !vistos.insert(achado.id).inserted { continue }
            let capa = (trabalho["poster_path"] as? String).map { imagens + "w342" + $0 }
                ?? Generos.capa(achado.nomeCompleto, serie: achado.serie)
            let papel = (trabalho["character"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? (trabalho["job"] as? String) ?? ""
            saida.append(Trabalho(achado: achado, capa: capa, papel: papel))
        }
        return saida
    }

    /// Quem é a pessoa: foto grande, biografia, nascimento, de onde é.
    struct Perfil: Sendable {
        var nome = ""
        var foto: String?
        var biografia = ""
        var nascimento = ""
        var falecimento = ""
        var local = ""
        var conhecidaPor = ""

        /// "Atuação · 1956 · 70 anos · Concord, California, USA"
        var dados: String {
            var partes: [String] = []
            if !conhecidaPor.isEmpty { partes.append(conhecidaPor) }
            if let nasceu = Int(nascimento.prefix(4)) {
                if let morreu = Int(falecimento.prefix(4)) {
                    partes.append("\(nasceu) – \(morreu)")
                } else {
                    let agora = Calendar.current.component(.year, from: Date())
                    partes.append("\(nasceu) · \(agora - nasceu) anos")
                }
            }
            if !local.isEmpty { partes.append(local) }
            return partes.joined(separator: "  ·  ")
        }
    }

    private static var perfis: [Int: Perfil] = [:]

    /// A biografia em português falta para quase todo mundo que não é
    /// brasileiro; sem ela vale a em inglês — melhor que um vazio sob a foto.
    static func perfil(_ id: Int) async -> Perfil? {
        if let pronto = perfis[id] { return pronto }
        guard let json = await pedir("\(base)/person/\(id)?api_key=\(chave)&language=pt-BR")
        else { return nil }
        var perfil = Perfil()
        perfil.nome = json["name"] as? String ?? ""
        perfil.foto = (json["profile_path"] as? String).map { imagens + "h632" + $0 }
        perfil.biografia = json["biography"] as? String ?? ""
        if perfil.biografia.isEmpty,
           let ingles = await pedir("\(base)/person/\(id)?api_key=\(chave)&language=en-US") {
            perfil.biografia = ingles["biography"] as? String ?? ""
        }
        perfil.nascimento = json["birthday"] as? String ?? ""
        perfil.falecimento = json["deathday"] as? String ?? ""
        perfil.local = json["place_of_birth"] as? String ?? ""
        perfil.conhecidaPor = switch json["known_for_department"] as? String {
        case "Acting": "Atuação"
        case "Directing": "Direção"
        case "Writing": "Roteiro"
        case "Production": "Produção"
        case "Sound": "Música"
        default: ""
        }
        perfis[id] = perfil
        return perfil
    }

    private static func pedir(_ endereco: String) async -> [String: Any]? {
        guard let url = URL(string: endereco) else { return nil }
        var pedido = URLRequest(url: url)
        pedido.timeoutInterval = 8
        pedido.setValue(Upstream.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (dados, resposta) = try? await URLSession.shared.data(for: pedido),
              let http = resposta as? HTTPURLResponse, (200...299).contains(http.statusCode)
        else { return nil }
        return try? JSONSerialization.jsonObject(with: dados) as? [String: Any]
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
