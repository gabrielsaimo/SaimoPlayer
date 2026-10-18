import Foundation
import AppKit
import AVFoundation
import Combine
import CryptoKit
import dnssd

/// Saimo Connect no Mac: o celular controla o app e ouve o som dele no fone.
///
/// O mesmo protocolo da TV Box (`Connect.kt`), na porta 8999:
/// 1. `GET /info` — descoberta pela rede local (o celular varre a sub-rede);
/// 2. `GET /hls` — a lista do canal na régua do Mac (`ConnectHls`);
/// 3. `GET /ws` — WebSocket com o controle remoto, o estado do que está no ar
///    e a posição de cada tela para o som no celular tocar junto;
/// 4. anúncio Bonjour `_saimotv._tcp`.
///
/// Celular novo só entra depois de alguém permitir na tela do Mac; aprovado
/// uma vez, fica lembrado até "Esquecer todos os celulares" nos Ajustes.
///
/// A rede roda nas threads do `ServidorConnect`; tudo que toca o app (estado,
/// comandos, aprovação) passa por aqui, na principal.
@MainActor
final class SaimoConnect: ObservableObject {
    static let shared = SaimoConnect()
    nonisolated static let porta: UInt16 = 8999

    private static let chaveId = "connect.tvId"
    private static let chaveConfiaveis = "connect.celularesConfiaveis"

    /// Celulares aprovados (lembrados).
    @Published private(set) var autorizados = 0
    /// Nomes dos celulares conectados agora.
    @Published private(set) var conectados: [String] = []
    @Published private(set) var ativo = false

    let tvId: String
    let nome: String

    private var confiaveis: Set<String>
    private let servidor = ServidorConnect()
    private var anuncio: DNSServiceRef?

    /// O som de cada celular: de qual tela ("0", "1", "both") ou "none".
    private var somNoCelular: [String: (nome: String, src: String)] = [:]

    private var aprovando: (cliente: ClienteConnect, alerta: NSAlert)?
    private var filaDeAprovacao: [ClienteConnect] = []

    private var ultimaAssinatura = ""
    private var ultimoEnvio = Date.distantPast
    private var observadores: Set<AnyCancellable> = []
    private var relogio: Timer?
    private var editandoTexto = false

    /// Número de canal digitado no controle do celular.
    private var numero = ""
    private var geracaoDoNumero = 0

    private var model: PlayerModel { PlayerModel.shared }

    private init() {
        let defaults = UserDefaults.standard
        if let salvo = defaults.string(forKey: Self.chaveId), !salvo.isEmpty {
            tvId = salvo
        } else {
            tvId = UUID().uuidString.lowercased()
            defaults.set(tvId, forKey: Self.chaveId)
        }
        confiaveis = Set(defaults.stringArray(forKey: Self.chaveConfiaveis) ?? [])
        nome = "Saimo TV - Mac (\(Host.current().localizedName ?? "Mac"))"
        autorizados = confiaveis.count
    }

    // MARK: - Ciclo de vida

    func iniciar() {
        guard !ativo else { return }
        let versao = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        guard servidor.iniciar(Identidade(id: tvId, nome: nome, versao: versao)) else {
            Log.shared.write("Saimo Connect: não consegui abrir a porta \(Self.porta)")
            return
        }
        ativo = true
        Log.shared.write("Saimo Connect em \(ProxyServer.lanAddress() ?? "127.0.0.1"):\(Self.porta)")
        anunciar()

        // Qualquer mudança no que está no ar vira um estado novo para os
        // celulares, juntando as que chegam em rajada.
        let model = self.model
        model.objectWillChange
            .merge(with: model.segunda.objectWillChange)
            .merge(with: VodEstado.shared.objectWillChange)
            .merge(with: Radios.shared.objectWillChange)
            .merge(with: Interface.shared.objectWillChange)
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.avisarEstado() } }
            .store(in: &observadores)

        relogio = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tique() }
        }
        RunLoop.main.add(relogio!, forMode: .common)
    }

    private func anunciar() {
        var ref: DNSServiceRef?
        let erro = DNSServiceRegister(&ref, 0, 0, nome, "_saimotv._tcp", nil, nil,
                                      Self.porta.bigEndian, 0, nil, nil, nil)
        if erro == kDNSServiceErr_NoError {
            anuncio = ref
        } else {
            Log.shared.write("Saimo Connect: anúncio Bonjour falhou (\(erro))")
        }
    }

    /// A cada segundo: a posição das telas para quem ouve no celular, o
    /// campo de texto que abriu ou fechou, e o estado (o que não avisa
    /// sozinho, como a fonte que o proxy trocou).
    private func tique() {
        let clientes = servidor.autenticados()
        guard !clientes.isEmpty else { return }
        if temSomNoCelular {
            let telas = instantes()
            if !telas.isEmpty {
                enviar(["t": "pos", "wall": Historico.agoraMs(), "screens": telas], para: clientes)
            }
        }
        vigiarTexto(clientes)
        avisarEstado()
    }

    private var temSomNoCelular: Bool {
        somNoCelular.values.contains { ["0", "1", "both"].contains($0.src) }
    }

    // MARK: - Celulares

    /// Esquece todos os celulares autorizados e desconecta os que estão ligados.
    func esquecerTodos() {
        confiaveis.removeAll()
        UserDefaults.standard.removeObject(forKey: Self.chaveConfiaveis)
        autorizados = 0
        for c in servidor.todos() { c.fechar() }
        Log.shared.write("Saimo Connect: celulares esquecidos")
    }

    private func confiar(_ cid: String) {
        confiaveis.insert(cid)
        UserDefaults.standard.set(Array(confiaveis).sorted(), forKey: Self.chaveConfiaveis)
        autorizados = confiaveis.count
    }

    /// Mensagem de um celular (menos o ping, respondido na thread dele).
    func recebeu(_ texto: String, de cliente: ClienteConnect) {
        guard let dados = texto.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: dados)) as? [String: Any],
              let tipo = json["t"] as? String else { return }
        if tipo == "hello" {
            ola(cliente, json)
            return
        }
        guard cliente.autenticado else { return }
        executar(tipo, json, de: cliente)
    }

    private func ola(_ cliente: ClienteConnect, _ json: [String: Any]) {
        guard let cid = json["cid"] as? String, !cid.isEmpty else { return }
        let nomeRecebido = ((json["name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let nome = nomeRecebido.isEmpty ? "Celular" : String(nomeRecebido.prefix(40))
        cliente.identificar(cid: cid, nome: nome)
        if confiaveis.contains(cid) {
            boasVindas(cliente)
            return
        }
        // Primeira vez deste celular: o Mac pergunta. Ninguém entra sem
        // alguém ver e permitir na tela.
        enviar(["t": "pending"], para: [cliente])
        filaDeAprovacao.append(cliente)
        perguntarProximo()
    }

    private func perguntarProximo() {
        guard aprovando == nil else { return }
        filaDeAprovacao.removeAll { $0.fechado }
        guard !filaDeAprovacao.isEmpty else { return }
        let cliente = filaDeAprovacao.removeFirst()

        let alerta = NSAlert()
        alerta.messageText = "Saimo Connect"
        alerta.informativeText = "\(cliente.nome) quer se conectar a este Mac.\nDeseja permitir?"
        alerta.icon = NSImage(systemSymbolName: "iphone.radiowaves.left.and.right",
                              accessibilityDescription: nil)
        alerta.addButton(withTitle: "Permitir")
        alerta.addButton(withTitle: "Recusar")
        aprovando = (cliente, alerta)
        NSApp.requestUserAttention(.criticalRequest)

        let responder: (NSApplication.ModalResponse) -> Void = { [weak self] resposta in
            MainActor.assumeIsolated {
                self?.respondeu(cliente, permitido: resposta == .alertFirstButtonReturn)
            }
        }
        if let janela = NSApp.windows.first(where: {
            $0.isVisible && $0.styleMask.contains(.titled) && !($0 is NSPanel) && $0.attachedSheet == nil
        }) {
            alerta.beginSheetModal(for: janela, completionHandler: responder)
        } else {
            responder(alerta.runModal())
        }
    }

    private func respondeu(_ cliente: ClienteConnect, permitido: Bool) {
        aprovando = nil
        defer { perguntarProximo() }
        guard !cliente.fechado, let cid = cliente.cid else { return }
        if permitido {
            confiar(cid)
            boasVindas(cliente)
        } else {
            Log.shared.write("Saimo Connect: \(cliente.nome) recusado")
            enviar(["t": "denied"], para: [cliente])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { cliente.fechar() }
        }
    }

    private func boasVindas(_ cliente: ClienteConnect) {
        cliente.autenticar()
        enviar(["t": "welcome", "tv": ["id": tvId, "name": nome]], para: [cliente])
        Log.shared.write("Saimo Connect: \(cliente.nome) conectado")
        atualizarConectados()
        avisarEstado(forcado: true)
    }

    /// Um celular saiu (fechou o app, perdeu a rede, foi esquecido).
    func desconectou(_ cliente: ClienteConnect) {
        if let (pendente, alerta) = aprovando, pendente === cliente {
            if let janela = alerta.window.sheetParent {
                janela.endSheet(alerta.window, returnCode: .alertSecondButtonReturn)
            } else {
                NSApp.abortModal()
            }
        }
        filaDeAprovacao.removeAll { $0 === cliente }
        if let cid = cliente.cid, somNoCelular.removeValue(forKey: cid) != nil {
            somDoCelularMudou()
        }
        atualizarConectados()
        avisarEstado(forcado: true)
    }

    private func atualizarConectados() {
        let nomes = servidor.autenticados().map(\.nome)
        if nomes != conectados { conectados = nomes }
    }

    // MARK: - Envio

    private func enviar(_ mensagem: [String: Any], para clientes: [ClienteConnect]) {
        guard let dados = try? JSONSerialization.data(withJSONObject: mensagem),
              let texto = String(data: dados, encoding: .utf8) else { return }
        for c in clientes { c.enviar(texto) }
    }

    /// Manda o estado para os celulares quando ele mudou. Num filme a posição
    /// muda a cada segundo: ela sozinha só vai de cinco em cinco.
    func avisarEstado(forcado: Bool = false) {
        let clientes = servidor.autenticados()
        guard !clientes.isEmpty else { return }
        var e = estado()
        var semPosicao = e
        if var vod = semPosicao["vod"] as? [String: Any] {
            vod["pos"] = 0
            semPosicao["vod"] = vod
        }
        let assinatura = (try? JSONSerialization.data(withJSONObject: semPosicao, options: [.sortedKeys]))
            .map { String(decoding: $0, as: UTF8.self) } ?? ""
        let vodNoAr = e["vod"] != nil && Date().timeIntervalSince(ultimoEnvio) >= 5
        guard forcado || assinatura != ultimaAssinatura || vodNoAr else { return }
        ultimaAssinatura = assinatura
        ultimoEnvio = Date()
        e["t"] = "state"
        enviar(e, para: clientes)
    }

    // MARK: - Estado

    /// O que está no ar, no formato da TV Box (`obterEstado`). O celular toca
    /// `screens[i].source` sozinho, então a fonte vai com os cabeçalhos.
    private func estado() -> [String: Any] {
        var e: [String: Any] = [
            "t": "state",
            "volume": model.volume,
            "muted": model.isMuted,
            "tvAudio": somDaTv,
            "phoneAudio": somNoCelular.map { ["cid": $0.key, "name": $0.value.nome, "src": $0.value.src] },
            "multi": false,
            "active": 0,
        ]
        let secao = VodEstado.shared.secao

        if let arquivo = model.fonteDoArquivoNoAr, model.playingFile != nil {
            e["mode"] = "vod"
            e["screen"] = secao == nil ? "vod" : telaDaSecao(secao)
            e["playing"] = model.isPlaying
            e["vod"] = [
                "title": model.playingFileName,
                "subtitle": model.playingFileDetail,
                "pos": Int64(model.position * 1000),
                "dur": Int64(model.duration * 1000),
                "key": model.episodioNoAr?.serie ?? model.playingFileName,
                "url": arquivo.absoluteString,
            ] as [String: Any]
            e["screens"] = [[
                "idx": 0,
                "channel": model.playingFileName,
                "num": 0,
                "logo": "",
                "program": model.playingFileDetail,
                "sourceIndex": model.sourceIndex,
                "source": ["url": arquivo.absoluteString, "referer": NSNull(), "userAgent": NSNull(),
                           "keyId": NSNull(), "key": NSNull()] as [String: Any],
                "liveOffset": 0,
            ] as [String: Any]]
            return e
        }

        if secao != nil {
            if let radio = Radios.shared.tocando {
                e["mode"] = "radio"
                e["screen"] = "radio"
                e["playing"] = Radios.shared.noAr
                e["screens"] = [[
                    "idx": 0, "channel": radio.nome, "num": 0, "logo": radio.logo ?? "",
                    "program": "", "sourceIndex": 0,
                    "source": ["url": radio.url, "referer": NSNull(), "userAgent": NSNull(),
                               "keyId": NSNull(), "key": NSNull()] as [String: Any],
                    "liveOffset": 0,
                ] as [String: Any]]
            } else {
                // Com o acervo aberto o ao vivo fica parado (MultiTela.swift).
                e["mode"] = "idle"
                e["screen"] = telaDaSecao(secao)
                e["channel"] = ""
                e["playing"] = false
                e["screens"] = [[String: Any]]()
            }
            return e
        }

        e["mode"] = "live"
        e["screen"] = model.showGuide ? "guide" : "live"
        e["playing"] = model.isPlaying && model.player.timeControlStatus == .playing
        e["multi"] = model.multiTela
        e["active"] = model.multiTela && model.segundaAtiva ? 1 : 0
        var telas: [[String: Any]] = []
        if let canal = model.selectedChannel {
            telas.append(tela(0, canal, fonte: ProxyServer.shared.variantIndex(canal), player: model.player))
        }
        if model.multiTela, let canal = model.segunda.canal {
            telas.append(tela(1, canal, fonte: model.segunda.fonte, player: model.segunda.player))
        }
        e["screens"] = telas
        return e
    }

    private func telaDaSecao(_ secao: VodSecao?) -> String {
        switch secao {
        case .ajustes: return "settings"
        case .buscar: return "search"
        case .radios: return "radio"
        case nil: return "live"
        default: return "home"
        }
    }

    private func tela(_ idx: Int, _ canal: Channel, fonte: Int, player: AVPlayer) -> [String: Any] {
        let indice = min(max(fonte, 0), canal.variants.count - 1)
        let variante = canal.variants[indice]
        let numero = (model.visibleChannels.firstIndex { $0.id == canal.id }).map { $0 + 1 } ?? 0
        var atraso: Int64 = 12_000
        if let item = player.currentItem, let faixa = item.seekableTimeRanges.last?.timeRangeValue {
            let fim = CMTimeRangeGetEnd(faixa).seconds
            let agora = player.currentTime().seconds
            if fim.isFinite, agora.isFinite, fim > agora { atraso = Int64((fim - agora) * 1000) }
        }
        return [
            "idx": idx,
            "channel": canal.name,
            "num": numero,
            "logo": canal.logo?.absoluteString ?? "",
            "program": EPGService.shared.nowNext(for: canal)?.current.title ?? "",
            "sourceIndex": indice,
            "source": [
                "url": variante.url.absoluteString,
                "referer": variante.referer ?? NSNull(),
                "userAgent": variante.userAgent ?? NSNull(),
                "keyId": variante.clearKeyId ?? NSNull(),
                "key": variante.clearKeyId == nil ? NSNull() as Any : (variante.clearKey ?? NSNull()) as Any,
            ] as [String: Any],
            "liveOffset": atraso,
        ]
    }

    /// De qual tela sai o som do Mac, como a TV Box informa.
    private var somDaTv: String {
        if let fixo = model.somDoConnect { return fixo }
        return model.multiTela && model.segundaAtiva ? "1" : "0"
    }

    /// Onde cada tela está na régua comum: ao vivo, a data do trecho no ar
    /// (a real do canal, ou a sintética que o proxy escreveu — ver
    /// `Historico`); filme, a posição. Tela sem régua (canal remontado pelo
    /// ffmpeg, que não leva a marca) fica de fora e o celular toca sem acerto.
    private func instantes() -> [[String: Any]] {
        var telas: [[String: Any]] = []
        if model.playingFile != nil {
            let t = model.player.currentTime().seconds
            if t.isFinite {
                telas.append(["idx": 0, "st": Int64((t * 1000).rounded()),
                              "playing": model.player.timeControlStatus == .playing])
            }
            return telas
        }
        guard VodEstado.shared.secao == nil else { return telas }
        if let data = model.player.currentItem?.currentDate() {
            telas.append(["idx": 0, "st": Int64((data.timeIntervalSince1970 * 1000).rounded()),
                          "playing": model.player.timeControlStatus == .playing])
        }
        if model.multiTela, model.segunda.canal != nil,
           let data = model.segunda.player.currentItem?.currentDate() {
            telas.append(["idx": 1, "st": Int64((data.timeIntervalSince1970 * 1000).rounded()),
                          "playing": model.segunda.player.timeControlStatus == .playing])
        }
        return telas
    }

    // MARK: - Comandos

    private func executar(_ tipo: String, _ j: [String: Any], de cliente: ClienteConnect) {
        switch tipo {
        case "tune":
            if let nome = j["channel"] as? String { sintonizar(nome, tela: inteiro(j["screen"])) }
        case "multi":
            alternarMultiTela((j["on"] as? Bool) ?? false)
        case "activeScreen":
            if model.multiTela { model.ativarTela(inteiro(j["idx"]) == 1 ? .segunda : .principal) }
        case "sync", "getState":
            avisarEstado(forcado: true)
        case "tvAudio":
            somDaTv((j["src"] as? String) ?? "0")
        case "playVod", "playMedia":
            Task { await abrirVod(j) }
        case "playPause":
            if model.playingFile != nil { model.togglePlayPause() }
        case "seek":
            guard model.playingFile != nil else { break }
            if let delta = numero(j["delta"]) {
                model.pular(delta / 1000)
            } else if let ms = numero(j["ms"]), ms >= 0 {
                model.seek(to: ms / 1000)
            }
        case "fonte":
            trocarFonte(inteiro(j["delta"]) ?? 1)
        case "key":
            if let codigo = j["code"] as? String { tecla(codigo) }
        case "volume":
            if let delta = numero(j["delta"]) {
                model.nudgeVolume(delta > 0 ? 0.05 : -0.05)
            } else if let valor = numero(j["set"]) {
                model.volume = min(1, max(0, valor))
                if valor > 0 { model.isMuted = false }
            } else if let mudo = j["mute"] as? Bool {
                model.isMuted = mudo
            }
        case "text":
            escrever((j["value"] as? String) ?? "")
        case "phoneAudio":
            guard let cid = cliente.cid else { break }
            somNoCelular[cid] = (cliente.nome, (j["src"] as? String) ?? "none")
            somDoCelularMudou()
        default:
            break
        }
        avisarEstado()
    }

    private func inteiro(_ v: Any?) -> Int? { (v as? NSNumber)?.intValue }
    private func numero(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }

    private func sintonizar(_ nome: String, tela: Int?) {
        // Só a lista que está na tela: o que o código esconde continua escondido.
        let alvo = nome.trimmingCharacters(in: .whitespaces)
        guard let canal = model.channels.first(where: { $0.name == alvo })
            ?? model.channels.first(where: { $0.name.localizedCaseInsensitiveCompare(alvo) == .orderedSame })
        else { return }
        // Na multi tela: a tela pedida, ou a ativa quando o celular não diz.
        if model.multiTela {
            if tela == 1 || (tela == nil && model.segundaAtiva) {
                model.tocarNaSegunda(canal)
                return
            }
            model.ativarTela(.principal)
        }
        Radios.shared.parar()
        let mesmo = model.selection == canal.id
        model.selection = canal.id
        if VodEstado.shared.secao != nil {
            VodEstado.shared.secao = nil
        } else if mesmo, model.playingFile != nil || model.player.currentItem == nil {
            model.play()
        }
    }

    private func alternarMultiTela(_ ligar: Bool) {
        if ligar {
            guard !model.multiTela else { return }
            if model.playingFile != nil { model.voltarAoVivo() }
            if VodEstado.shared.secao != nil { VodEstado.shared.secao = nil }
            model.alternarMultiTela()
        } else if model.multiTela {
            model.alternarMultiTela()
        }
    }

    /// "0"/"1": o som do Mac sai dessa tela; "mute": o Mac fica calado. Sem
    /// ninguém ouvindo no celular, escolher a tela é o mesmo que ativá-la.
    private func somDaTv(_ src: String) {
        if src == "mute" {
            model.somDoConnect = "mute"
        } else if !model.multiTela {
            model.somDoConnect = nil
        } else if temSomNoCelular {
            model.somDoConnect = src == "1" ? "1" : "0"
        } else {
            model.somDoConnect = nil
            model.ativarTela(src == "1" ? .segunda : .principal)
        }
    }

    /// Ninguém mais ouvindo no celular: o som do Mac volta a seguir a tela ativa.
    private func somDoCelularMudou() {
        if !temSomNoCelular, model.somDoConnect != "mute" { model.somDoConnect = nil }
        let ouvindo = somNoCelular.values.filter { ["0", "1", "both"].contains($0.src) }
        for o in ouvindo {
            let qual = !model.multiTela ? "o Mac" : o.src == "0" ? "a tela 1" : o.src == "1" ? "a tela 2" : "as duas telas"
            Log.shared.write("Saimo Connect: \(o.nome) ouvindo \(qual) no celular")
        }
    }

    private func trocarFonte(_ delta: Int) {
        if model.playingFile != nil {
            model.trocarFonteDoArquivo(delta)
            return
        }
        guard let canal = model.canalAtivo, canal.variants.count > 1 else { return }
        let n = canal.variants.count
        if model.multiTela && model.segundaAtiva {
            let proxima = ((model.segunda.fonte + delta) % n + n) % n
            ProxyServer.shared.forceVariant(canal, proxima)
            model.segunda.tocar(canal)
        } else {
            let proxima = ((ProxyServer.shared.variantIndex(canal) + delta) % n + n) % n
            model.playVariant(canal, index: proxima)
        }
    }

    // MARK: - Filme e série

    /// Abre o título pedido pelo celular: acha no acervo (pelo índice de busca,
    /// que não tem os extras), escolhe o episódio e toca como a grade tocaria.
    private func abrirVod(_ j: [String: Any]) async {
        let chave = (j["key"] as? String) ?? ""
        var dachave: (serie: Bool?, letra: String?, titulo: String?, ano: String?) = (nil, nil, nil, nil)
        if chave.hasPrefix("saimo|") {
            let partes = chave.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            if partes.count > 1 { dachave.serie = partes[1] == "s" }
            if partes.count > 2 { dachave.letra = partes[2].removingPercentEncoding }
            if partes.count > 3 { dachave.titulo = partes[3].removingPercentEncoding }
            if partes.count > 4 { dachave.ano = partes[4].removingPercentEncoding }
        }
        func texto(_ k: String) -> String? {
            (j[k] as? String).flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        }
        let titulo = texto("title") ?? dachave.titulo
            ?? (!chave.hasPrefix("saimo|") && !chave.isEmpty ? chave : "Vídeo")
        let ano = texto("year") ?? dachave.ano ?? ""
        let temporada = inteiro(j["temporada"]) ?? 0
        let serie = (j["isSeries"] as? Bool) ?? dachave.serie ?? (temporada > 0)
        let episodio = inteiro(j["episodio"]) ?? 0
        let fonte = inteiro(j["fonte"]) ?? 0
        let direto = texto("url").flatMap(URL.init(string:))
        let inicio = numero(j["startTime"]) ?? 0

        let todos = await Vod.todos()
        let normal = { (s: String) in s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
        let candidatos = todos.filter { normal($0.titulo) == normal(titulo) || normal($0.nomeCompleto) == normal(titulo) }
        let achado = candidatos.first { $0.serie == serie && (ano.isEmpty || $0.ano == ano) }
            ?? candidatos.first { $0.serie == serie }
            ?? candidatos.first

        func comecar() {
            if model.multiTela { model.fecharTela(.segunda) }
            Radios.shared.parar()
            model.inicioPedido = inicio > 0 ? inicio : nil
        }

        if let achado, achado.serie {
            var lista: [Episodio] = []
            var nomeDaSerie = achado.nomeCompleto
            if let s = await Vod.series(letra: achado.letra)
                .first(where: { $0.titulo == achado.titulo && (achado.ano.isEmpty || $0.ano == achado.ano) }) {
                lista = await Vod.episodios(letra: achado.letra, serie: s)
                nomeDaSerie = s.nomeCompleto
            } else {
                for tipo in ["animes", "doramas"] {
                    if let par = await Vod.colecao(tipo).first(where: { $0.0.titulo == achado.titulo }) {
                        lista = par.1
                        nomeDaSerie = par.0.nomeCompleto
                        break
                    }
                }
            }
            let escolhido: Episodio?
            if temporada > 0 || episodio > 0 {
                let iguais = lista.filter {
                    (temporada == 0 || $0.temporada == temporada) && (episodio == 0 || $0.numero == episodio)
                }
                escolhido = iguais.first { $0.versao != "leg" } ?? iguais.first
            } else {
                escolhido = lista.min { ($0.temporada, $0.numero, $0.versao == "leg" ? 1 : 0)
                    < ($1.temporada, $1.numero, $1.versao == "leg" ? 1 : 0) }
            }
            if let ep = escolhido {
                var urls = model.fontesPreferidas(serie: nomeDaSerie, urls: ep.urls).compactMap(URL.init(string:))
                urls = primeiro(urls, fonte: fonte, direto: direto)
                comecar()
                model.episodioPendente = EpisodioNoAr(serie: nomeDaSerie, temporada: ep.temporada,
                                                      numero: ep.numero, versao: ep.versao, lista: lista)
                model.playFile(urls, nome: nomeDaSerie,
                               detalhe: "Temporada \(ep.temporada), episódio \(ep.numero)",
                               chave: Progresso.chaveEpisodio(nomeDaSerie, ep.temporada, ep.numero))
                VodEstado.shared.secao = nil
                return
            }
        } else if let achado,
                  let filme = await Vod.filmes(letra: achado.letra).first(where: { $0.titulo == achado.titulo }) {
            let versoes = filme.fontes.keys.sorted { ($0 == "leg" ? 1 : 0, $0) < ($1 == "leg" ? 1 : 0, $1) }
            let ordenadas = versoes.flatMap { v in
                (filme.fontes[v] ?? []).sorted {
                    Vod.posicao(daQualidade: Vod.qualidade(de: $0)) < Vod.posicao(daQualidade: Vod.qualidade(de: $1))
                }
            }
            let urls = primeiro(ordenadas.compactMap(URL.init(string:)), fonte: fonte, direto: direto)
            if !urls.isEmpty {
                comecar()
                model.episodioPendente = nil
                model.playFile(urls, nome: filme.titulo, detalhe: "Filme",
                               chave: Progresso.chaveFilme(filme.titulo))
                VodEstado.shared.secao = nil
                return
            }
        }
        // Fora do acervo: o endereço que o celular mandou.
        guard let direto else {
            Log.shared.write("Saimo Connect: \(titulo) não encontrado no acervo")
            return
        }
        comecar()
        model.episodioPendente = nil
        model.playFile([direto], nome: titulo, detalhe: serie ? "Episódio" : "Filme",
                       chave: Progresso.chaveFilme(titulo))
        VodEstado.shared.secao = nil
    }

    /// A fonte pedida (ou o endereço mandado) vai na frente; as outras ficam
    /// de reserva, na ordem de sempre.
    private func primeiro(_ urls: [URL], fonte: Int, direto: URL?) -> [URL] {
        var lista = urls
        if fonte > 0, fonte < lista.count { lista.insert(lista.remove(at: fonte), at: 0) }
        if let direto {
            lista.removeAll { $0 == direto }
            lista.insert(direto, at: 0)
        }
        return lista
    }

    // MARK: - Controle remoto

    /// As teclas do controle do celular, no que o teclado do Mac já faz. Os
    /// números escolhem o canal pelo número da lista; não passam pelo teclado
    /// de propósito, para o código dos extras continuar só no teclado do Mac.
    private func tecla(_ codigo: String) {
        if let campo = campoEmEdicao() {
            teclaNoCampo(codigo, campo)
            return
        }
        switch codigo {
        case "0", "1", "2", "3", "4", "5", "6", "7", "8", "9":
            digitar(codigo)
            return
        case "DEL":
            if !numero.isEmpty { numero.removeLast(); agendarNumero() }
            return
        case "CLEAR":
            numero = ""
            geracaoDoNumero += 1
            return
        case "HOME":
            Aba.inicio.abrir()
            return
        case "MENU":
            Aba.ajustes.abrir()
            return
        case "CH_UP":
            if model.playingFile == nil { fecharAcervoParaOAoVivo(); model.step(-1) }
            return
        case "CH_DOWN":
            if model.playingFile == nil { fecharAcervoParaOAoVivo(); model.step(1) }
            return
        default:
            break
        }

        let estado = VodEstado.shared
        if codigo == "BACK" {
            voltar()
            return
        }
        // No acervo a navegação é de mouse; só o voltar vale.
        guard estado.secao == nil else { return }

        if model.playingFile != nil {
            switch codigo {
            case "OK":
                if model.puloNaTela != nil { model.pularTrecho() }
                else if model.proximoNaTela != nil { _ = model.tocarProximo() }
                else { model.togglePlayPause() }
            case "LEFT": model.pular(-10)
            case "RIGHT": model.pular(10)
            case "UP": model.nudgeVolume(0.05)
            case "DOWN": model.nudgeVolume(-0.05)
            default: break
            }
            return
        }
        switch codigo {
        case "UP": model.step(-1)
        case "DOWN": model.step(1)
        case "LEFT": Interface.shared.painelCanais = true
        case "RIGHT": model.showGuide = true
        case "OK":
            if !numero.isEmpty { confirmarNumero() } else { Interface.shared.painelCanais.toggle() }
        default: break
        }
    }

    private func fecharAcervoParaOAoVivo() {
        if VodEstado.shared.secao != nil { VodEstado.shared.secao = nil }
    }

    /// Voltar: fecha o que estiver por cima, um de cada vez.
    private func voltar() {
        let estado = VodEstado.shared
        if model.showGuide { model.showGuide = false; return }
        if model.painelEpisodios { model.painelEpisodios = false; return }
        if !numero.isEmpty { numero = ""; geracaoDoNumero += 1; return }
        if estado.secao != nil {
            if estado.serieAberta != nil { estado.serieAberta = nil } else { estado.secao = nil }
            return
        }
        if model.playingFile != nil {
            if model.proximoNaTela != nil { model.dispensarProximo() } else { model.voltarAoVivo() }
            return
        }
        if Interface.shared.painelCanais { Interface.shared.painelCanais = false; return }
        if model.multiTela { model.alternarMultiTela(); return }
        if model.isFullScreen { model.toggleFullScreen() }
    }

    private func digitar(_ digito: String) {
        guard model.playingFile == nil else { return }
        numero = String((numero + digito).suffix(4))
        agendarNumero()
    }

    private func agendarNumero() {
        geracaoDoNumero += 1
        let esta = geracaoDoNumero
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.geracaoDoNumero == esta else { return }
                self.confirmarNumero()
            }
        }
    }

    private func confirmarNumero() {
        geracaoDoNumero += 1
        defer { numero = "" }
        let lista = model.visibleChannels
        guard let n = Int(numero), n >= 1, n <= lista.count else { return }
        Radios.shared.parar()
        model.escolherNaLista(lista[n - 1].id)
    }

    // MARK: - Texto

    /// O campo de texto em edição na janela da frente, se houver.
    private func campoEmEdicao() -> NSTextView? {
        guard let janela = NSApp.keyWindow ?? NSApp.mainWindow,
              let editor = janela.firstResponder as? NSTextView, editor.isFieldEditor else { return nil }
        return editor
    }

    private func teclaNoCampo(_ codigo: String, _ campo: NSTextView) {
        switch codigo {
        case "DEL": campo.deleteBackward(nil)
        case "CLEAR": campo.selectAll(nil); campo.delete(nil)
        case "LEFT": campo.moveLeft(nil)
        case "RIGHT": campo.moveRight(nil)
        case "OK": campo.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        case "BACK": campo.window?.makeFirstResponder(nil)
        case "0", "1", "2", "3", "4", "5", "6", "7", "8", "9":
            campo.insertText(codigo, replacementRange: campo.selectedRange())
        default: break
        }
    }

    private func escrever(_ valor: String) {
        guard let campo = campoEmEdicao() else { return }
        campo.selectAll(nil)
        campo.insertText(valor, replacementRange: campo.selectedRange())
    }

    /// Campo de texto que abriu ou fechou na tela: o celular abre o teclado
    /// dele (`textRequest`) e fecha quando o campo sai (`textDone`).
    private func vigiarTexto(_ clientes: [ClienteConnect]) {
        let campo = campoEmEdicao()
        if let campo, !editandoTexto {
            editandoTexto = true
            let dica = (campo.delegate as? NSTextField)?.placeholderString ?? "Buscar"
            enviar(["t": "textRequest", "hint": dica, "value": campo.string], para: clientes)
        } else if campo == nil, editandoTexto {
            editandoTexto = false
            enviar(["t": "textDone"], para: clientes)
        }
    }
}

// MARK: - Rede

struct Identidade: Sendable {
    let id: String
    let nome: String
    let versao: String
}

/// O servidor TCP da porta 8999: HTTP para `/info` e `/hls`, WebSocket para o
/// resto. Uma thread por conexão, como o `ProxyServer`; a lista de celulares
/// mora atrás de `lock`, daí o `@unchecked Sendable`.
final class ServidorConnect: @unchecked Sendable {
    private static let guidWebSocket = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

    private var fd: Int32 = -1
    private var identidade = Identidade(id: "", nome: "", versao: "")
    private var clientes: [ClienteConnect] = []
    private let lock = NSLock()

    func iniciar(_ identidade: Identidade) -> Bool {
        lock.lock(); self.identidade = identidade; lock.unlock()
        signal(SIGPIPE, SIG_IGN)
        let s = socket(AF_INET, SOCK_STREAM, 0)
        guard s >= 0 else { return false }
        var sim: Int32 = 1
        setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &sim, socklen_t(MemoryLayout<Int32>.size))
        var endereco = sockaddr_in()
        endereco.sin_family = sa_family_t(AF_INET)
        endereco.sin_port = SaimoConnect.porta.bigEndian
        endereco.sin_addr.s_addr = INADDR_ANY.bigEndian
        endereco.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        let ligou = withUnsafePointer(to: &endereco) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(s, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard ligou == 0, listen(s, 16) == 0 else { close(s); return false }
        fd = s
        let t = Thread { [weak self] in self?.aceitar() }
        t.name = "saimo-connect"
        t.start()
        return true
    }

    func todos() -> [ClienteConnect] {
        lock.lock(); defer { lock.unlock() }
        return clientes
    }

    func autenticados() -> [ClienteConnect] { todos().filter(\.autenticado) }

    private func aceitar() {
        while fd >= 0 {
            let c = accept(fd, nil, nil)
            if c < 0 {
                if errno == EINTR { continue }
                break
            }
            var sim: Int32 = 1
            setsockopt(c, IPPROTO_TCP, TCP_NODELAY, &sim, socklen_t(MemoryLayout<Int32>.size))
            setsockopt(c, SOL_SOCKET, SO_NOSIGPIPE, &sim, socklen_t(MemoryLayout<Int32>.size))
            let t = Thread { [weak self] in
                self?.atender(c)
            }
            t.name = "saimo-connect-cliente"
            t.start()
        }
    }

    private func atender(_ c: Int32) {
        var fechar = true
        defer { if fechar { close(c) } }
        var lido: [UInt8] = []
        var pedaco = [UInt8](repeating: 0, count: 4096)
        var fimDoCabecalho: Int?
        while fimDoCabecalho == nil {
            let n = recv(c, &pedaco, pedaco.count, 0)
            if n <= 0 { return }
            lido.append(contentsOf: pedaco[0..<n])
            if lido.count > 16 * 1024 { return }
            if let i = Self.procurar([13, 10, 13, 10], em: lido) { fimDoCabecalho = i + 4 }
        }
        let cabecalho = String(decoding: lido[0..<fimDoCabecalho!], as: UTF8.self)
        let sobra = Array(lido[fimDoCabecalho!...])
        let linhas = cabecalho.components(separatedBy: "\r\n")
        let partes = (linhas.first ?? "").split(separator: " ")
        let metodo = partes.first.map(String.init) ?? ""
        let alvo = partes.count > 1 ? String(partes[1]) : "/"
        func campo(_ nome: String) -> String? {
            linhas.first { $0.lowercased().hasPrefix(nome.lowercased() + ":") }
                .map { String($0.dropFirst(nome.count + 1)).trimmingCharacters(in: .whitespaces) }
        }

        if metodo == "OPTIONS" {
            responder(c, 204, "No Content", tipo: nil, corpo: Data())
            return
        }
        if metodo == "GET", alvo == "/info" || alvo.hasPrefix("/info?") {
            lock.lock(); let eu = identidade; lock.unlock()
            let info: [String: Any] = ["app": "saimo-tv", "id": eu.id, "name": eu.nome,
                                       "version": eu.versao, "port": Int(SaimoConnect.porta), "multi": true]
            let dados = (try? JSONSerialization.data(withJSONObject: info)) ?? Data()
            responder(c, 200, "OK", tipo: "application/json; charset=utf-8", corpo: dados)
            return
        }
        if metodo == "GET", alvo.hasPrefix("/hls") {
            let r = ConnectHls.responder(alvo: alvo, cabecalho: cabecalho)
            responder(c, r.codigo, r.codigo == 200 ? "OK" : r.codigo == 400 ? "Bad Request" : "Bad Gateway",
                      tipo: r.tipo, corpo: Data(r.corpo.utf8), semCache: true)
            return
        }
        if campo("Upgrade")?.lowercased() == "websocket", let chave = campo("Sec-WebSocket-Key") {
            let aceite = Data(Insecure.SHA1.hash(data: Data((chave + Self.guidWebSocket).utf8)))
                .base64EncodedString()
            let resposta = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n" +
                "Connection: Upgrade\r\nSec-WebSocket-Accept: \(aceite)\r\n\r\n"
            guard Self.escrever(c, Data(resposta.utf8)) else { return }
            fechar = false
            let cliente = ClienteConnect(fd: c)
            lock.lock(); clientes.append(cliente); lock.unlock()
            cliente.ler(inicio: sobra)
            lock.lock(); clientes.removeAll { $0 === cliente }; lock.unlock()
            cliente.encerrar()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { SaimoConnect.shared.desconectou(cliente) }
            }
            return
        }
        responder(c, 404, "Not Found", tipo: "text/plain", corpo: Data("não encontrado".utf8))
    }

    private func responder(_ c: Int32, _ codigo: Int, _ motivo: String, tipo: String?,
                           corpo: Data, semCache: Bool = false) {
        var cabecalho = "HTTP/1.1 \(codigo) \(motivo)\r\n"
        if let tipo { cabecalho += "Content-Type: \(tipo)\r\n" }
        if semCache { cabecalho += "Cache-Control: no-cache\r\n" }
        cabecalho += "Access-Control-Allow-Origin: *\r\n"
        cabecalho += "Access-Control-Allow-Methods: GET, OPTIONS\r\n"
        cabecalho += "Access-Control-Allow-Headers: *\r\n"
        cabecalho += "Connection: close\r\n"
        cabecalho += "Content-Length: \(corpo.count)\r\n\r\n"
        var tudo = Data(cabecalho.utf8)
        tudo.append(corpo)
        _ = Self.escrever(c, tudo)
    }

    static func escrever(_ c: Int32, _ dados: Data) -> Bool {
        dados.withUnsafeBytes { buffer -> Bool in
            guard let base = buffer.baseAddress else { return true }
            var enviado = 0
            while enviado < buffer.count {
                let n = send(c, base.advanced(by: enviado), buffer.count - enviado, 0)
                if n <= 0 { return false }
                enviado += n
            }
            return true
        }
    }

    static func procurar(_ agulha: [UInt8], em palheiro: [UInt8]) -> Int? {
        guard palheiro.count >= agulha.count else { return nil }
        for i in 0...(palheiro.count - agulha.count) where palheiro[i] == agulha[0] {
            if Array(palheiro[i..<(i + agulha.count)]) == agulha { return i }
        }
        return nil
    }
}

/// Um celular ligado por WebSocket (RFC 6455, feito à mão como na TV Box).
///
/// A leitura roda na thread da conexão; a escrita numa fila só dele, para os
/// quadros não se misturarem. O socket só fecha depois de a fila esvaziar —
/// um número de socket reaproveitado nunca recebe o que era deste.
final class ClienteConnect: @unchecked Sendable {
    private let fd: Int32
    private let lock = NSLock()
    private let fila = DispatchQueue(label: "saimo.connect.envio")
    private var _cid: String?
    private var _nome = "Celular"
    private var _autenticado = false
    private var _fechado = false

    init(fd: Int32) { self.fd = fd }

    var cid: String? { lock.lock(); defer { lock.unlock() }; return _cid }
    var nome: String { lock.lock(); defer { lock.unlock() }; return _nome }
    var autenticado: Bool { lock.lock(); defer { lock.unlock() }; return _autenticado && !_fechado }
    var fechado: Bool { lock.lock(); defer { lock.unlock() }; return _fechado }

    func identificar(cid: String, nome: String) {
        lock.lock(); _cid = cid; _nome = nome; lock.unlock()
    }

    func autenticar() { lock.lock(); _autenticado = true; lock.unlock() }

    func enviar(_ texto: String) { quadro(0x1, Data(texto.utf8)) }

    /// Derruba a conexão; a thread de leitura acorda e encerra.
    func fechar() {
        // Com a trava presa: o `encerrar` só fecha o socket depois disto.
        lock.lock(); defer { lock.unlock() }
        if !_fechado { shutdown(fd, SHUT_RDWR) }
    }

    /// Fim da conexão, chamado pela thread de leitura.
    func encerrar() {
        lock.lock(); _fechado = true; lock.unlock()
        fila.sync {}
        close(fd)
    }

    private func quadro(_ opcode: UInt8, _ dados: Data) {
        fila.async { [self] in
            guard !fechado else { return }
            var q = Data([0x80 | opcode])
            let n = dados.count
            if n <= 125 {
                q.append(UInt8(n))
            } else if n <= 65_535 {
                q.append(126)
                q.append(UInt8(n >> 8)); q.append(UInt8(n & 0xFF))
            } else {
                q.append(127)
                for i in stride(from: 7, through: 0, by: -1) { q.append(UInt8((UInt64(n) >> (UInt64(i) * 8)) & 0xFF)) }
            }
            q.append(dados)
            if !ServidorConnect.escrever(fd, q) { shutdown(fd, SHUT_RDWR) }
        }
    }

    /// Lê quadros até a conexão fechar.
    func ler(inicio: [UInt8]) {
        var buffer = inicio
        var pedaco = [UInt8](repeating: 0, count: 16 * 1024)
        func exato(_ n: Int) -> [UInt8]? {
            while buffer.count < n {
                let r = recv(fd, &pedaco, pedaco.count, 0)
                if r <= 0 { return nil }
                buffer.append(contentsOf: pedaco[0..<r])
            }
            let saida = Array(buffer[0..<n])
            buffer.removeFirst(n)
            return saida
        }
        var mensagem: [UInt8] = []
        while true {
            guard let h = exato(2) else { return }
            let fim = h[0] & 0x80 != 0
            let opcode = h[0] & 0x0F
            let mascarado = h[1] & 0x80 != 0
            var tamanho = UInt64(h[1] & 0x7F)
            if tamanho == 126 {
                guard let e = exato(2) else { return }
                tamanho = UInt64(e[0]) << 8 | UInt64(e[1])
            } else if tamanho == 127 {
                guard let e = exato(8) else { return }
                tamanho = e.reduce(0) { $0 << 8 | UInt64($1) }
            }
            guard tamanho <= 1_048_576 else { return }       // teto: 1 MB
            var mascara: [UInt8] = [0, 0, 0, 0]
            if mascarado {
                guard let m = exato(4) else { return }
                mascara = m
            }
            guard var dados = exato(Int(tamanho)) else { return }
            if mascarado { for i in dados.indices { dados[i] ^= mascara[i % 4] } }

            switch opcode {
            case 0x8:                                              // fechar
                quadro(0x8, Data())
                return
            case 0x9:                                              // ping
                quadro(0xA, Data(dados))
            case 0x1, 0x0:                                         // texto (e continuação)
                mensagem.append(contentsOf: dados)
                guard fim else { continue }
                let texto = String(decoding: mensagem, as: UTF8.self)
                mensagem = []
                tratar(texto)
            default:
                break
            }
        }
    }

    private func tratar(_ texto: String) {
        // O ping é respondido aqui mesmo, sem passar pela principal: é com a
        // ida e volta dele que o celular acerta o relógio com o do Mac.
        if texto.contains("\"ping\""),
           let dados = texto.data(using: .utf8),
           let json = (try? JSONSerialization.jsonObject(with: dados)) as? [String: Any],
           json["t"] as? String == "ping" {
            var resposta = "{\"t\":\"pong\""
            if let c0 = Self.numeroBruto("c0", em: texto) { resposta += ",\"c0\":\(c0)" }
            resposta += ",\"tv\":\(Historico.agoraMs())}"
            enviar(resposta)
            return
        }
        DispatchQueue.main.async {
            MainActor.assumeIsolated { SaimoConnect.shared.recebeu(texto, de: self) }
        }
    }

    /// O número como veio no texto: o `c0` volta exatamente igual, sem
    /// arredondar (é o relógio do celular que ele mede).
    private static func numeroBruto(_ campo: String, em texto: String) -> String? {
        guard let r = texto.range(of: "\"\(campo)\"\\s*:\\s*-?[0-9][0-9.eE+\\-]*", options: .regularExpression)
        else { return nil }
        let trecho = texto[r]
        guard let doisPontos = trecho.firstIndex(of: ":") else { return nil }
        let valor = trecho[trecho.index(after: doisPontos)...].trimmingCharacters(in: .whitespaces)
        return Double(valor) != nil ? valor : nil
    }
}
