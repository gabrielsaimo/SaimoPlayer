import Foundation

/// O anúncio da versão mais nova, lido de `versao.json` (ver `Enderecos.canais`).
///
/// Nada aqui sabe de dono ou repositório: o endereço do instalador vem no
/// próprio JSON e só é aceito se tiver cara de download de release do GitHub.
struct VersaoPublicada: Equatable {
    let tag: String
    let numero: String
    let notas: String
    let dmg: URL
    let tamanho: Int64?
    let sha256: String?

    /// Lê o JSON; nulo para qualquer coisa fora do contrato (nunca lança).
    static func ler(_ dados: Data) -> VersaoPublicada? {
        guard let raiz = try? JSONSerialization.jsonObject(with: dados) as? [String: Any],
              let mac = (raiz["arquivos"] as? [String: Any])?["mac"] as? [String: Any],
              let texto = mac["url"] as? String,
              let endereco = URL(string: texto), downloadPermitido(endereco)
        else { return nil }

        // A tag (ou, faltando, a versão) precisa ter cara de versão ("v1.2" ou
        // "1.2.3"). Um "beta-v2" não diz o que é mais novo que o quê.
        let tag = (raiz["tag"] as? String) ?? (raiz["versao"] as? String).map { "v\($0)" }
        guard let tag, let numero = Atualizacao.numeroDaTag(tag) else { return nil }

        let bytes = (mac["bytes"] as? NSNumber)?.int64Value
        let resumo = (mac["sha256"] as? String)?.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // sha256 presente mas malformado: recusa o anúncio em vez de baixar
        // sem a conferência prometida.
        if let resumo, resumo.range(of: "^[0-9a-f]{64}$", options: .regularExpression) == nil {
            return nil
        }
        return VersaoPublicada(tag: tag, numero: numero,
                               notas: (raiz["notas"] as? String) ?? "",
                               dmg: endereco,
                               tamanho: bytes.flatMap { $0 > 0 ? $0 : nil },
                               sha256: resumo)
    }

    /// `https://github.com/<dono>/<repo>/releases/download/<tag>/<arquivo>`.
    static func downloadPermitido(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.host?.lowercased() == "github.com",
              url.user == nil, url.port == nil else { return false }
        let partes = url.path.split(separator: "/", omittingEmptySubsequences: false)
        // ["", dono, repo, "releases", "download", tag, arquivo…]
        return partes.count >= 7 && partes[0].isEmpty && !partes[1].isEmpty && !partes[2].isEmpty
            && partes[3] == "releases" && partes[4] == "download"
            && !partes[5].isEmpty && !partes[6].isEmpty
    }

    /// Para onde o GitHub pode redirecionar o download (a CDN dos arquivos).
    static func redirecionamentoPermitido(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return host == "objects.githubusercontent.com"
            || host == "release-assets.githubusercontent.com"
            || downloadPermitido(url)
    }

    /// A página da versão, derivada do próprio endereço do instalador.
    var pagina: URL? {
        var partes = dmg.pathComponents  // ["/", dono, repo, "releases", "download", tag, arquivo]
        guard partes.count >= 7 else { return nil }
        partes = Array(partes[1...3]) + ["tag", partes[5]]
        var c = URLComponents()
        c.scheme = "https"; c.host = "github.com"
        c.path = "/" + partes.joined(separator: "/")
        return c.url
    }
}
