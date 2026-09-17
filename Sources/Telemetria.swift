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
    /// Só conta tempo com o vídeo andando: pausado ou carregando não é
    /// assistir. `acumulado` é o que já andou desde a última batida.
    private var acumulado: TimeInterval = 0
    private var rodandoDesde: Date?
    private var pausado = false
    private var qualidade: String?
    private var travouDesde: Date?
    private var buscas: [String: (texto: String, espera: DispatchWorkItem?, achou: () -> Bool)] = [:]
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
            "os": "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "screen": Self.tela(),
            "lang": Locale.preferredLanguages.first ?? ""
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
        let segundos = tocando == nil ? 0 : Int(rodando)
        acumulado = 0
        if rodandoDesde != nil { rodandoDesde = Date() }
        var corpo: [String: Any] = ["version": versao, "seconds": segundos]
        if let t = tocando {
            var playing: [String: Any] = ["kind": t.tipo.rawValue, "title": t.titulo, "host": t.host ?? "", "paused": pausado]
            if let qualidade { playing["quality"] = qualidade }
            corpo["playing"] = playing
        } else {
            corpo["playing"] = NSNull()
        }
        enviar("beat", corpo, esperar: esperar)
    }

    private var rodando: TimeInterval {
        acumulado + (rodandoDesde.map { Date().timeIntervalSince($0) } ?? 0)
    }

    /// O que o player está fazendo agora, a cada segundo e a cada pausa.
    ///
    /// `rodando` é o vídeo já confirmado na tela; `carregando` é o player
    /// esperando dados. Pausar ou voltar bate na hora, para o painel não mostrar
    /// como assistindo quem pausou. Carregar depois de ter começado é
    /// travamento — menos logo depois de pular para outro ponto do filme.
    func video(rodando: Bool, pausado: Bool, carregando: Bool, pulou: Bool, qualidade: String?) {
        guard let t = tocando else { return }
        let andando = rodando && !pausado && !carregando
        if andando, rodandoDesde == nil { rodandoDesde = Date() }
        if !andando, let desde = rodandoDesde {
            acumulado += Date().timeIntervalSince(desde)
            rodandoDesde = nil
        }
        if rodando, let qualidade { self.qualidade = qualidade }
        if pulou {
            travouDesde = nil
        } else if rodando && carregando && !pausado {
            if travouDesde == nil { travouDesde = Date() }
        } else if let desde = travouDesde {
            travouDesde = nil
            let ms = Int(Date().timeIntervalSince(desde) * 1000)
            if ms >= 500 && !pausado {
                iniciar()
                var corpo: [String: Any] = ["type": "stall", "version": versao, "kind": t.tipo.rawValue,
                                            "title": t.titulo, "ms": ms, "detail": "\(ms) ms"]
                if let h = t.host { corpo["host"] = h }
                enviar("event", corpo)
            }
        }
        if rodando, pausado != self.pausado {
            self.pausado = pausado
            baterAgora()
        }
    }

    /// Busca que ficou parada 2 s sem resultado: o painel mostra o que
    /// procuram e não acham. `achou` é lido só na hora de decidir.
    func buscou(_ tipo: Tipo, _ texto: String, achou: @escaping () -> Bool) {
        let texto = texto.trimmingCharacters(in: .whitespaces)
        // Mesmo texto: só guarda a resposta mais nova (a lista pode ter chegado).
        if buscas[tipo.rawValue]?.texto == texto {
            buscas[tipo.rawValue]?.achou = achou
            return
        }
        buscas[tipo.rawValue]?.espera?.cancel()
        guard texto.count >= 3 else { buscas[tipo.rawValue] = (texto, nil, achou); return }
        let espera = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let busca = self.buscas[tipo.rawValue], busca.texto == texto,
                      !busca.achou() else { return }
                self.iniciar()
                self.enviar("event", ["type": "search_miss", "version": self.versao,
                                      "kind": tipo.rawValue, "query": texto])
            }
        }
        buscas[tipo.rawValue] = (texto, espera, achou)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: espera)
    }

    /// `nova` é falso quando é só a próxima fonte do mesmo título depois de uma falha.
    func comecou(_ tipo: Tipo, _ titulo: String, url: URL?, fonte: Int, nova: Bool = true) {
        // O último canal é retomado antes de o App terminar o init; sem isto a
        // primeira abertura de cada sessão se perdia.
        iniciar()
        if let anterior = tocando, anterior.titulo != titulo, rodando >= minimoParaContar {
            baterAgora()
        }
        if tocando?.titulo != titulo {
            acumulado = 0
            rodandoDesde = nil
            pausado = false
            qualidade = nil
        }
        travouDesde = nil
        tocando = Tocando(tipo: tipo, titulo: titulo, host: Self.host(url))
        if nova { evento("play_start", tipo: tipo, titulo: titulo, url: url, fonte: fonte) }
    }

    func tocou(_ tipo: Tipo, _ titulo: String, url: URL?, fonte: Int, ms: Int) {
        evento("play_ok", tipo: tipo, titulo: titulo, url: url, fonte: fonte, detalhe: "\(ms) ms", ms: ms)
    }

    func falhou(_ tipo: Tipo, _ titulo: String, url: URL?, fonte: Int, detalhe: String) {
        evento("source_fail", tipo: tipo, titulo: titulo, url: url, fonte: fonte, detalhe: detalhe)
    }

    func caiu(_ tipo: Tipo, _ titulo: String, fontes: Int) {
        evento("channel_down", tipo: tipo, titulo: titulo, detalhe: "nenhuma das \(fontes) fonte(s) abriu")
    }

    func parou() {
        guard tocando != nil else { return }
        if rodando >= minimoParaContar { baterAgora() }
        tocando = nil
        acumulado = 0
        rodandoDesde = nil
        pausado = false
        qualidade = nil
        travouDesde = nil
        evento("play_stop")
    }

    private func evento(_ tipo: String, tipo kind: Tipo? = nil, titulo: String? = nil, url: URL? = nil,
                        fonte: Int? = nil, detalhe: String? = nil, ms: Int? = nil, esperar: Bool = false) {
        iniciar()
        var corpo: [String: Any] = ["type": tipo, "version": versao]
        if let kind { corpo["kind"] = kind.rawValue }
        if let titulo { corpo["title"] = titulo }
        if let h = Self.host(url) { corpo["host"] = h }
        if let fonte { corpo["source"] = fonte }
        if let detalhe { corpo["detail"] = detalhe }
        if let ms { corpo["ms"] = ms }
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

    private static func tela() -> String {
        guard let s = NSScreen.main else { return "" }
        let px = s.convertRectToBacking(s.frame).size
        return "\(Int(px.width))x\(Int(px.height))"
    }

    private static func modelo() -> String {
        var tamanho = 0
        sysctlbyname("hw.model", nil, &tamanho, nil, 0)
        var bytes = [CChar](repeating: 0, count: max(tamanho, 1))
        sysctlbyname("hw.model", &bytes, &tamanho, nil, 0)
        return String(cString: bytes)
    }
}
