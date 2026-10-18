import Foundation
import os

/// As tabelas do guia de programação por canal, lidas de `guia.txt`
/// (servido pelo endereço da lista de canais). Nada disto mora no código.
///
/// Linhas com TAB; `#` comenta:
///   `meuguia<TAB>nome do canal no catálogo<TAB>código`
///   `guiadetv<TAB>nome normalizado<TAB>endereço (ou só o final dele)`
///   `alias<TAB>nome normalizado<TAB>nome no feed`
///   `feed<TAB>-<TAB>url` (vale a ordem)
///   `pluto<TAB>-<TAB>url`
struct GuiaTabelas: Equatable, Sendable {
    var meuguia: [String: String] = [:]
    var guiadetv: [String: String] = [:]
    var aliases: [String: String] = [:]
    var feeds: [URL] = []
    var pluto: URL?

    var vazia: Bool {
        meuguia.isEmpty && guiadetv.isEmpty && aliases.isEmpty && feeds.isEmpty && pluto == nil
    }

    static func ler(_ texto: String) -> GuiaTabelas {
        var t = GuiaTabelas()
        for bruta in texto.split(whereSeparator: \.isNewline) {
            let linha = String(bruta)
            if linha.trimmingCharacters(in: .whitespaces).hasPrefix("#") { continue }
            let campos = linha.split(separator: "\t", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard campos.count >= 3, !campos[2].isEmpty else { continue }
            switch campos[0].lowercased() {
            case "meuguia":
                if !campos[1].isEmpty { t.meuguia[campos[1]] = campos[2] }
            case "guiadetv":
                if !campos[1].isEmpty { t.guiadetv[campos[1]] = campos[2] }
            case "alias":
                if !campos[1].isEmpty { t.aliases[campos[1]] = campos[2] }
            case "feed":
                if let url = enderecoWeb(campos[2]), !t.feeds.contains(url) { t.feeds.append(url) }
            case "pluto":
                if let url = enderecoWeb(campos[2]) { t.pluto = url }
            default:
                continue
            }
        }
        return t
    }

    private static func enderecoWeb(_ texto: String) -> URL? {
        guard let url = URL(string: texto), let e = url.scheme?.lowercased(),
              e == "http" || e == "https", url.host != nil else { return nil }
        return url
    }

    /// Endereço da página de um canal no guiadetv: a tabela traz o endereço
    /// inteiro ou só o final dele (`espn-2`).
    static func paginaDoGuiaDeTv(_ valor: String) -> URL? {
        if valor.hasPrefix("http") { return enderecoWeb(valor) }
        let limpo = valor.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !limpo.isEmpty else { return nil }
        return URL(string: "https://www.guiadetv.com/canal/\(limpo)")
    }

    // MARK: - Tabela em uso

    private static let guardada = OSAllocatedUnfairLock(initialState: GuiaTabelas())

    /// A tabela de agora: a do último `guia.txt` lido (disco ou rede).
    static var atual: GuiaTabelas {
        get { guardada.withLock { $0 } }
        set { guardada.withLock { $0 = newValue } }
    }

    private static var arquivo: URL {
        let pasta = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SaimoTV", isDirectory: true)
        try? FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        return pasta.appendingPathComponent("guia.txt")
    }

    /// Carrega do disco, sem rede. Sem endereço de canais, a tabela é vazia.
    static func carregarDoDisco() {
        guard Enderecos.canais != nil,
              let texto = try? String(contentsOf: arquivo, encoding: .utf8) else {
            atual = GuiaTabelas()
            return
        }
        atual = ler(texto)
    }

    /// Baixa `guia.txt` do endereço dos canais e guarda em disco. Sem endereço
    /// não faz pedido nenhum. Falha de rede mantém o que já estava.
    static func baixar() async {
        guard let url = Enderecos.canais("guia.txt") else { atual = GuiaTabelas(); return }
        var pedido = URLRequest(url: url)
        pedido.timeoutInterval = 20
        pedido.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (dados, resposta) = try? await URLSession.shared.data(for: pedido),
              let http = resposta as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let texto = String(data: dados, encoding: .utf8)
        else {
            if atual.vazia { carregarDoDisco() }
            return
        }
        let lida = ler(texto)
        guard !lida.vazia else { return }
        try? dados.write(to: arquivo, options: .atomic)
        atual = lida
    }
}
