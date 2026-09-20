import Foundation

/// Servidores desligados à mão, no painel do monitor.
///
/// Quando um provedor cai, cai inteiro: não é a fonte 3 de um canal que
/// morreu, é o servidor que parou de responder para todo mundo. Editar o
/// catálogo publicado a cada queda é lento e some com o link, que depois
/// precisa voltar. Desligar o servidor no painel some com ele de todo canal e
/// de todo filme, em todos os aplicativos, e religar devolve tudo.
///
/// A lista é baixada sem chave nenhuma: são nomes de servidor, que o catálogo
/// publicado já mostra, e exigir segredo significaria embutir um segredo num
/// aplicativo que qualquer um baixa.
///
/// Na primeira abertura sem rede a lista vem vazia, e nada é escondido — o
/// erro certo a cometer: um canal a mais na tela é melhor que a lista inteira
/// sumindo porque o monitor não respondeu.
enum FontesDesativadas {

    private static let endereco = URL(
        string: "https://saimo-monitor.gabrielsaimo68.workers.dev/v1/fontes")!
    /// Desligar um servidor tem que valer em minutos, que é o tempo que alguém
    /// aguenta um canal quebrado.
    private static let validade: TimeInterval = 120

    private static var hosts: Set<String> = []
    private static var lidoEm: Date = .distantPast

    /// Os servidores desligados agora, sem ir à rede.
    static var atuais: Set<String> { hosts }

    /// Busca a lista quando ela envelheceu. Devolve `true` quando mudou, que é
    /// quando quem chamou precisa redesenhar a lista de canais.
    @discardableResult
    static func atualizar() async -> Bool {
        if Date().timeIntervalSince(lidoEm) < validade { return false }
        var pedido = URLRequest(url: endereco)
        pedido.setValue("*/*", forHTTPHeaderField: "Accept")
        pedido.timeoutInterval = 10
        // A resposta vem com `max-age` de dois minutos, e o URLSession o
        // respeita: somado ao relógio daqui, a lista podia demorar o dobro
        // para mudar. Quem manda no ritmo é este relógio, um só.
        pedido.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (dados, resposta) = try? await URLSession.shared.data(for: pedido),
              let http = resposta as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let corpo = try? JSONSerialization.jsonObject(with: dados) as? [String: Any],
              let lista = corpo["desativados"] as? [String]
        else { return false }

        lidoEm = Date()
        let novos = Set(lista.map { $0.lowercased() })
        guard novos != hosts else { return false }
        hosts = novos
        Log.shared.write(novos.isEmpty
            ? "nenhum servidor desligado"
            : "servidores desligados: \(novos.sorted().joined(separator: ", "))")
        return true
    }

    static func desligado(_ url: URL?) -> Bool {
        guard let host = url?.host?.lowercased() else { return false }
        return hosts.contains(host)
    }

    static func desligado(_ endereco: String) -> Bool {
        desligado(URL(string: endereco))
    }

    /// O catálogo sem o que está desligado.
    ///
    /// Canal que fica sem nenhuma fonte sai da lista: ele não abriria mesmo, e
    /// deixá-lo ali só rende clique frustrado. Volta sozinho quando o servidor
    /// for religado.
    static func peneirar(_ canais: [Channel]) -> [Channel] {
        guard !hosts.isEmpty else { return canais }
        var mexidos = 0
        var sumiram = 0
        let out: [Channel] = canais.compactMap { canal in
            let vivas = canal.variants.filter { !desligado($0.url) }
            if vivas.isEmpty { sumiram += 1; return nil }
            if vivas.count == canal.variants.count { return canal }
            mexidos += 1
            var copia = canal
            copia.variants = vivas
            return copia
        }
        if mexidos > 0 || sumiram > 0 {
            Log.shared.write("fontes desligadas: \(mexidos) canal(is) perderam fonte, "
                             + "\(sumiram) sumiram da lista")
        }
        return out
    }

    /// Os endereços de um filme ou episódio sem os que estão desligados.
    static func peneirar(_ enderecos: [String]) -> [String] {
        guard !hosts.isEmpty else { return enderecos }
        return enderecos.filter { !desligado($0) }
    }
}
