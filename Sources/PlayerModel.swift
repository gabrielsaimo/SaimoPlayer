import SwiftUI
import AppKit
import AVKit
import AVFoundation
import MediaPlayer
import Combine

struct PlaybackStats {
    var resolution: String = "—"
    var observedBitrate: Double = 0
    var indicatedBitrate: Double = 0
    var droppedFrames: Int = 0
    var stalls: Int = 0
    var bufferedAhead: Double = 0
    var behindLive: Double = 0
}

struct MediaChoice: Identifiable, Hashable {
    let id: String
    let title: String
}

@MainActor
final class PlayerModel: NSObject, ObservableObject {
    static let shared = PlayerModel()

    // Library
    @Published var channels: [Channel] = []
    @Published var favorites: Set<String> = []
    @Published var search: String = ""
    @Published var selection: UUID? { didSet { if selection != oldValue { play() } } }

    // Playback
    @Published private(set) var isPlaying = false
    @Published var status: String = "parado"
    @Published var generatedLink: URL?
    @Published var volume: Double = 1.0 { didSet { applyVolume() } }
    @Published var isMuted = false { didSet { applyVolume() } }
    @Published var rate: Float = 1.0 { didSet { if isPlaying { player.rate = rate } } }
    @Published var fillScreen = false
    @Published var isPiPActive = false
    @Published var isPiPPossible = false
    @Published var alwaysOnTop = false { didSet { applyAlwaysOnTop() } }
    @Published var showStats = false
    @Published var showLog = false
    @Published var showGuide = false
    @Published var showVod = false
    /// Channel list living in its own window pinned to the player.
    @Published var detachedList = true
    @Published var stats = PlaybackStats()

    /// Qual das fontes do canal está no ar, e se ela ainda está carregando.
    ///
    /// Um canal costuma ter três ou quatro fontes e o proxy desce para a
    /// seguinte sozinho quando uma falha. Sem mostrar isso, uma imagem que
    /// demora é indistinguível de uma que não vem, e não há como saber que a
    /// primeira fonte morreu e a segunda salvou o canal.
    @Published var sourceIndex = 0
    @Published var sourceCount = 1
    @Published var sourceHost = ""
    @Published var isLoadingSource = false

    /// Filme ou episódio no ar, em vez de canal. Guardado porque quase tudo
    /// aqui é feito para canal ao vivo — reconexão, vigia de travamento, faixa
    /// de fonte — e nada disso vale para um arquivo que tem começo e fim.
    @Published private(set) var playingFile: URL?
    @Published private(set) var playingFileName = ""
    /// Linha de apoio do arquivo: versão, temporada e episódio. É o que existe
    /// para dizer — a lista de origem não traz sinopse nem gênero.
    @Published private(set) var playingFileDetail = ""
    /// Onde o arquivo no ar deve ser guardado. Ver Progresso.
    private var chaveArquivo = ""

    private var ultimoGuardado: Double = -100

    /// Onde o que está tocando parou. De cinco em cinco segundos, que é o
    /// bastante para não perder nada e pouco o bastante para não escrever em
    /// disco a cada quadro.
    private func guardarProgresso(forcado: Bool = false) {
        guard playingFile != nil, !chaveArquivo.isEmpty, duration > 0 else { return }
        guard forcado || abs(position - ultimoGuardado) >= 5 else { return }
        ultimoGuardado = position
        Progresso.salvar(chaveArquivo, posicao: position, duracao: duration)
    }
    /// Posição e duração do arquivo, para a barra de progresso. Um canal ao
    /// vivo não tem duração, e é por isso que a barra só aparece no arquivo.
    @Published var duration: Double = 0
    @Published var position: Double = 0
    /// Enquanto a pessoa arrasta, o relógio do player não manda na barra: ela
    /// pularia de volta a cada segundo e seria impossível mirar.
    @Published var scrubbing = false

    // Tracks
    @Published var audioChoices: [MediaChoice] = []
    @Published var subtitleChoices: [MediaChoice] = []
    @Published var selectedAudio: String?
    @Published var selectedSubtitle: String?

    let player = AVPlayer()

    private var pip: AVPictureInPictureController?
    private weak var surface: PlayerLayerView?
    private var itemObservers: [NSKeyValueObservation] = []
    private var playerObservers: [NSKeyValueObservation] = []
    private var notificationTokens: [NSObjectProtocol] = []
    private var statsTimer: Timer?
    private var watchdog: Timer?
    private var stalledSince: Date?
    private var reconnectAttempt = 0
    /// Se a fonte atual chegou a entregar imagem desde que o canal abriu.
    /// Enquanto não chegou, uma falha significa fonte ruim, não rede ruim.
    private var playedSinceOpen = false
    private var retomou = false
    private var sourcesTried = 0
    /// Fontes do arquivo no ar, em ordem. O mesmo filme vem das duas listas.
    private var fileSources: [URL] = []
    private var fileSourceIndex = 0

    private var sleepAssertion: NSObjectProtocol?
    private var audioGroup: AVMediaSelectionGroup?
    private var subtitleGroup: AVMediaSelectionGroup?

    /// Extra line-up, present only after the code is typed. Deliberately not
    /// persisted: closing the app locks it again, so the next person to open it
    /// sees the same list as everyone else.
    private(set) var restrictedUnlocked = false
    private var typed = ""
    private var typedAt = Date.distantPast

    private override init() {
        super.init()
        channels = RemoteCatalog.cached() + Store.customChannels()
        favorites = Store.favorites()
        volume = Store.volume()
        for c in channels { ProxyServer.shared.register(c) }
        player.automaticallyWaitsToMinimizeStalling = true
        // Required for the AirPlay picker to offer receivers rather than only
        // mirroring; the proxy advertises a LAN URL the receiver can reach.
        player.allowsExternalPlayback = true
        applyVolume()
        observePlayer()
        setupRemoteCommands()
        selection = channels.first?.id
        EPGService.shared.load(channels: channels)
        refreshCatalog()
    }

    /// Picks up the published list without disturbing what is on screen: the
    /// channel being watched keeps playing if it survived the update.
    private func refreshCatalog() {
        Task { @MainActor in
            guard let fresh = await RemoteCatalog.fetch() else {
                Log.shared.write("lista publicada indisponível — usando a que já estava")
                return
            }
            Log.shared.write("lista publicada: \(fresh.count) canais")
            let playing = selectedChannel?.name
            let extra = restrictedUnlocked ? restrictedChannels : []
            let updated = fresh + Store.customChannels() + extra
            guard updated.map(\.id) != channels.map(\.id) else { return }

            channels = updated
            for c in channels { ProxyServer.shared.register(c) }
            if let playing, let same = channels.first(where: { $0.name == playing }) {
                if same.id != selection { selection = same.id }
            } else if selection == nil || !channels.contains(where: { $0.id == selection }) {
                selection = channels.first?.id
            }
            EPGService.shared.load(channels: channels)
        }
    }

    // MARK: - Library

    var visibleChannels: [Channel] {
        let base = search.isEmpty
            ? channels
            : channels.filter { $0.name.localizedCaseInsensitiveContains(search) }
        return base.sorted {
            let fa = isFavorite($0), fb = isFavorite($1)
            if fa != fb { return fa }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    var selectedChannel: Channel? { channels.first { $0.id == selection } }

    func isFavorite(_ c: Channel) -> Bool { favorites.contains(c.source.absoluteString) }

    func toggleFavorite(_ c: Channel) {
        let key = c.source.absoluteString
        if favorites.contains(key) { favorites.remove(key) } else { favorites.insert(key) }
        Store.setFavorites(favorites)
    }

    func addChannels(_ new: [Channel], persist: Bool = true) {
        var added: [Channel] = []
        for c in new where !channels.contains(where: { $0.id == c.id }) {
            ProxyServer.shared.register(c)
            channels.append(c)
            added.append(c)
        }
        if persist, !added.isEmpty { Store.appendCustom(added) }
        Log.shared.write("adicionados \(added.count) canal(is)")
        if selection == nil { selection = channels.first?.id }
    }

    func removeChannel(_ c: Channel) {
        channels.removeAll { $0.id == c.id }
        Store.removeCustom(c)
        if selection == c.id { selection = channels.first?.id }
    }

    func step(_ delta: Int) {
        let list = visibleChannels
        guard !list.isEmpty else { return }
        let idx = list.firstIndex { $0.id == selection } ?? 0
        let next = (idx + delta + list.count) % list.count
        selection = list[next].id
    }

    // MARK: - Playback

    func play() {
        guard let channel = selectedChannel else { return }
        guardarProgresso(forcado: true)
        playingFile = nil
        chaveArquivo = ""
        duration = 0
        position = 0
        let link = ProxyServer.shared.link(for: channel)
        generatedLink = link
        status = "carregando…"
        reconnectAttempt = 0
        playedSinceOpen = false
        sourcesTried = 0
        Log.shared.write("abrindo \(channel.name) — \(link.absoluteString)")
        load(link, channel: channel)
    }

    /// Toca um arquivo — filme ou episódio — em vez de um canal.
    ///
    /// Vai direto ao endereço, sem passar pelo proxy: um mp4 progressivo o
    /// AVFoundation lê sozinho, e o proxy só existe para reescrever playlist e
    /// remontar o que ele recusa. O provedor responde 302 para uma URL com
    /// token, e o redirecionamento o próprio AVFoundation segue.
    ///
    /// A seleção de canal fica como está, de propósito: a lista lateral é uma
    /// List ligada a ela, e zerá-la fazia a própria lista devolver um canal —
    /// que entrava por cima do filme antes do primeiro quadro.
    func playFile(_ urls: [URL], nome: String, detalhe: String = "", chave: String = "") {
        guard let primeira = urls.first else { return }
        guardarProgresso(forcado: true)
        chaveArquivo = chave
        ultimoGuardado = -100
        fileSources = urls
        fileSourceIndex = 0
        playingFile = primeira
        retomou = false
        playingFileName = nome
        playingFileDetail = detalhe
        duration = 0
        position = 0
        generatedLink = primeira
        status = "carregando…"
        reconnectAttempt = 0
        playedSinceOpen = false
        sourcesTried = 0
        sourceCount = urls.count
        sourceIndex = 0
        sourceHost = primeira.host ?? ""
        Log.shared.write("abrindo \(nome) — \(primeira.absoluteString)")
        load(primeira, channel: nil)
    }

    func playVariant(_ channel: Channel, index: Int) {
        ProxyServer.shared.forceVariant(channel, index)
        if selection != channel.id {
            selection = channel.id
        } else {
            play()
        }
    }

    private func load(_ link: URL, channel: Channel?) {
        tearDownItemObservers()

        let asset = AVURLAsset(url: link, options: [
            "AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": Upstream.userAgent]
        ])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 6

        itemObservers.append(item.observe(\.status, options: [.new]) { [weak self] it, _ in
            Task { @MainActor in self?.itemStatusChanged(it) }
        })
        itemObservers.append(item.observe(\.presentationSize, options: [.new]) { [weak self] it, _ in
            Task { @MainActor in
                let s = it.presentationSize
                if s.width > 0 { self?.stats.resolution = "\(Int(s.width))×\(Int(s.height))" }
            }
        })

        let center = NotificationCenter.default
        notificationTokens.append(center.addObserver(
            forName: .AVPlayerItemPlaybackStalled, object: item, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.stats.stalls += 1
                    Log.shared.write("stall detectado")
                }
            })
        notificationTokens.append(center.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.scheduleReconnect(reason: "falha ao reproduzir") }
            })
        notificationTokens.append(center.addObserver(
            forName: .AVPlayerItemNewErrorLogEntry, object: item, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    if let e = item.errorLog()?.events.last {
                        Log.shared.write("erro HLS: \(e.errorComment ?? "\(e.errorStatusCode)")")
                    }
                    _ = self
                }
            })

        player.replaceCurrentItem(with: item)
        player.rate = rate
        isPlaying = true
        startTimers()
        loadMediaOptions(for: asset, item: item)
        if let channel { updateNowPlaying(channel: channel) }
        preventSleep(true)
    }

    private func itemStatusChanged(_ item: AVPlayerItem) {
        switch item.status {
        case .readyToPlay:
            status = "tocando"
            reconnectAttempt = 0
            sourcesTried = 0
            playedSinceOpen = true
            stalledSince = nil
            // Volta ao ponto em que parou, uma vez só por abertura.
            if playingFile != nil, !retomou, !chaveArquivo.isEmpty {
                retomou = true
                let ponto = Progresso.posicao(chaveArquivo)
                if ponto > 0 { seekQuandoPuder(ponto) }
            }
            Log.shared.write("pronto — reproduzindo")
        case .failed:
            let msg = item.error?.localizedDescription ?? "erro desconhecido"
            Log.shared.write("item falhou: \(msg)")
            scheduleReconnect(reason: msg)
        default:
            break
        }
    }

    func togglePlayPause() {
        if isPlaying {
            player.pause()
            isPlaying = false
            status = "pausado"
            preventSleep(false)
        } else if player.currentItem != nil {
            player.rate = rate
            isPlaying = true
            status = "tocando"
            preventSleep(true)
        } else {
            play()
        }
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        tearDownItemObservers()
        stopTimers()
        isPlaying = false
        status = "parado"
        preventSleep(false)
    }

    func reload() {
        Log.shared.write("recarregando fluxo")
        play()
    }

    /// Jumps to the live edge of the sliding window.
    func jumpToLive() {
        guard let item = player.currentItem,
              let range = item.seekableTimeRanges.last?.timeRangeValue else { return }
        let edge = CMTimeRangeGetEnd(range)
        player.seek(to: edge, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                self?.player.rate = self?.rate ?? 1
                self?.isPlaying = true
            }
        }
        Log.shared.write("pulou para o ao vivo")
    }

    // MARK: - Reconnect

    private func scheduleReconnect(reason: String) {
        if let arquivo = playingFile {
            // Enquanto o arquivo não entregou nada, é fonte ruim: desce para a
            // seguinte antes de insistir na mesma.
            if !playedSinceOpen, fileSourceIndex + 1 < fileSources.count {
                fileSourceIndex += 1
                let proxima = fileSources[fileSourceIndex]
                playingFile = proxima
                sourceIndex = fileSourceIndex
                sourceHost = proxima.host ?? ""
                status = "tentando a fonte \(fileSourceIndex + 1) de \(fileSources.count)…"
                Log.shared.write("\(playingFileName): \(reason) — indo para a fonte \(fileSourceIndex + 1)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    guard let self, self.playingFile == proxima else { return }
                    self.load(proxima, channel: nil)
                }
                return
            }
            reconnectAttempt += 1
            guard reconnectAttempt <= 4 else {
                status = "falhou: \(reason)"
                return
            }
            let retomar = position
            status = "reconectando…"
            Log.shared.write("\(playingFileName): \(reason) — tentando de novo")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, self.playingFile == arquivo else { return }
                self.load(arquivo, channel: nil)
                if retomar > 5 { self.seek(to: retomar) }
            }
            return
        }
        guard let channel = selectedChannel else { return }

        // Enquanto o canal não tocou nenhuma vez, o problema é a fonte, não a
        // rede: em vez de insistir na mesma com espera crescente, desce para a
        // seguinte de imediato. Só depois de rodar a lista inteira é que faz
        // sentido esperar e tentar tudo de novo.
        if !playedSinceOpen, channel.variants.count > 1, sourcesTried + 1 < channel.variants.count {
            sourcesTried += 1
            let next = (ProxyServer.shared.variantIndex(channel) + 1) % channel.variants.count
            ProxyServer.shared.forceVariant(channel, next)
            status = "tentando a fonte \(next + 1) de \(channel.variants.count)…"
            Log.shared.write("\(channel.name): \(reason) — indo para a fonte \(next + 1)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self, let channel = self.selectedChannel else { return }
                self.load(ProxyServer.shared.link(for: channel), channel: channel)
            }
            return
        }

        reconnectAttempt += 1
        guard reconnectAttempt <= 8 else {
            status = "falhou: \(reason)"
            Log.shared.write("desisti após 8 tentativas")
            return
        }
        let delay = min(pow(1.6, Double(reconnectAttempt)), 20)
        status = "reconectando (\(reconnectAttempt))…"
        Log.shared.write("reconectando em \(String(format: "%.1f", delay))s — \(reason)")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, let channel = self.selectedChannel else { return }
            self.load(ProxyServer.shared.link(for: channel), channel: channel)
        }
    }

    /// A duração só existe depois de o item carregar; retomar antes disso
    /// cairia no zero.
    private func seekQuandoPuder(_ segundos: Double) {
        guard let item = player.currentItem else { return }
        let total = item.duration.seconds
        if total.isFinite, total > 0 {
            // A duração publicada só é lida no tique de um segundo, e o seek
            // depende dela: sem preenchê-la aqui, a retomada seria descartada
            // por "duração zero" justamente na abertura.
            duration = total
            seek(to: segundos)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.seekQuandoPuder(segundos)
        }
    }

    /// Vai para um ponto do arquivo. Tolerância zero para o quadro cair onde a
    /// pessoa soltou, e não no ponto-chave mais próximo, que num filme pode
    /// estar dez segundos adiante.
    func seek(to seconds: Double) {
        guard playingFile != nil, duration > 0 else { return }
        let alvo = CMTime(seconds: max(0, min(seconds, duration)), preferredTimescale: 600)
        position = seconds
        player.seek(to: alvo, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    // MARK: - Timers

    private func startTimers() {
        stopTimers()
        statsTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshStats() }
        }
        watchdog = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkStall() }
        }
    }

    private func stopTimers() {
        statsTimer?.invalidate(); statsTimer = nil
        watchdog?.invalidate(); watchdog = nil
    }

    /// O proxy só decide a fonte quando o player pede a playlist, então a
    /// escolha é lida de lá a cada segundo em vez de adivinhada aqui.
    private func refreshSource() {
        if playingFile != nil {
            sourceCount = max(fileSources.count, 1)
            sourceIndex = fileSourceIndex
            isLoadingSource = player.timeControlStatus != .playing
            return
        }
        guard let channel = selectedChannel else { return }
        let index = ProxyServer.shared.variantIndex(channel)
        let variant = channel.variants[min(index, channel.variants.count - 1)]
        if sourceIndex != index { sourceIndex = index }
        if sourceCount != channel.variants.count { sourceCount = channel.variants.count }
        let host = variant.url.host ?? ""
        if sourceHost != host { sourceHost = host }
        let loading = !isPlaying || player.timeControlStatus != .playing
        if isLoadingSource != loading { isLoadingSource = loading }
    }

    private func refreshStats() {
        refreshSource()
        guard let item = player.currentItem else { return }
        if playingFile != nil {
            let total = item.duration.seconds
            duration = total.isFinite && total > 0 ? total : 0
            if !scrubbing {
                let atual = player.currentTime().seconds
                position = atual.isFinite ? atual : 0
            }
            guardarProgresso()
        }
        // presentationSize only fires once the first frame is decoded, and the
        // KVO can land before the layer is ready, so re-read it each tick.
        let size = item.presentationSize
        if size.width > 0 {
            stats.resolution = "\(Int(size.width))×\(Int(size.height))"
        }
        if let e = item.accessLog()?.events.last {
            stats.observedBitrate = e.observedBitrate
            stats.indicatedBitrate = e.indicatedBitrate
            stats.droppedFrames = max(stats.droppedFrames, e.numberOfDroppedVideoFrames)
        }
        if let buffered = item.loadedTimeRanges.last?.timeRangeValue {
            let end = CMTimeGetSeconds(CMTimeRangeGetEnd(buffered))
            stats.bufferedAhead = max(0, end - CMTimeGetSeconds(item.currentTime()))
        }
        if let seekable = item.seekableTimeRanges.last?.timeRangeValue {
            let edge = CMTimeGetSeconds(CMTimeRangeGetEnd(seekable))
            stats.behindLive = max(0, edge - CMTimeGetSeconds(item.currentTime()))
        }
    }

    /// AVPlayer keeps "waiting to play" forever on a dead live source; reconnect instead.
    private func checkStall() {
        guard isPlaying else { stalledSince = nil; return }
        if player.timeControlStatus == .waitingToPlayAtSpecifiedRate {
            if let since = stalledSince {
                // Uma fonte viva entrega imagem em segundos. Esperar doze antes
                // de desconfiar só faz sentido depois que ela já tocou uma vez.
                let limite: TimeInterval = playedSinceOpen ? 12 : 8
                if Date().timeIntervalSince(since) > limite {
                    stalledSince = nil
                    scheduleReconnect(reason: playedSinceOpen ? "travado sem dados"
                                                             : "fonte não entregou imagem")
                }
            } else {
                stalledSince = Date()
            }
        } else {
            stalledSince = nil
        }
    }

    // MARK: - Audio / subtitles

    private func loadMediaOptions(for asset: AVURLAsset, item: AVPlayerItem) {
        Task { @MainActor in
            audioChoices = []; subtitleChoices = []
            audioGroup = try? await asset.loadMediaSelectionGroup(for: .audible)
            subtitleGroup = try? await asset.loadMediaSelectionGroup(for: .legible)
            if let g = audioGroup {
                audioChoices = g.options.map { MediaChoice(id: $0.displayName, title: $0.displayName) }
                selectedAudio = item.currentMediaSelection.selectedMediaOption(in: g)?.displayName
            }
            if let g = subtitleGroup {
                subtitleChoices = [MediaChoice(id: "__off__", title: "Desligado")]
                    + g.options.map { MediaChoice(id: $0.displayName, title: $0.displayName) }
                selectedSubtitle = item.currentMediaSelection.selectedMediaOption(in: g)?.displayName ?? "__off__"
            }
        }
    }

    func selectAudio(_ id: String) {
        guard let g = audioGroup, let item = player.currentItem,
              let opt = g.options.first(where: { $0.displayName == id }) else { return }
        item.select(opt, in: g)
        selectedAudio = id
    }

    func selectSubtitle(_ id: String) {
        guard let g = subtitleGroup, let item = player.currentItem else { return }
        if id == "__off__" {
            item.select(nil, in: g)
        } else if let opt = g.options.first(where: { $0.displayName == id }) {
            item.select(opt, in: g)
        }
        selectedSubtitle = id
    }

    // MARK: - Window / PiP

    func attach(surface: PlayerLayerView) {
        self.surface = surface
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            Log.shared.write("PiP não suportado neste Mac")
            return
        }
        let controller = AVPictureInPictureController(playerLayer: surface.playerLayer)
        controller?.delegate = self
        pip = controller
        playerObservers.append(
            controller!.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] c, _ in
                Task { @MainActor in self?.isPiPPossible = c.isPictureInPicturePossible }
            })
        applyAlwaysOnTop()
    }

    func togglePiP() {
        guard let pip else { return }
        if pip.isPictureInPictureActive { pip.stopPictureInPicture() } else { pip.startPictureInPicture() }
    }

    func toggleFullScreen() {
        surface?.window?.toggleFullScreen(nil)
    }

    var isFullScreen: Bool {
        surface?.window?.styleMask.contains(.fullScreen) ?? false
    }

    private func applyAlwaysOnTop() {
        surface?.window?.level = alwaysOnTop ? .floating : .normal
    }

    func openInExternalPlayer() {
        guard let link = generatedLink else { return }
        NSWorkspace.shared.open(link)
    }

    func copyLink() {
        guard let link = generatedLink else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link.absoluteString, forType: .string)
        Log.shared.write("link copiado")
    }

    /// Exports every generated link as an .m3u playlist for other players.
    func exportPlaylist() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "saimo.m3u"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var out = "#EXTM3U\n"
        for c in channels {
            out += "#EXTINF:-1,\(c.name)\n\(ProxyServer.shared.link(for: c).absoluteString)\n"
        }
        try? out.write(to: url, atomically: true, encoding: .utf8)
        Log.shared.write("playlist exportada: \(url.lastPathComponent)")
    }

    // MARK: - System integration

    private func applyVolume() {
        player.volume = Float(volume)
        player.isMuted = isMuted
        Store.setVolume(volume)
    }

    func nudgeVolume(_ delta: Double) {
        volume = min(1, max(0, volume + delta))
        if volume > 0 { isMuted = false }
    }

    private func observePlayer() {
        playerObservers.append(player.observe(\.timeControlStatus, options: [.new]) { [weak self] p, _ in
            Task { @MainActor in
                guard let self else { return }
                switch p.timeControlStatus {
                case .playing: self.status = "tocando"; self.isPlaying = true
                case .paused: if self.status != "parado" { self.status = "pausado" }
                case .waitingToPlayAtSpecifiedRate: self.status = "aguardando dados…"
                @unknown default: break
                }
            }
        })
    }

    private func setupRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }; return .success
        }
        c.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in if self?.isPlaying == false { self?.togglePlayPause() } }; return .success
        }
        c.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in if self?.isPlaying == true { self?.togglePlayPause() } }; return .success
        }
        c.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.step(1) }; return .success
        }
        c.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.step(-1) }; return .success
        }
    }

    private func updateNowPlaying(channel: Channel) {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: channel.name,
            MPMediaItemPropertyArtist: "Saimo TV",
            MPNowPlayingInfoPropertyIsLiveStream: true,
        ]
        MPNowPlayingInfoCenter.default().playbackState = .playing
    }

    private func preventSleep(_ on: Bool) {
        if on {
            guard sleepAssertion == nil else { return }
            sleepAssertion = ProcessInfo.processInfo.beginActivity(
                options: [.idleDisplaySleepDisabled, .userInitiated],
                reason: "reproduzindo vídeo")
        } else if let token = sleepAssertion {
            ProcessInfo.processInfo.endActivity(token)
            sleepAssertion = nil
        }
    }

    /// Bare-key shortcuts (Space, F, M, arrows) that a menu item cannot own
    /// without stealing keystrokes from the search field.
    func installKeyMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.intersection([.command, .control, .option]) != [] { return event }
            if NSApp.keyWindow?.firstResponder is NSTextView { return event }

            let handled: Bool = MainActor.assumeIsolated {
                if let digits = event.charactersIgnoringModifiers,
                   digits.count == 1, digits.allSatisfy(\.isNumber) {
                    self.typeDigit(digits)
                    return true
                }
                switch event.keyCode {
                case 49:  self.togglePlayPause(); return true                 // space
                case 126: self.nudgeVolume(0.05); return true                 // up
                case 125: self.nudgeVolume(-0.05); return true                // down
                case 123: self.step(-1); return true                          // left
                case 124: self.step(1); return true                           // right
                default: break
                }
                switch event.charactersIgnoringModifiers?.lowercased() {
                case "f": self.toggleFullScreen(); return true
                case "m": self.isMuted.toggle(); return true
                case "p": self.togglePiP(); return true
                case "l": self.jumpToLive(); return true
                case "i": self.showStats.toggle(); return true
                default: return false
                }
            }
            return handled ? nil : event
        }
    }

    // MARK: - Code

    /// Digits typed in a row. Nothing on screen reacts to them, so a wrong code
    /// looks exactly like nothing happening — which is the point.
    private func typeDigit(_ digit: String) {
        if Date().timeIntervalSince(typedAt) > 2 { typed = "" }
        typedAt = Date()
        typed = String((typed + digit).suffix(8))
        if typed.hasSuffix(Self.code) {
            typed = ""
            setRestricted(!restrictedUnlocked)
        }
    }

    private static let code = "1010"

    private func setRestricted(_ unlocked: Bool) {
        guard unlocked != restrictedUnlocked, !restrictedChannels.isEmpty else { return }
        restrictedUnlocked = unlocked
        // Trancar com um desses no ar deixaria o nome à vista na tela; volta
        // para o primeiro canal comum antes de sumir com a lista.
        let restrictedIDs = Set(restrictedChannels.map(\.id))
        let leaving = selection.map { restrictedIDs.contains($0) } ?? false
        let base = channels.filter { !restrictedIDs.contains($0.id) }
        channels = base + (unlocked ? restrictedChannels : [])
        for c in channels { ProxyServer.shared.register(c) }
        if !unlocked, leaving { selection = channels.first?.id }
        objectWillChange.send()
    }

    private func tearDownItemObservers() {
        itemObservers.forEach { $0.invalidate() }
        itemObservers.removeAll()
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
        notificationTokens.removeAll()
    }
}

extension PlayerModel: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ c: AVPictureInPictureController) {
        Task { @MainActor in self.isPiPActive = true; Log.shared.write("PiP ativo") }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ c: AVPictureInPictureController) {
        Task { @MainActor in self.isPiPActive = false; Log.shared.write("PiP encerrado") }
    }

    nonisolated func pictureInPictureController(_ c: AVPictureInPictureController,
                                                failedToStartPictureInPictureWithError error: Error) {
        Task { @MainActor in Log.shared.write("PiP falhou: \(error.localizedDescription)") }
    }
}
