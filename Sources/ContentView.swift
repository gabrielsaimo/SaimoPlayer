import SwiftUI
import AVKit
import AppKit

/// A janela inteira, como na TV Box: a barra de vidro no topo, com as abas, e
/// embaixo dela a tela da aba aberta. "Ao vivo" é o vídeo, com a lista de
/// canais de vidro à esquerda e o cartão do programa no canto; as outras abas
/// são telas em fileiras, e com uma delas aberta o ao vivo para (ver
/// `VodEstado.secao`).
struct ContentView: View {
    @ObservedObject private var model = PlayerModel.shared
    @State private var controlsVisible = true
    @State private var hideWork: DispatchWorkItem?

    @ObservedObject private var vod = VodEstado.shared
    @ObservedObject private var interface = Interface.shared

    @ObservedObject private var atualizacao = Atualizacao.shared

    /// Em tela cheia não há botões de janela: a barra encosta na esquerda.
    @State private var telaCheia = false

    /// Enquanto a abertura animada cobre a janela; a lista de canais (outra
    /// janela, ao lado) espera ela sair.
    @State private var abertura = true
    @State private var abriu = false

    var body: some View {
        ZStack(alignment: .top) {
            FundoDoApp()
            principal
            BarraDoTopo(model: model, telaCheia: telaCheia)
                .opacity(barraVisivel ? 1 : 0)
                .allowsHitTesting(barraVisivel)
                .animation(.easeInOut(duration: 0.22), value: barraVisivel)
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .tint(Tema.acento)
            .background {
                // Põe a abertura por cima da janela inteira (ver `Abertura`).
                Abertura {
                    abertura = false
                    if model.detachedList { SidebarWindowController.shared.open(model: model) }
                }
                .frame(width: 0, height: 0)
            }
            .frame(minWidth: 820, minHeight: 520)
            .sheet(item: $atualizacao.disponivel) { versao in
                AtualizacaoView(atualizacao: atualizacao, versao: versao)
            }
            .task { atualizacao.vigiar() }
            .alert("Atualização", isPresented: Binding(
                get: { atualizacao.aviso != nil },
                set: { if !$0 { atualizacao.aviso = nil } })) {
                Button("OK", role: .cancel) { atualizacao.aviso = nil }
            } message: {
                Text(atualizacao.aviso ?? "")
            }
            .sheet(isPresented: $model.showGuide) {
                EPGGuideView(model: model)
            }
            .navigationTitle(vod.secao?.titulo ?? model.canalAtivo?.name ?? "Saimo TV")
            .onAppear {
                // Como a TV: abre na tela inicial, a menos que os ajustes
                // digam para ir direto ao último canal.
                guard !abriu else { return }
                abriu = true
                if !Preferencias.abrirNoCanal, vod.secao == nil { vod.secao = .inicio }
                // `open -a "Saimo TV" --args -abaInicial radios`: abre direto
                // numa aba, para conferir uma tela sem clicar até ela.
                let padrao = UserDefaults.standard
                if let nome = padrao.string(forKey: "abaInicial") {
                    if let aba = Aba(rawValue: nome) {
                        aba.abrir()
                    } else if let secao = VodSecao(rawValue: nome) {
                        vod.explorando = padrao.bool(forKey: "explorar")
                        vod.secao = secao
                    }
                    interface.painelCanais = padrao.bool(forKey: "listaInicial")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.willEnterFullScreenNotification)) { _ in
                telaCheia = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.willExitFullScreenNotification)) { _ in
                telaCheia = false
            }
            .onChange(of: model.detachedList) { _, detached in
                // A lista é outra janela: só abre quando a abertura sai.
                if detached, !abertura {
                    SidebarWindowController.shared.open(model: model)
                } else {
                    SidebarWindowController.shared.close()
                }
            }
    }

    /// No vídeo a barra some junto com os controles; nas outras telas fica.
    private var barraVisivel: Bool {
        vod.secao != nil || controlsVisible || interface.painelCanais
    }

    @ViewBuilder
    private var principal: some View {
        if vod.secao != nil {
            VodGridView(model: model)
                .transition(.opacity)
        } else {
            stage
        }
    }

    // MARK: - Stage

    private var stage: some View {
        ZStack(alignment: .bottom) {
            // A principal fica sempre no mesmo lugar da árvore: recriá-la ao
            // abrir a multi tela refaria a superfície e o PiP dela.
            HStack(spacing: model.multiTela ? 2 : 0) {
                VideoSurface(
                    player: model.player,
                    gravity: model.fillScreen ? .resizeAspectFill : .resizeAspect,
                    onReady: { model.attach(surface: $0) },
                    onDoubleClick: { model.toggleFullScreen() },
                    onClick: { model.ativarTela(.principal) })
                    .overlay {
                        if model.multiTela {
                            MolduraDaTela(model: model, lado: .principal, rotuloVisivel: controlsVisible)
                        }
                    }
                if model.multiTela {
                    VideoSurface(
                        player: model.segunda.player,
                        gravity: model.fillScreen ? .resizeAspectFill : .resizeAspect,
                        onReady: { _ in },
                        onDoubleClick: { model.toggleFullScreen() },
                        onClick: { model.ativarTela(.segunda) })
                        .overlay {
                            MolduraDaTela(model: model, lado: .segunda, rotuloVisivel: controlsVisible)
                        }
                }
            }
                .background(Color.black)
                .ignoresSafeArea()

            // O véu de baixo e o de cima deixam o vidro e o texto legíveis
            // sobre qualquer imagem, sem caixa preta.
            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 120)
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 220)
            }
            .allowsHitTesting(false)
            .opacity(controlsVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.22), value: controlsVisible)

            LegendaNaTela(model: model, acimaDosControles: controlsVisible)

            if model.showStats {
                statsOverlay
                    .opacity(controlsVisible ? 1 : 0)
                    .animation(.easeInOut(duration: 0.22), value: controlsVisible)
            }

            VStack(alignment: .trailing, spacing: 12) {
                CartaoNoAr(model: model)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                ControlBar(model: model)
            }
                .padding(.horizontal, 22)
                .padding(.bottom, 20)
                .padding(.leading, interface.painelCanais ? 420 : 0)
                .opacity(controlsVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.22), value: controlsVisible)
                .allowsHitTesting(controlsVisible)

            // Fora da regra dos controles: o botão de pular só serve na hora.
            PulosNaTela(model: model, acimaDosControles: controlsVisible)

            if interface.painelCanais {
                PainelDeCanais(model: model)
                    .padding(.top, Tema.alturaDaBarra + 6)
                    .padding([.leading, .bottom], 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            // Por cima de tudo, com o vídeo tocando por trás.
            if model.painelEpisodios, let episodio = model.episodioNoAr {
                PainelEpisodios(model: model, episodio: episodio)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.painelEpisodios)
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: interface.painelCanais)
        .background(Color.black)
        .onContinuousHover { phase in
            switch phase {
            case .active: revealControls()
            case .ended: scheduleHide(after: 0.6)
            }
        }
        .onAppear { revealControls() }
        .onChange(of: interface.painelCanais) { _, aberto in
            if aberto { revealControls() } else { scheduleHide(after: 2.8) }
        }
    }

    private var statsOverlay: some View {
        VStack(alignment: .leading, spacing: 3) {
            statLine("Resolução", model.stats.resolution)
            statLine("Bitrate", String(format: "%.2f Mb/s", model.stats.observedBitrate / 1_000_000))
            statLine("Buffer", String(format: "%.1f s", model.stats.bufferedAhead))
            statLine("Atraso do vivo", String(format: "%.1f s", model.stats.behindLive))
            statLine("Quadros perdidos", "\(model.stats.droppedFrames)")
            statLine("Travamentos", "\(model.stats.stalls)")
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(12)
        .vidroPainel(raio: 14)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.top, Tema.alturaDaBarra + 8)
        .padding(.trailing, 18)
    }

    private func statLine(_ k: String, _ v: String) -> some View {
        HStack(spacing: 8) {
            Text(k).foregroundStyle(.white.opacity(0.6))
            Spacer(minLength: 12)
            Text(v)
        }
        .frame(width: 190, alignment: .leading)
    }

    // MARK: - Control auto-hide

    private func revealControls() {
        hideWork?.cancel()
        if !controlsVisible { controlsVisible = true }
        scheduleHide(after: 2.8)
    }

    private func scheduleHide(after seconds: Double) {
        hideWork?.cancel()
        // Com a lista aberta os controles ficam: ela é para escolher olhando.
        guard !interface.painelCanais else { return }
        let work = DispatchWorkItem { controlsVisible = false }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

}

// MARK: - Sidebar row

struct ChannelRow: View {
    let channel: Channel
    let isFavorite: Bool
    let toggleFavorite: () -> Void

    @ObservedObject private var epg = EPGService.shared
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            ChannelIcon(channel: channel)
            VStack(alignment: .leading, spacing: 2) {
                Text(channel.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let onAir = epg.nowNext(for: channel, at: epg.clock) {
                    Text(onAir.current.title)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let detail = onAir.current.shortDetail {
                        Text(detail)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    ProgressView(value: onAir.progress)
                        .progressViewStyle(.linear)
                        .controlSize(.mini)
                        .frame(height: 2)
                }
            }
            Spacer(minLength: 4)
            if isFavorite || hovering {
                Button(action: toggleFavorite) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .foregroundStyle(isFavorite ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 3)
        .onHover { hovering = $0 }
    }
}

/// Offline channel artwork: a deterministic gradient tile carrying either a
/// genre glyph or the channel's initials.
struct ChannelIcon: View {
    let channel: Channel
    var size: CGFloat = 30

    @ObservedObject private var logos = LogoLoader.shared

    private var glyph: String? {
        let n = channel.name.lowercased()
        if n.contains("impd") { return "globe.americas.fill" }
        if n.contains("telecine") || n.contains("megapix") || n.contains("cine") { return "film.fill" }
        if n.contains("cartoon") || n.contains("adult swim") { return "face.smiling.fill" }
        if n.contains("history") { return "building.columns.fill" }
        if n.contains("animal") || n.contains("planet") { return "pawprint.fill" }
        if n.contains("warner") { return "sparkles.tv.fill" }
        return nil
    }

    private var initials: String {
        let words = channel.name.split(separator: " ").prefix(2)
        return words.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    var body: some View {
        Group {
            if let logo = channel.logo, let image = logos.image(for: logo) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(2)
                    .frame(width: size, height: size)
                    .background(
                        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                            .fill(Color.primary.opacity(0.08)))
            } else {
                placeholder
            }
        }
    }

    /// Monochrome on purpose: the real channel logos are white-on-transparent,
    /// so a coloured tile would stand out as the odd one in the list.
    private var placeholder: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(Color.primary.opacity(0.08))
            .frame(width: size, height: size)
            .overlay {
                if let glyph {
                    Image(systemName: glyph)
                        .font(.system(size: size * 0.46, weight: .medium))
                        .foregroundStyle(.primary)
                } else {
                    Text(initials)
                        .font(.system(size: size * 0.36, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                }
            }
    }
}

// MARK: - Floating control bar

private struct ControlBar: View {
    @ObservedObject var model: PlayerModel

    @ObservedObject private var interface = Interface.shared

    var body: some View {
        VStack(spacing: 10) {
            // Filme e episódio: a barra do tempo inteira, de ponta a ponta,
            // como no player da TV.
            if model.playingFile != nil, model.duration > 0 {
                ScrubBar(model: model)
            }
            controles
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .vidroPainel(raio: 24)
        .environment(\.colorScheme, .dark)
        .shadow(color: .black.opacity(0.3), radius: 14, y: 4)
    }

    private var controles: some View {
        HStack(spacing: 14) {
            if model.playingFile == nil {
                Button { interface.painelCanais.toggle() } label: {
                    Image(systemName: "list.bullet.rectangle.portrait")
                        .symbolVariant(interface.painelCanais ? .fill : .none)
                }
                .help("Lista de canais (⇧⌘L)")
            }

            if model.podePausar || !model.isPlaying {
                Button(action: model.togglePlayPause) {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 22)
                }
                .help(model.isPlaying ? "Pausar (Espaço)" : "Tocar (Espaço)")
            }

            Button(action: model.step0) {
                Image(systemName: "backward.end.fill")
            }
            .help("Canal anterior")

            Button(action: model.step1) {
                Image(systemName: "forward.end.fill")
            }
            .help("Próximo canal")

            if model.playingFile == nil { LiveBadge(model: model) }

            // Na multi tela cada tela mostra a própria fonte no canto dela.
            if !model.multiTela {
                QualityBadge(model: model)

                SourceBadge(model: model)
            }

            volume

            Spacer(minLength: 8)

            if model.playingFile == nil {
                Button { model.showGuide = true } label: {
                    Image(systemName: "calendar.badge.clock")
                }
                .help("Programação completa")
            }

            if model.isPlaying, !model.multiTela {
                Menu {
                    Section("Qualidade · \(model.selectedQualityTitle)") {
                        ForEach(model.qualityChoices) { c in
                            Button { model.selectQuality(c.id) } label: {
                                Text(model.selectedQuality == c.id ? "✓  \(c.title)" : "    \(c.title)")
                            }
                        }
                    }
                    if !model.audioChoices.isEmpty {
                        Section("Áudio · \(model.selectedAudioTitle)") {
                            ForEach(model.audioChoices) { c in
                                Button { model.selectAudio(c.id) } label: {
                                    Text(model.selectedAudio == c.id ? "✓  \(c.title)" : "    \(c.title)")
                                }
                            }
                        }
                    }
                    if !model.subtitleChoices.isEmpty {
                        Section("Legendas · \(model.selectedSubtitleTitle)") {
                            ForEach(model.subtitleChoices) { c in
                                Button { model.selectSubtitle(c.id) } label: {
                                    Text(model.selectedSubtitle == c.id ? "✓  \(c.title)" : "    \(c.title)")
                                }
                            }
                        }
                    }
                    if !model.legendasExt.isEmpty {
                        Section("Legendas · OpenSubtitles") {
                            Button { model.escolherLegendaExterna(nil) } label: {
                                Text(model.legendaExt == nil ? "✓  Desligadas" : "    Desligadas")
                            }
                            ForEach(model.legendasExt) { o in
                                Button { model.escolherLegendaExterna(o) } label: {
                                    Text(model.legendaExt == o ? "✓  \(o.rotulo)" : "    \(o.rotulo)")
                                }
                            }
                            if model.legendaExt != nil {
                                Menu("Sincronia · \(rotuloDoAtraso(model.legendaAtraso))") {
                                    Button("Original") { model.definirAtrasoLegenda(0) }
                                    ForEach([-2.0, -1.0, -0.5, 0.5, 1.0, 2.0], id: \.self) { passo in
                                        Button(passo < 0 ? "Adiantar \(abs(passo).formatted()) s" : "Atrasar \(passo.formatted()) s") {
                                            model.ajustarAtrasoLegenda(passo)
                                        }
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 26)
                .help("Qualidade, áudio e legendas")
            }

            if model.episodioNoAr != nil {
                Button { model.painelEpisodios.toggle() } label: {
                    Image(systemName: "rectangle.stack")
                }
                .help("Episódios (E)")
            }

            Menu {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { r in
                    Button {
                        model.rate = Float(r)
                    } label: {
                        Text(model.rate == Float(r) ? "✓ \(r, specifier: "%g")×" : "\(r, specifier: "%g")×")
                    }
                }
            } label: {
                Image(systemName: "speedometer")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 26)
            .help("Velocidade")

            if model.playingFile == nil {
                Button(action: model.alternarMultiTela) {
                    Image(systemName: model.multiTela ? "rectangle.split.2x1.fill" : "rectangle.split.2x1")
                }
                .help(model.multiTela ? "Sair da multi tela" : "Multi tela")
            }

            Button { model.fillScreen.toggle() } label: {
                Image(systemName: model.fillScreen
                      ? "rectangle.arrowtriangle.2.inward"
                      : "rectangle.arrowtriangle.2.outward")
            }
            .help(model.fillScreen ? "Ajustar à tela" : "Preencher tela")

            Button { model.alwaysOnTop.toggle() } label: {
                Image(systemName: model.alwaysOnTop ? "pin.fill" : "pin")
            }
            .help("Manter à frente")

            // Transmitir e PiP só levam a tela principal: na multi tela
            // ficariam pela metade.
            if !model.multiTela {
                CastMenu(model: model)

                RoutePicker(player: model.player)
                    .frame(width: 24, height: 20)
                    .help("Transmitir para AirPlay")

                Button(action: model.togglePiP) {
                    Image(systemName: model.isPiPActive
                          ? "pip.exit"
                          : "pip.enter")
                }
                .disabled(!model.isPiPPossible)
                .help("Picture in Picture (⌘⇧P)")
            }

            Button(action: model.toggleFullScreen) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .help("Tela cheia (F)")
        }
        .font(.system(size: 15))
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }

    private var volume: some View {
        HStack(spacing: 6) {
            Button { model.isMuted.toggle() } label: {
                Image(systemName: model.isMuted || model.volume == 0
                      ? "speaker.slash.fill"
                      : model.volume < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.3.fill")
                    .frame(width: 18)
            }
            .help("Silenciar (M)")
            Slider(value: $model.volume, in: 0...1)
                .frame(width: 80)
                .controlSize(.mini)
        }
    }
}

/// Current video resolution, shown next to the live badge. Rides the same
/// auto-hide as the rest of the control bar.
private struct QualityBadge: View {
    @ObservedObject var model: PlayerModel

    private var label: String? {
        let parts = model.stats.resolution.split(separator: "×")
        guard parts.count == 2, let height = Int(parts[1]) else { return nil }
        return "\(height)p"
    }

    var body: some View {
        if let label {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 4))
                .help("Resolução do vídeo — \(model.stats.resolution)")
        }
    }
}

/// Progress bar for a film or an episode.
///
/// A live channel has no end to slide towards, so this only exists for a file —
/// and for a file it is the whole point: nobody watches two hours without
/// jumping back over the bit they missed.
private struct ScrubBar: View {
    @ObservedObject var model: PlayerModel

    var body: some View {
        HStack(spacing: 8) {
            Text(relogio(model.position))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.75))
            Slider(value: Binding(
                get: { model.position },
                set: { model.seek(to: $0) }),
                   in: 0...max(model.duration, 1),
                   onEditingChanged: { arrastando in model.scrubbing = arrastando })
                .frame(maxWidth: .infinity)
                .controlSize(.small)
                .tint(Tema.acento)
            Text(relogio(model.duration))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
        }
        .help("Arraste para avançar ou voltar")
    }

    private func relogio(_ segundos: Double) -> String {
        guard segundos.isFinite, segundos >= 0 else { return "--:--" }
        let total = Int(segundos)
        let horas = total / 3600, minutos = (total % 3600) / 60, resto = total % 60
        return horas > 0
            ? String(format: "%d:%02d:%02d", horas, minutos, resto)
            : String(format: "%02d:%02d", minutos, resto)
    }
}

/// Which of the channel's sources is on air, and whether it is still loading.
///
/// A channel carries several sources and the proxy walks down the list on its
/// own when one fails. Without showing it, a picture that takes a while looks
/// exactly like one that never comes, and a viewer has no way of telling that
/// the first source died and the second one saved the channel.
private struct SourceBadge: View {
    @ObservedObject var model: PlayerModel

    var body: some View {
        if model.sourceCount > 0, !model.sourceHost.isEmpty {
            HStack(spacing: 5) {
                if model.isLoadingSource {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.6)
                        .frame(width: 9, height: 9)
                } else {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 5, height: 5)
                }
                Text(rotulo)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .lineLimit(1)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 4))
            .help(ajuda)
        }
    }

    private var rotulo: String {
        // Canal 24h: a temporada no ar no lugar do número da fonte.
        if let canal = model.selectedChannel, model.sourceIndex < canal.variants.count,
           let nome = canal.variants[model.sourceIndex].nome {
            return model.isLoadingSource ? "carregando \(nome) · \(model.sourceHost)" : "\(nome) · \(model.sourceHost)"
        }
        let posicao = "\(model.sourceIndex + 1)/\(model.sourceCount)"
        return model.isLoadingSource
            ? "carregando fonte \(posicao) · \(model.sourceHost)"
            : "fonte \(posicao) · \(model.sourceHost)"
    }

    private var ajuda: String {
        guard let channel = model.selectedChannel,
              model.sourceIndex < channel.variants.count else { return rotulo }
        let url = channel.variants[model.sourceIndex].url.absoluteString
        let estado = model.isLoadingSource ? "Carregando" : "No ar"
        return "\(estado) pela fonte \(model.sourceIndex + 1) de \(model.sourceCount)\n\(url)"
    }
}

/// Google Cast receivers — Chromecast, Google TV boxes, Android TVs. The system
/// AirPlay picker cannot see these, so they get their own menu.
private struct CastMenu: View {
    @ObservedObject var model: PlayerModel
    @ObservedObject private var cast = CastService.shared

    var body: some View {
        Menu {
            if let connected = cast.connected {
                Text("Transmitindo para \(connected.name)")
                Button("Parar transmissão") { cast.disconnect() }
                Divider()
            }
            if cast.devices.isEmpty {
                Text("Procurando aparelhos…")
            } else {
                ForEach(cast.devices) { device in
                    Button(device.label) {
                        guard let link = model.generatedLink,
                              let channel = model.selectedChannel else { return }
                        cast.cast(url: link, title: channel.name, to: device)
                    }
                }
            }
        } label: {
            Image(systemName: cast.connected == nil ? "tv.badge.wifi" : "tv.badge.wifi.fill")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 26)
        .help("Transmitir para Chromecast / Google TV")
        .onAppear { cast.startDiscovery() }
    }
}

private struct LiveBadge: View {
    @ObservedObject var model: PlayerModel

    private var atLive: Bool { model.stats.behindLive < 12 }

    var body: some View {
        Button(action: model.jumpToLive) {
            HStack(spacing: 5) {
                Circle()
                    .fill(atLive ? Color.red : Color.secondary)
                    .frame(width: 7, height: 7)
                Text(atLive ? "AO VIVO" : "VOLTAR AO VIVO")
                    .font(.system(size: 10, weight: .bold))
            }
        }
        .help("Ir para o ponto ao vivo")
    }
}

extension PlayerModel {
    func step0() { step(-1) }
    func step1() { step(1) }
}


/// "Pular abertura" e o cartão do próximo episódio, no canto de baixo.
/// Os tempos vêm do TheIntroDB.
private func rotuloDoAtraso(_ segundos: Double) -> String {
    if segundos == 0 { return "original" }
    return "\(segundos > 0 ? "+" : "−")\(abs(segundos).formatted()) s"
}

/// A legenda do OpenSubtitles, desenhada por cima do vídeo. O texto é escolhido
/// pelo relógio do player, cinco vezes por segundo, sem publicar nada.
private struct LegendaNaTela: View {
    @ObservedObject var model: PlayerModel
    let acimaDosControles: Bool

    var body: some View {
        if model.legendaExt != nil || model.legendaAviso != nil {
            TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                VStack {
                    Spacer()
                    if let aviso = model.legendaAviso {
                        Text(aviso).font(.system(size: 12)).foregroundStyle(.white.opacity(0.8))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(.black.opacity(0.6), in: Capsule())
                    } else if let fala = model.legendaExternaEm(model.player.currentTime().seconds) {
                        Text(fala)
                            .font(.system(size: 26, weight: .medium))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)
                            .shadow(color: .black, radius: 2, x: 0, y: 1)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .frame(maxWidth: 900)
                    }
                }
                .padding(.bottom, acimaDosControles ? 130 : 50)
                .padding(.horizontal, 40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            }
        }
    }
}

private struct PulosNaTela: View {
    @ObservedObject var model: PlayerModel
    let acimaDosControles: Bool

    var body: some View {
        HStack {
            Spacer()
            if let trecho = model.puloNaTela {
                Button(action: model.pularTrecho) {
                    Text(trecho.tipo.rotulo)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 18).padding(.vertical, 11)
                        .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: [])
            } else if let proximo = model.proximoNaTela {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Próximo episódio em \(proximo.resta) s")
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
                    Text("Temporada \(proximo.episodio.temporada) · Episódio \(proximo.episodio.numero)")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    HStack(spacing: 8) {
                        Button { model.tocarProximo() } label: {
                            Text("Assistir agora").font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.return, modifiers: [])
                        Button("Continuar vendo", action: model.dispensarProximo)
                            .keyboardShortcut(.escape, modifiers: [])
                    }
                }
                .padding(16)
                .frame(width: 300, alignment: .leading)
                .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(.trailing, 24)
        .padding(.bottom, acimaDosControles ? 150 : 32)
        .animation(.easeInOut(duration: 0.2), value: acimaDosControles)
    }
}
