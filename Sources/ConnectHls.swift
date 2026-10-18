import Foundation

/// A lista do canal para o celular, já na régua do Mac.
///
/// `GET /hls?u=<lista>&r=<referer>&ua=<user-agent>` no Saimo Connect (porta
/// 8999): o Mac baixa a lista com os cabeçalhos certos e devolve com os
/// endereços absolutos (os pedaços o celular busca direto na origem) e, quando
/// o canal não traz marca de horário, com a marca sintética de cada trecho
/// escrita (ver `Historico`). Lista mestra tem as variantes reescritas para
/// passar por aqui também. Porte do `ConnectHls.kt` da TV Box.
enum ConnectHls {

    /// A lista de mídia com endereços absolutos e a régua escrita.
    ///
    /// É a mesma para o celular e para o player do Mac (o `ProxyServer` passa
    /// as listas ao vivo por aqui antes de reescrevê-las): é isso que deixa a
    /// data do AVPlayer na mesma régua que o celular lê.
    static func listaDeMidia(_ texto: String, url: URL,
                             absoluto: (String) -> String,
                             trecho: (String) -> String) -> String {
        let linhas = linhasDe(texto)
        if let estendida = Historico.shared.estender(url: url, linhas: linhas,
                                                     absoluto: absoluto, trecho: trecho) {
            return estendida
        }
        // Regra antiga (filme, LL-HLS, BYTERANGE): endereços absolutos e, ao
        // vivo sem marca, a marca contada pela duração declarada.
        let temMarca = linhas.contains { $0.hasPrefix("#EXT-X-PROGRAM-DATE-TIME") }
        let fim = linhas.contains { $0.hasPrefix("#EXT-X-ENDLIST") }
        let sequencia = linhas.first { $0.hasPrefix("#EXT-X-MEDIA-SEQUENCE:") }
            .flatMap { Int64($0.dropFirst("#EXT-X-MEDIA-SEQUENCE:".count).trimmingCharacters(in: .whitespaces)) } ?? 0
        let passo = linhas.first { $0.hasPrefix("#EXT-X-TARGETDURATION:") }
            .flatMap { Double($0.dropFirst("#EXT-X-TARGETDURATION:".count).trimmingCharacters(in: .whitespaces)) }
            .map { max(Int64($0 * 1000), 1) } ?? 6000
        let escreverMarca = !temMarca && !fim
        var indice: Int64 = 0
        var saida = ""
        for l in linhas {
            if l.hasPrefix("#EXT-X-KEY") || l.hasPrefix("#EXT-X-MAP") {
                saida += Historico.uriAbsoluta(l, absoluto) + "\n"
            } else if l.hasPrefix("#EXTINF") {
                // A marca vai antes do EXTINF de cada trecho.
                if escreverMarca {
                    saida += "#EXT-X-PROGRAM-DATE-TIME:\(Historico.marca(Historico.t0 + (sequencia + indice) * passo))\n"
                }
                saida += l + "\n"
            } else if !l.isEmpty, !l.hasPrefix("#") {
                saida += trecho(l) + "\n"
                indice += 1
            } else {
                saida += l + "\n"
            }
        }
        return saida
    }

    static func linhasDe(_ texto: String) -> [String] {
        texto.split(separator: "\n", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// A resposta do `/hls`: código, tipo e corpo.
    static func responder(alvo: String, cabecalho: String) -> (codigo: Int, tipo: String, corpo: String) {
        let consulta = alvo.split(separator: "?", maxSplits: 1).dropFirst().first.map(String.init) ?? ""
        var parametros: [String: String] = [:]
        for par in consulta.split(separator: "&") {
            let kv = par.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard kv.count == 2 else { continue }
            let valor = String(kv[1]).replacingOccurrences(of: "+", with: " ")
            parametros[String(kv[0])] = valor.removingPercentEncoding ?? valor
        }
        guard let u = parametros["u"], u.hasPrefix("http://") || u.hasPrefix("https://"),
              let url = URL(string: u) else {
            return (400, "text/plain", "lista?")
        }
        let referer = parametros["r"].flatMap { $0.isEmpty ? nil : $0 }
        let agente = parametros["ua"].flatMap { $0.isEmpty ? nil : $0 }
        let host = cabecalho.components(separatedBy: "\r\n")
            .first { $0.lowercased().hasPrefix("host:") }
            .map { String($0.dropFirst(5)).trimmingCharacters(in: .whitespaces) }
            ?? "\(ProxyServer.lanAddress() ?? "127.0.0.1"):\(SaimoConnect.porta)"

        guard let res = try? Upstream.shared.fetch(url, referer: referer, agente: agente),
              (200...299).contains(res.status) else {
            return (502, "text/plain", "origem")
        }
        let corpo = String(decoding: res.body, as: UTF8.self)
        guard corpo.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#EXTM3U") else {
            return (502, "text/plain", "origem")
        }
        let base = res.finalURL
        let absoluto: (String) -> String = { u in
            URL(string: u.trimmingCharacters(in: .whitespaces), relativeTo: base)?.absoluteURL.absoluteString ?? u
        }
        let baseDosTrechos = ProxyServer.shared.baseDosSegmentos(base)
        let trecho: (String) -> String = { u in
            URL(string: u.trimmingCharacters(in: .whitespaces), relativeTo: baseDosTrechos)?.absoluteURL.absoluteString ?? u
        }
        let peloProxy: (String) -> String = { u in
            var s = "http://\(host)/hls?u=\(codificar(absoluto(u)))"
            if let referer { s += "&r=\(codificar(referer))" }
            if let agente { s += "&ua=\(codificar(agente))" }
            return s
        }

        let linhas = linhasDe(corpo)
        guard linhas.contains(where: { $0.hasPrefix("#EXT-X-STREAM-INF") }) else {
            return (200, "application/vnd.apple.mpegurl",
                    listaDeMidia(corpo, url: url, absoluto: absoluto, trecho: trecho))
        }
        var saida = ""
        var proximaEhVariante = false
        for l in linhas {
            if l.hasPrefix("#EXT-X-STREAM-INF") {
                saida += l + "\n"
                proximaEhVariante = true
            } else if l.hasPrefix("#EXT-X-MEDIA") || l.hasPrefix("#EXT-X-I-FRAME-STREAM-INF") {
                saida += Historico.uriAbsoluta(l, peloProxy) + "\n"
            } else if !l.isEmpty, !l.hasPrefix("#"), proximaEhVariante {
                saida += peloProxy(l) + "\n"
                proximaEhVariante = false
            } else {
                saida += l + "\n"
            }
        }
        return (200, "application/vnd.apple.mpegurl", saida)
    }

    private static func codificar(_ s: String) -> String {
        var permitidos = CharacterSet.alphanumerics
        permitidos.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: permitidos) ?? s
    }
}
