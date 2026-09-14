import Foundation
import AppKit

/// O que o Saimo Monitor fica sabendo deste Mac.
///
/// Que o app abriu (versão, modelo, sistema), o que está tocando de tempos em
/// tempos, e quando uma fonte falha, um canal cai ou o app quebrou na última
/// vez. O aparelho é um UUID sorteado aqui na primeira abertura; nada de nome,
/// conta ou número de série, e o IP não é guardado — a cidade sai da borda.
///
/// Tudo é fogo e esquece: sem rede, o monitor fica sem o dado e o player segue
/// igual.
@MainActor
final class Telemetria {
    static let shared = Telemetria()

    enum Tipo: String { case live, vod }

    private let base = URL(string: "https://saimo-monitor.gabrielsaimo68.workers.dev/v1")!
    private let plataforma = "mac"
    /// Zapeando, cada canal que passa não vira batida: só quem ficou.
    private let minimoParaContar: TimeInterval = 20

    private struct Tocando { let tipo: Tipo; let titulo: String; let host: String? }

    private var tocando: Tocando?
    private var contandoDesde = Date()
    private var batida: Timer?
    private var intervalo: TimeInterval = 300
    private var iniciado = false

    private lazy var id: String = {
        let chave = "telemetria.id"
        if let salvo = UserDefaults.standard.string(forKey: chave) { return salvo }
        let novo = UUID().uuidString.lowercased()
        UserDefaults.standard.set(novo, forKey: chave)
        return novo
    }()

    private var versao: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    func iniciar() {
        guard !iniciado else { return }
        iniciado = true
        enviar("hello", [
            "version": versao,
            "model": Self.modelo(),
            "os": "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
        ]) { [weak self] corpo in
            if let s = corpo?["heartbeatSeconds"] as? Double, (60...3600).contains(s) {
                self?.intervalo = s
                self?.agendar()
            }
        }
        enviarCrashesAnteriores()
        agendar()
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.encerrar() }
            }
    }

    private func agendar() {
        batida?.invalidate()
        batida = Timer.scheduledTimer(withTimeInterval: intervalo, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.baterAgora() }
        }
    }

    private func encerrar() {
        batida?.invalidate()
        baterAgora(esperar: true)
        if tocando != nil { evento("play_stop", esperar: true) }
    }

    private func baterAgora(esperar: Bool = false) {
        let agora = Date()
        let segundos = tocando == nil ? 0 : Int(agora.timeIntervalSince(contandoDesde))
        contandoDesde = agora
        var corpo: [String: Any] = ["version": versao, "seconds": segundos]
        if let t = tocando {
            corpo["playing"] = ["kind": t.tipo.rawValue, "title": t.titulo, "host": t.host ?? ""]
        } else {
            corpo["playing"] = NSNull()
        }
        enviar("beat", corpo, esperar: esperar)
    }

    /// `nova` é falso quando é só a próxima fonte do mesmo título depois de uma falha.
    func comecou(_ tipo: Tipo, _ titulo: String, url: URL?, fonte: Int, nova: Bool = true) {
        // O último canal é retomado antes de o App terminar o init; sem isto a
        // primeira abertura de cada sessão se perdia.
        iniciar()
        let agora = Date()
        if let anterior = tocando, anterior.titulo != titulo,
           agora.timeIntervalSince(contandoDesde) >= minimoParaContar {
            baterAgora()
        }
        if tocando?.titulo != titulo { contandoDesde = agora }
        tocando = Tocando(tipo: tipo, titulo: titulo, host: Self.host(url))
        if nova { evento("play_start", tipo: tipo, titulo: titulo, url: url, fonte: fonte) }
    }

    func tocou(_ tipo: Tipo, _ titulo: String, url: URL?, fonte: Int, ms: Int) {
        evento("play_ok", tipo: tipo, titulo: titulo, url: url, fonte: fonte, detalhe: "\(ms) ms")
    }

    func falhou(_ tipo: Tipo, _ titulo: String, url: URL?, fonte: Int, detalhe: String) {
        evento("source_fail", tipo: tipo, titulo: titulo, url: url, fonte: fonte, detalhe: detalhe)
    }

    func caiu(_ tipo: Tipo, _ titulo: String, fontes: Int) {
        evento("channel_down", tipo: tipo, titulo: titulo, detalhe: "nenhuma das \(fontes) fonte(s) abriu")
    }

    func parou() {
        guard tocando != nil else { return }
        if Date().timeIntervalSince(contandoDesde) >= minimoParaContar { baterAgora() }
        tocando = nil
        evento("play_stop")
    }

    private func evento(_ tipo: String, tipo kind: Tipo? = nil, titulo: String? = nil, url: URL? = nil,
                        fonte: Int? = nil, detalhe: String? = nil, esperar: Bool = false) {
        iniciar()
        var corpo: [String: Any] = ["type": tipo, "version": versao]
        if let kind { corpo["kind"] = kind.rawValue }
        if let titulo { corpo["title"] = titulo }
        if let h = Self.host(url) { corpo["host"] = h }
        if let fonte { corpo["source"] = fonte }
        if let detalhe { corpo["detail"] = detalhe }
        enviar("event", corpo, esperar: esperar)
    }

    /// O relatório que o próprio macOS escreve quando o app quebra, lido na
    /// abertura seguinte. Um app que fecha sozinho não tem chance de avisar na
    /// hora; o sistema guarda por ele.
    private func enviarCrashesAnteriores() {
        let chave = "telemetria.crashVisto"
        let visto = UserDefaults.standard.double(forKey: chave)
        let pasta = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DiagnosticReports")
        guard let arquivos = try? FileManager.default.contentsOfDirectory(
            at: pasta, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        var maisNovo = visto
        for arquivo in arquivos where arquivo.lastPathComponent.hasPrefix("SaimoTV") {
            let data = (try? arquivo.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate?.timeIntervalSince1970 ?? 0
            guard data > visto else { continue }
            maisNovo = max(maisNovo, data)
            // Na primeira abertura com telemetria não manda o histórico todo.
            guard visto > 0, let texto = try? String(contentsOf: arquivo, encoding: .utf8) else { continue }
            evento("crash", detalhe: "\(arquivo.lastPathComponent)\n" + String(texto.prefix(2800)))
        }
        UserDefaults.standard.set(max(maisNovo, Date().timeIntervalSince1970), forKey: chave)
    }

    private func enviar(_ rota: String, _ corpo: [String: Any], esperar: Bool = false,
                        resposta: ((([String: Any])?) -> Void)? = nil) {
        var corpo = corpo
        corpo["deviceId"] = id
        corpo["platform"] = plataforma
        guard let dados = try? JSONSerialization.data(withJSONObject: corpo) else { return }
        var pedido = URLRequest(url: base.appendingPathComponent(rota))
        pedido.httpMethod = "POST"
        pedido.httpBody = dados
        pedido.setValue("application/json", forHTTPHeaderField: "content-type")
        pedido.timeoutInterval = esperar ? 3 : 15
        let sinal = esperar ? DispatchSemaphore(value: 0) : nil
        URLSession.shared.dataTask(with: pedido) { data, resp, _ in
            defer { sinal?.signal() }
            guard let resposta else { return }
            let ok = ((resp as? HTTPURLResponse)?.statusCode ?? 0) / 100 == 2
            let lido = ok ? data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } : nil
            Task { @MainActor in resposta(lido) }
        }.resume()
        // Só ao fechar o app: dá um instante para a última batida sair.
        _ = sinal?.wait(timeout: .now() + 2)
    }

    private static func host(_ url: URL?) -> String? {
        guard let h = url?.host, !h.isEmpty, h != "127.0.0.1", h != "localhost" else { return nil }
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }

    private static func modelo() -> String {
        var tamanho = 0
        sysctlbyname("hw.model", nil, &tamanho, nil, 0)
        var bytes = [CChar](repeating: 0, count: max(tamanho, 1))
        sysctlbyname("hw.model", &bytes, &tamanho, nil, 0)
        return String(cString: bytes)
    }
}
