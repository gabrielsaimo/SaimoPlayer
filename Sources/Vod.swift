import Foundation

struct Filme: Identifiable, Hashable {
    var titulo: String
    /// Versão ("dub"/"leg") -> fontes em ordem de preferência. O mesmo filme
    /// existe nas duas listas de origem, e em vez de aparecer duas vezes ele
    /// aparece uma com as duas fontes.
    var fontes: [String: [String]]
    var id: String { titulo }
}

struct Serie: Identifiable, Hashable {
    var titulo: String
    var ano: String
    var pedaco: Int
    var episodios: Int
    var nomeCompleto: String { ano.isEmpty ? titulo : "\(titulo) (\(ano))" }
    var id: String { nomeCompleto }
}

struct Episodio: Identifiable, Hashable {
    var temporada: Int
    var numero: Int
    var versao: String
    var urls: [String]
    var id: String { "\(temporada)-\(numero)-\(versao)" }
}

/// Filmes e séries, baixados por pedaço conforme a navegação desce.
///
/// A lista de origem tem 30 MB e 300 mil linhas. Ela é pré-digerida num catálogo
/// fatiado por letra — e as séries ainda em pedaços dentro da letra — de modo
/// que nenhum download passe de uns 100 KB. Como a tela também navega por letra,
/// o download acompanha o clique em vez de contrariá-lo.
enum Vod {

    private static let base =
        "https://raw.githubusercontent.com/gabrielsaimo/SaimoPlayer/main/vod/"

    struct Gaveta: Identifiable, Hashable {
        var letra: String
        var filmes: Int
        var series: Int
        var reservados: Int
        var id: String { letra }
    }

    private static var bases: [String] = []

    /// Sobe quando o formato do catálogo muda.
    ///
    /// O cache é por arquivo e dura entre aberturas, então um catálogo gravado
    /// por uma versão antiga sobrevive à atualização do app — foi assim que um
    /// índice sem as linhas `base:` deixou todo filme com endereço quebrado.
    /// Guardar a versão junto e limpar a pasta quando ela muda evita que o
    /// formato velho envenene o novo.
    private static let versaoCache = "3"

    static func indice() async -> [Gaveta] {
        conferirVersao()
        guard let texto = await arquivo("indice.txt") else { return [] }
        var out: [Gaveta] = []
        var encontradas: [String] = []
        for linha in texto.split(separator: "\n") {
            if linha.hasPrefix("base:") {
                let partes = String(linha.dropFirst("base:".count))
                    .trimmingCharacters(in: .whitespaces)
                    .split(separator: " ", maxSplits: 1)
                if partes.count == 2 { encontradas.append(String(partes[1])) }
            } else {
                let campos = linha.split(separator: "\t", omittingEmptySubsequences: false)
                if campos.count >= 3 {
                    out.append(Gaveta(letra: String(campos[0]),
                                      filmes: Int(campos[1]) ?? 0,
                                      series: Int(campos[2]) ?? 0,
                                      reservados: campos.count > 3 ? (Int(campos[3]) ?? 0) : 0))
                }
            }
        }
        if !encontradas.isEmpty { bases = encontradas }
        return out
    }

    static func filmes(letra: String, reservados: Bool = false) async -> [Filme] {
        let prefixo = reservados ? "reservado" : "filmes"
        guard let texto = await arquivo("\(prefixo)-\(gaveta(letra)).txt") else { return [] }
        return texto.split(separator: "\n").compactMap { linha in
            let campos = linha.split(separator: "\t", omittingEmptySubsequences: false)
            guard campos.count >= 2, !campos[0].isEmpty else { return nil }
            var fontes: [String: [String]] = [:]
            for parte in campos.dropFirst() {
                guard let marca = parte.firstIndex(of: "=") else { continue }
                let versao = String(parte[parte.startIndex..<marca])
                let lista = String(parte[parte.index(after: marca)...])
                    .split(separator: ",").map { montar(String($0)) }
                    .filter { !$0.isEmpty }
                if !lista.isEmpty { fontes[versao] = lista }
            }
            return fontes.isEmpty ? nil : Filme(titulo: String(campos[0]), fontes: fontes)
        }
    }

    static func series(letra: String) async -> [Serie] {
        guard let texto = await arquivo("series-\(gaveta(letra)).txt") else { return [] }
        return texto.split(separator: "\n").compactMap { linha in
            let campos = linha.split(separator: "\t", omittingEmptySubsequences: false)
            guard campos.count >= 4, !campos[0].isEmpty else { return nil }
            return Serie(titulo: String(campos[0]), ano: String(campos[1]),
                         pedaco: Int(campos[2]) ?? 0, episodios: Int(campos[3]) ?? 0)
        }
    }

    /// Episódios de uma série. Baixa só o pedaço em que ela está.
    static func episodios(letra: String, serie: Serie) async -> [Episodio] {
        let nome = "series-\(gaveta(letra))-\(serie.pedaco).txt"
        guard let texto = await arquivo(nome) else { return [] }
        var out: [Episodio] = []
        var dentro = false
        for linha in texto.split(separator: "\n", omittingEmptySubsequences: false) {
            if linha.hasPrefix("@") {
                if dentro { break }
                let identidade = linha.dropFirst().split(
                    separator: "\t", omittingEmptySubsequences: false)
                let titulo = identidade.first.map(String.init) ?? ""
                let ano = identidade.count > 1 ? String(identidade[1]) : ""
                dentro = titulo == serie.titulo && ano == serie.ano
                continue
            }
            guard dentro else { continue }
            let campos = linha.split(separator: "\t", omittingEmptySubsequences: false)
            guard campos.count >= 4 else { continue }
            let urls = campos[3].split(separator: ",").map { montar(String($0)) }
                .filter { !$0.isEmpty }
            guard !urls.isEmpty else { continue }
            out.append(Episodio(temporada: Int(campos[0]) ?? 0,
                                numero: Int(campos[1]) ?? 0,
                                versao: String(campos[2]),
                                urls: urls))
        }
        return out
    }

    // MARK: - Acervo inteiro

    struct Achado: Identifiable, Hashable {
        let titulo: String
        let serie: Bool
        let letra: String
        let ano: String
        var nomeCompleto: String { ano.isEmpty ? titulo : "\(titulo) (\(ano))" }
        var id: String { (serie ? "s:" : "f:") + nomeCompleto }
    }

    @MainActor
    private static var indiceBusca: [Achado] = []

    /// Todo o acervo numa lista só, para procurar sem escolher letra.
    ///
    /// O índice traz nome, tipo e letra — 780 KB para trinta mil títulos —,
    /// então dá para varrer o acervo inteiro sem baixar o acervo. Os extras
    /// ficam de fora dele de propósito: o que não aparece sem o código também
    /// não pode aparecer numa busca geral.
    @MainActor
    static func todos() async -> [Achado] {
        if !indiceBusca.isEmpty { return indiceBusca }
        guard let texto = await arquivo("busca.txt") else { return [] }
        let lidos = texto.split(separator: "\n").compactMap { linha -> Achado? in
            let campos = linha.split(separator: "\t", omittingEmptySubsequences: false)
            guard campos.count >= 3, !campos[0].isEmpty else { return nil }
            return Achado(titulo: String(campos[0]),
                          serie: campos[1] == "s",
                          letra: String(campos[2]),
                          ano: campos.count > 3 ? String(campos[3]) : "")
        }
        indiceBusca = lidos
        return lidos
    }

    /// Os extras inteiros, juntando as letras que têm algum.
    ///
    /// Eles não entram no índice de busca de propósito — o que não aparece sem
    /// o código também não pode aparecer numa busca comum —, então aqui a lista
    /// é montada lendo os arquivos por letra. São só os nomes: as fontes ficam
    /// para a hora de abrir, como na navegação normal.
    static func todosReservados(_ letras: [String]) async -> [Achado] {
        var out: [Achado] = []
        for letra in letras {
            guard let texto = await arquivo("reservado-\(gaveta(letra)).txt") else { continue }
            for linha in texto.split(separator: "\n") {
                let campos = linha.split(separator: "\t", omittingEmptySubsequences: false)
                guard campos.count >= 2, !campos[0].isEmpty else { continue }
                out.append(Achado(titulo: String(campos[0]), serie: false,
                                  letra: letra, ano: ""))
            }
        }
        return out
    }

    /// O item guarda "base:resto"; o endereço inteiro sairia dezenas de vezes
    /// maior, e o começo é sempre o mesmo punhado de servidores.
    private static func montar(_ valor: String) -> String {
        if valor.hasPrefix("http") { return valor }
        // Sem a base o que sobra é "0:19927", que o player aceita como URL de
        // esquema "0" e só falha na hora de tocar. Melhor não devolver fonte.
        guard let corte = valor.firstIndex(of: ":"),
              let indice = Int(valor[valor.startIndex..<corte]),
              bases.indices.contains(indice) else { return "" }
        let resto = String(valor[valor.index(after: corte)...])
        let base = bases[indice]
        return resto.contains(".") ? base + resto : "\(base)\(resto).mp4"
    }

    private static func conferirVersao() {
        let marca = pasta.appendingPathComponent("versao.txt")
        let atual = try? String(contentsOf: marca, encoding: .utf8)
        guard atual != versaoCache else { return }
        let arquivos = (try? FileManager.default.contentsOfDirectory(
            at: pasta, includingPropertiesForKeys: nil)) ?? []
        for arquivo in arquivos { try? FileManager.default.removeItem(at: arquivo) }
        try? versaoCache.write(to: marca, atomically: true, encoding: .utf8)
    }

    private static func gaveta(_ letra: String) -> String {
        letra == "#" ? "%23" : letra
    }

    /// Conteúdo do arquivo, do disco quando já foi baixado. O catálogo muda de
    /// vez em quando e nunca no meio de uma navegação, então o que está em
    /// disco serve: poupa a rede e faz a segunda visita abrir na hora.
    private static func arquivo(_ nome: String) async -> String? {
        let local = pasta.appendingPathComponent(nome.replacingOccurrences(of: "%23", with: "hash"))
        if let texto = try? String(contentsOf: local, encoding: .utf8), !texto.isEmpty {
            return texto
        }
        guard let url = URL(string: base + nome) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue(Upstream.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, resposta) = try? await URLSession.shared.data(for: request),
              let http = resposta as? HTTPURLResponse, (200...299).contains(http.statusCode),
              !data.isEmpty
        else { return nil }
        try? data.write(to: local, options: .atomic)
        return String(decoding: data, as: UTF8.self)
    }

    private static var pasta: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SaimoTV/vod", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
}
