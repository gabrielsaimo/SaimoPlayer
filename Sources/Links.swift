import Foundation

/// A lógica dos endereços das listas, sem tela: normalização, o pedido que
/// valida um endereço e as decisões de "o que mostrar quando não há dados".
/// Fica separada da interface para ser testada sozinha (`scripts/testar_links.sh`).
enum Links {

    // MARK: - Normalização

    enum Resultado: Equatable {
        /// Campo em branco: sem endereço.
        case vazio
        /// Endereço-base pronto, sempre terminado em `/`.
        case valido(String)
        case invalido
    }

    /// Normalização única do contrato "app sem listas":
    /// 1. `trim`; vazio = sem endereço.
    /// 2. Sem `://` → prefixa `https://`. Só `http` e `https`; outro esquema,
    ///    espaço no meio ou host vazio = inválido.
    /// 3. Tira `?query` e `#fragmento`.
    /// 4. Se o último trecho do caminho tem ponto (`catalogo.txt`), descarta-o.
    /// 5. Garante `/` no fim.
    static func normalizar(_ entrada: String) -> Resultado {
        let texto = entrada.trimmingCharacters(in: .whitespacesAndNewlines)
        if texto.isEmpty { return .vazio }
        if texto.contains(where: { $0.isWhitespace || $0.isNewline }) { return .invalido }

        var esquema = "https"
        var resto = texto
        if let marca = texto.range(of: "://") {
            esquema = texto[texto.startIndex..<marca.lowerBound].lowercased()
            resto = String(texto[marca.upperBound...])
            guard esquema == "http" || esquema == "https" else { return .invalido }
        }

        // ?query e #fragmento saem antes de olhar o caminho.
        if let corte = resto.firstIndex(where: { $0 == "?" || $0 == "#" }) {
            resto = String(resto[resto.startIndex..<corte])
        }

        let barra = resto.firstIndex(of: "/")
        let host = String(barra.map { resto[resto.startIndex..<$0] } ?? resto[...])
        var caminho = barra.map { String(resto[$0...]) } ?? "/"
        guard hostValido(host) else { return .invalido }

        // A pessoa colou o arquivo (catalogo.txt), não a pasta.
        if !caminho.hasSuffix("/") {
            var trechos = caminho.split(separator: "/", omittingEmptySubsequences: false)
            if let ultimo = trechos.last, ultimo.contains(".") { trechos.removeLast() }
            caminho = trechos.joined(separator: "/")
        }
        if !caminho.hasSuffix("/") { caminho += "/" }
        if !caminho.hasPrefix("/") { caminho = "/" + caminho }

        return .valido("\(esquema)://\(host.lowercased())\(caminho)")
    }

    /// `nome`, `nome.dominio` ou IP, com porta opcional. Sem usuário/senha.
    private static func hostValido(_ host: String) -> Bool {
        guard !host.isEmpty else { return false }
        var nome = host
        if let doisPontos = host.lastIndex(of: ":"), !host.hasSuffix("]") {
            let porta = host[host.index(after: doisPontos)...]
            guard !porta.isEmpty, porta.count <= 5, porta.allSatisfy(\.isNumber) else { return false }
            nome = String(host[host.startIndex..<doisPontos])
        }
        guard !nome.isEmpty, !nome.hasPrefix("."), !nome.hasPrefix("-") else { return false }
        return nome.unicodeScalars.allSatisfy {
            ($0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains($0))) || $0 == "." || $0 == "-"
        }
    }

    // MARK: - Teste do endereço

    enum Tipo: Equatable {
        case canais, filmes

        /// O arquivo que precisa responder 200 para o endereço valer.
        var arquivoDeTeste: String { self == .canais ? "catalogo.txt" : "indice.txt" }
        var rotulo: String { self == .canais ? "Canais" : "Filmes e séries" }
    }

    /// `GET <base><arquivo de teste>`.
    static func pedidoDeTeste(base: String, tipo: Tipo) -> URLRequest? {
        guard let url = URL(string: base + tipo.arquivoDeTeste) else { return nil }
        var pedido = URLRequest(url: url)
        pedido.httpMethod = "GET"
        pedido.timeoutInterval = 15
        pedido.cachePolicy = .reloadIgnoringLocalCacheData
        return pedido
    }

    /// Só 200 conta.
    static func respostaAceita(_ codigo: Int?) -> Bool { codigo == 200 }

    static func testar(base: String, tipo: Tipo) async -> Bool {
        guard let pedido = pedidoDeTeste(base: base, tipo: tipo),
              let (_, resposta) = try? await URLSession.shared.data(for: pedido)
        else { return false }
        return respostaAceita((resposta as? HTTPURLResponse)?.statusCode)
    }

    // MARK: - Decisões de tela

    enum Secao: Equatable {
        case canais, filmes, radios, guia
    }

    static func semEndereco(_ secao: Secao, canais: String?, filmes: String?) -> Bool {
        switch secao {
        case .canais, .radios, .guia: return (canais ?? "").isEmpty
        case .filmes: return (filmes ?? "").isEmpty
        }
    }

    /// O texto do estado vazio de cada seção quando falta o endereço.
    static func mensagemSemEndereco(_ secao: Secao) -> String {
        switch secao {
        case .canais: return "Nenhum canal. Ative a lista de canais em Ajustes > Listas."
        case .filmes: return "Nenhum filme ou série. Ative o endereço da lista de filmes e séries em Ajustes > Listas."
        case .radios: return "Nenhuma rádio. Ative a lista de canais em Ajustes > Listas."
        case .guia: return "Sem programação. Ative a lista de canais em Ajustes > Listas."
        }
    }

    /// Quando há endereço mas a lista veio vazia ou não abriu.
    static func mensagemListaVazia(_ secao: Secao) -> String {
        switch secao {
        case .canais: return "Nenhum canal na lista informada. Confira o endereço em Ajustes > Listas."
        case .filmes: return "Nenhum filme ou série na lista informada. Confira o endereço em Ajustes > Listas."
        case .radios: return "Nenhuma rádio na lista informada. Confira o endereço em Ajustes > Listas."
        case .guia: return "Sem programação para os canais da lista."
        }
    }

    /// A mensagem do estado vazio de uma seção, conforme haja ou não endereço.
    static func mensagemVazia(_ secao: Secao, canais: String?, filmes: String?) -> String {
        semEndereco(secao, canais: canais, filmes: filmes)
            ? mensagemSemEndereco(secao) : mensagemListaVazia(secao)
    }

    static let textoDoDialogo =
        "Endereço da lista de canais e da lista de filmes e séries. Deixe um campo em branco para desligar aquela lista, ou use Restaurar padrão."
    static let erroDeEndereco = "Não consegui abrir este endereço. Confira o link."
    static let erroDeFormato = "Endereço inválido. Confira o link."

    // MARK: - Salvar

    /// O que fazer com o que foi digitado nos dois campos ao Salvar.
    struct Plano: Equatable {
        var canais: Resultado
        var filmes: Resultado
        /// Há algum campo preenchido, mas inválido: nada é salvo.
        var temInvalido: Bool { canais == .invalido || filmes == .invalido }
        /// Endereços preenchidos que precisam do teste de rede.
        var aTestar: [(Tipo, String)] {
            var itens: [(Tipo, String)] = []
            if case .valido(let b) = canais { itens.append((.canais, b)) }
            if case .valido(let b) = filmes { itens.append((.filmes, b)) }
            return itens
        }
        static func == (a: Plano, b: Plano) -> Bool { a.canais == b.canais && a.filmes == b.filmes }
    }

    static func planejar(canais: String, filmes: String) -> Plano {
        Plano(canais: normalizar(canais), filmes: normalizar(filmes))
    }
}
