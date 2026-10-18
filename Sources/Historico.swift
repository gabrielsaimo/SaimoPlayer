import Foundation

/// A lista ao vivo numa régua de tempo contínua, a mesma para o player do Mac
/// e para o celular do Saimo Connect.
///
/// Porte do `Historico.kt` da TV Box. Dois problemas que só a lista crua tinha:
///
/// - Muitos canais guardam só os últimos 10 a 15 s na lista, e o Mac costuma
///   tocar mais atrás que isso. O trecho que o Mac mostra já saiu da lista
///   quando o celular pede: ele nunca chegava lá e o som sumia. Aqui ficam os
///   trechos dos últimos `guardaMs`, e a lista devolvida tem todos eles.
/// - Sem marca de horário no canal (EXT-X-PROGRAM-DATE-TIME) não havia régua
///   comum. Aqui cada trecho ganha uma marca sintética: começa onde o anterior
///   terminou, pela duração real (EXTINF), a partir de uma âncora no relógio do
///   Mac tirada na primeira vez que o trecho apareceu.
///
/// Diferente da TV Box, o player do próprio Mac também recebe esta lista (pelo
/// `ProxyServer`): a data que o AVPlayer informa (`currentDate()`) já é o
/// instante na régua, sem conversão nenhuma. O celular lê a mesma régua das
/// marcas que vão na lista dele (`ConnectHls`). Os dois medem a mesma coisa.
///
/// Usado das threads do proxy e do Saimo Connect: o estado mora atrás de
/// `lock`, daí o `@unchecked Sendable`.
final class Historico: @unchecked Sendable {
    static let shared = Historico()

    private static let guardaMs: Int64 = 120_000
    private static let esqueceMs: Int64 = 10 * 60_000
    /// Origem da hora sintética antiga (lista que não dá para estender).
    /// Qualquer valor serve, desde que seja o mesmo em toda parte.
    static let t0: Int64 = 1_600_000_000_000

    private final class Trecho {
        let seq: Int64
        let duracaoMs: Int64
        /// EXTINF, outras marcas do trecho e o endereço absoluto.
        let corpo: [String]
        let chave: String?
        let mapa: String?
        let descontinuidade: Bool
        /// Número de descontinuidade do trecho.
        let sequenciaDesc: Int64
        let marcaPropria: String?
        let inicioMs: Int64

        init(seq: Int64, duracaoMs: Int64, corpo: [String], chave: String?, mapa: String?,
             descontinuidade: Bool, sequenciaDesc: Int64, marcaPropria: String?, inicioMs: Int64) {
            self.seq = seq
            self.duracaoMs = duracaoMs
            self.corpo = corpo
            self.chave = chave
            self.mapa = mapa
            self.descontinuidade = descontinuidade
            self.sequenciaDesc = sequenciaDesc
            self.marcaPropria = marcaPropria
            self.inicioMs = inicioMs
        }
    }

    private final class Regua {
        var trechos: [Int64: Trecho] = [:]
        var vistaEm: Int64 = 0
        var cabecalho: [String] = []
        var alvoS = 6
        var marcaReal = false

        var ordenados: [Trecho] { trechos.keys.sorted().compactMap { trechos[$0] } }
    }

    private var reguas: [String: Regua] = [:]
    private let lock = NSLock()

    private init() {}

    /// Marcas que descrevem a lista inteira, não um trecho.
    private static let marcasDaLista = [
        "#EXTM3U", "#EXT-X-VERSION", "#EXT-X-TARGETDURATION", "#EXT-X-MEDIA-SEQUENCE",
        "#EXT-X-DISCONTINUITY-SEQUENCE", "#EXT-X-PLAYLIST-TYPE", "#EXT-X-INDEPENDENT-SEGMENTS",
        "#EXT-X-START", "#EXT-X-ALLOW-CACHE", "#EXT-X-SERVER-CONTROL",
    ]

    static func agoraMs() -> Int64 { Int64((Date().timeIntervalSince1970 * 1000).rounded()) }

    /// A marca de horário no formato da norma, em UTC e com milissegundos.
    static func marca(_ ms: Int64) -> String {
        Date(timeIntervalSince1970: Double(ms) / 1000)
            .formatted(.iso8601.year().month().day().dateSeparator(.dash)
                .time(includingFractionalSeconds: true).timeSeparator(.colon)
                .timeZone(separator: .omitted))
    }

    /// A chave da régua: o endereço sem a consulta, que costuma trocar de token.
    private static func chaveDe(_ url: URL) -> String {
        guard let esquema = url.scheme, let host = url.host else { return url.absoluteString }
        return "\(esquema)://\(host)\(url.path)"
    }

    /// Troca o `URI="..."` de uma marca pelo endereço absoluto.
    static func uriAbsoluta(_ linha: String, _ absoluto: (String) -> String) -> String {
        guard let abre = linha.range(of: "URI=\""),
              let fecha = linha[abre.upperBound...].firstIndex(of: "\"") else { return linha }
        let valor = String(linha[abre.upperBound..<fecha])
        return linha.replacingCharacters(in: abre.upperBound..<fecha, with: absoluto(valor))
    }

    private static func depoisDosDoisPontos(_ linha: String) -> String {
        guard let i = linha.firstIndex(of: ":") else { return "" }
        return linha[linha.index(after: i)...].trimmingCharacters(in: .whitespaces)
    }

    /// A lista estendida e com a régua escrita, ou nulo quando ela não é uma
    /// lista ao vivo simples (filme, LL-HLS com partes, BYTERANGE) e vale a
    /// regra antiga (ver `ConnectHls.listaDeMidia`).
    ///
    /// - Parameters:
    ///   - url: o endereço pedido; o caminho dele é a chave da régua.
    ///   - absoluto: resolve o `URI=` das marcas (chave, mapa).
    ///   - trecho: resolve o endereço de cada pedaço.
    func estender(url: URL, linhas: [String], absoluto: (String) -> String,
                  trecho: (String) -> String) -> String? {
        if linhas.contains(where: {
            $0.hasPrefix("#EXT-X-ENDLIST") || $0.hasPrefix("#EXT-X-PART") ||
            $0.hasPrefix("#EXT-X-PRELOAD-HINT") || $0.hasPrefix("#EXT-X-BYTERANGE")
        }) { return nil }
        if linhas.contains(where: { $0.hasPrefix("#EXT-X-PLAYLIST-TYPE:VOD") }) { return nil }

        struct Lido {
            let dur: Int64
            let corpo: [String]
            let chave: String?
            let mapa: String?
            let desc: Bool
            let marca: String?
        }
        var cabecalho: [String] = []
        var sequencia: Int64 = 0
        var sequenciaDesc: Int64 = 0
        var alvoS = 6
        var lidos: [Lido] = []
        var chave: String?
        var mapa: String?
        var desc = false
        var marca: String?
        var corpo: [String] = []
        var dur: Int64 = 0
        var algumTrecho = false

        for l in linhas {
            if l.isEmpty { continue }
            if l.hasPrefix("#EXT-X-MEDIA-SEQUENCE:") {
                sequencia = Int64(Self.depoisDosDoisPontos(l)) ?? 0
            } else if l.hasPrefix("#EXT-X-DISCONTINUITY-SEQUENCE:") {
                sequenciaDesc = Int64(Self.depoisDosDoisPontos(l)) ?? 0
            } else if l.hasPrefix("#EXT-X-TARGETDURATION:") {
                alvoS = Double(Self.depoisDosDoisPontos(l)).map { Int($0.rounded(.up)) } ?? 6
            } else if Self.marcasDaLista.contains(where: { l.hasPrefix($0) }) {
                if !l.hasPrefix("#EXTM3U") { cabecalho.append(l) }
            } else if l.hasPrefix("#EXT-X-KEY") {
                chave = Self.uriAbsoluta(l, absoluto)
            } else if l.hasPrefix("#EXT-X-MAP") {
                mapa = Self.uriAbsoluta(l, absoluto)
            } else if l.hasPrefix("#EXT-X-DISCONTINUITY") {
                desc = true
            } else if l.hasPrefix("#EXT-X-PROGRAM-DATE-TIME") {
                marca = l
            } else if l.hasPrefix("#EXTINF") {
                let valor = Self.depoisDosDoisPontos(l).split(separator: ",", maxSplits: 1,
                                                              omittingEmptySubsequences: false).first ?? ""
                dur = Int64(((Double(valor.trimmingCharacters(in: .whitespaces)) ?? 0) * 1000))
                corpo.append(l)
            } else if l.hasPrefix("#") {
                if algumTrecho || !corpo.isEmpty { corpo.append(l) } else { cabecalho.append(l) }
            } else {
                corpo.append(trecho(l))
                lidos.append(Lido(dur: max(dur, 1), corpo: corpo, chave: chave, mapa: mapa,
                                  desc: desc, marca: marca))
                corpo = []; desc = false; marca = nil; dur = 0
                algumTrecho = true
            }
        }
        if lidos.isEmpty { return nil }

        let agora = Self.agoraMs()
        lock.lock(); defer { lock.unlock() }
        let chaveDaRegua = Self.chaveDe(url)
        let regua: Regua
        if let existente = reguas[chaveDaRegua] { regua = existente } else {
            regua = Regua()
            reguas[chaveDaRegua] = regua
        }
        regua.vistaEm = agora
        regua.cabecalho = cabecalho
        regua.alvoS = alvoS
        regua.marcaReal = lidos.contains { $0.marca != nil }

        var d = sequenciaDesc
        var restante = lidos.reduce(Int64(0)) { $0 + $1.dur }
        for (i, lido) in lidos.enumerated() {
            let seq = sequencia + Int64(i)
            if lido.desc { d += 1 }
            if regua.trechos[seq] == nil {
                // Sem o anterior (primeira vez, ou um buraco depois de muito
                // tempo parado): a âncora de outra lista que já tem este
                // trecho (o celular, outra qualidade do mesmo canal), para
                // todas contarem igual; senão o relógio, com o fim da lista agora.
                let inicio: Int64
                if let anterior = regua.trechos[seq - 1] {
                    inicio = anterior.inicioMs + anterior.duracaoMs
                } else if let deOutra = reguas.values.first(where: {
                    $0 !== regua && agora - $0.vistaEm < 60_000 && $0.trechos[seq] != nil
                })?.trechos[seq]?.inicioMs {
                    inicio = deOutra
                } else {
                    inicio = agora - restante
                }
                regua.trechos[seq] = Trecho(seq: seq, duracaoMs: lido.dur, corpo: lido.corpo,
                                            chave: lido.chave, mapa: lido.mapa,
                                            descontinuidade: lido.desc, sequenciaDesc: d,
                                            marcaPropria: lido.marca, inicioMs: inicio)
            }
            restante -= lido.dur
        }
        if let ultimaSeq = regua.trechos.keys.max(), let ultimo = regua.trechos[ultimaSeq] {
            let corte = ultimo.inicioMs + ultimo.duracaoMs - Self.guardaMs
            while regua.trechos.count > lidos.count,
                  let primeiraSeq = regua.trechos.keys.min(),
                  let primeiro = regua.trechos[primeiraSeq], primeiro.inicioMs < corte {
                regua.trechos.removeValue(forKey: primeiraSeq)
            }
        }
        reguas = reguas.filter { agora - $0.value.vistaEm <= Self.esqueceMs }
        return escreverLista(regua)
    }

    private func escreverLista(_ regua: Regua) -> String {
        let trechos = regua.ordenados
        guard let primeiro = trechos.first else { return "#EXTM3U\n" }
        let maior = trechos.map(\.duracaoMs).max() ?? 0
        let alvo = max(regua.alvoS, Int((Double(maior) / 1000).rounded(.up)))
        var sb = "#EXTM3U\n"
        for l in regua.cabecalho where !l.hasPrefix("#EXT-X-TARGETDURATION") { sb += l + "\n" }
        sb += "#EXT-X-TARGETDURATION:\(alvo)\n"
        sb += "#EXT-X-MEDIA-SEQUENCE:\(primeiro.seq)\n"
        sb += "#EXT-X-DISCONTINUITY-SEQUENCE:\(primeiro.sequenciaDesc - (primeiro.descontinuidade ? 1 : 0))\n"
        var chave: String?
        var mapa: String?
        for t in trechos {
            if t.descontinuidade { sb += "#EXT-X-DISCONTINUITY\n" }
            if let c = t.chave, c != chave { sb += c + "\n"; chave = c }
            if let m = t.mapa, m != mapa { sb += m + "\n"; mapa = m }
            if regua.marcaReal {
                if let propria = t.marcaPropria { sb += propria + "\n" }
            } else {
                sb += "#EXT-X-PROGRAM-DATE-TIME:\(Self.marca(t.inicioMs))\n"
            }
            for l in t.corpo { sb += l + "\n" }
        }
        return sb
    }
}
