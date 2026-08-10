import SwiftUI
import AVKit
import AppKit

struct ContentView: View {
    @ObservedObject private var model = PlayerModel.shared
    @State private var controlsVisible = true
    @State private var hideWork: DispatchWorkItem?

    var body: some View {
        stage
            .frame(minWidth: 720, minHeight: 460)
            .sheet(isPresented: $model.showGuide) {
                EPGGuideView(model: model)
            }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button { model.detachedList.toggle() } label: {
                        Image(systemName: "sidebar.leading")
                    }
                    .help("Mostrar ou ocultar a lista de canais (⇧⌘L)")
                }
            }
            .onAppear {
                if model.detachedList { SidebarWindowController.shared.open(model: model) }
            }
            .onChange(of: model.detachedList) { _, detached in
                if detached {
                    SidebarWindowController.shared.open(model: model)
                } else {
                    SidebarWindowController.shared.close()
                }
            }
    }

    // MARK: - Stage

    private var stage: some View {
        ZStack(alignment: .bottom) {
            VideoSurface(
                player: model.player,
                gravity: model.fillScreen ? .resizeAspectFill : .resizeAspect,
                onReady: { model.attach(surface: $0) },
                onDoubleClick: { model.toggleFullScreen() })
                .background(Color.black)
                .ignoresSafeArea()

            if model.showStats {
                statsOverlay
                    .opacity(controlsVisible ? 1 : 0)
                    .animation(.easeInOut(duration: 0.22), value: controlsVisible)
            }

            VStack(spacing: 8) {
                NowPlayingStrip(model: model)
                ControlBar(model: model)
            }
                .padding(16)
                .opacity(controlsVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.22), value: controlsVisible)
                .allowsHitTesting(controlsVisible)
        }
        .background(Color.black)
        .onContinuousHover { phase in
            switch phase {
            case .active: revealControls()
            case .ended: scheduleHide(after: 0.6)
            }
        }
        .onAppear { scheduleHide(after: 3) }
        .navigationTitle(model.selectedChannel?.name ?? "Saimo TV")
        .toolbar(removing: .title)
        .toolbarBackground(.hidden, for: .windowToolbar)
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
        .padding(10)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
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

    var body: some View {
        HStack(spacing: 14) {
            Button(action: model.togglePlayPause) {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 22)
            }
            .help(model.isPlaying ? "Pausar (Espaço)" : "Tocar (Espaço)")

            Button(action: model.step0) {
                Image(systemName: "backward.end.fill")
            }
            .help("Canal anterior")

            Button(action: model.step1) {
                Image(systemName: "forward.end.fill")
            }
            .help("Próximo canal")

            LiveBadge(model: model)

            QualityBadge(model: model)

            volume

            Spacer(minLength: 8)

            if !model.audioChoices.isEmpty || !model.subtitleChoices.isEmpty {
                Menu {
                    if !model.audioChoices.isEmpty {
                        Section("Áudio") {
                            ForEach(model.audioChoices) { c in
                                Button { model.selectAudio(c.id) } label: {
                                    Label(c.title, systemImage: model.selectedAudio == c.id ? "checkmark" : "")
                                }
                            }
                        }
                    }
                    if !model.subtitleChoices.isEmpty {
                        Section("Legendas") {
                            ForEach(model.subtitleChoices) { c in
                                Button { model.selectSubtitle(c.id) } label: {
                                    Label(c.title, systemImage: model.selectedSubtitle == c.id ? "checkmark" : "")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "captions.bubble")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 26)
                .help("Áudio e legendas")
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

            Button(action: model.toggleFullScreen) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .help("Tela cheia (F)")
        }
        .font(.system(size: 14))
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .environment(\.colorScheme, .dark)
        .shadow(color: .black.opacity(0.35), radius: 14, y: 4)
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

/// What is on air now, plus what follows — rides the same auto-hide as the
/// controls so it never sits on top of the picture.
private struct NowPlayingStrip: View {
    @ObservedObject var model: PlayerModel
    @ObservedObject private var epg = EPGService.shared
    @ObservedObject private var posters = LogoLoader.shared

    var body: some View {
        if let channel = model.selectedChannel,
           let onAir = epg.nowNext(for: channel, at: epg.clock) {
            HStack(spacing: 12) {
                if let poster = onAir.current.poster, let image = posters.image(for: poster) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 66, height: 45)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(onAir.current.title)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        Text("faltam \(onAir.remainingMinutes) min")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    if let detail = onAir.current.shortDetail {
                        Text(detail)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                    if let next = onAir.next {
                        Text("a seguir · \(next.title)")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 12)
                Button { model.showGuide = true } label: {
                    Label("Guia", systemImage: "calendar.badge.clock")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .help("Programação completa (⌘G)")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .environment(\.colorScheme, .dark)
            .overlay(alignment: .bottomLeading) {
                GeometryReader { geo in
                    Capsule()
                        .fill(Color.red)
                        .frame(width: geo.size.width * onAir.progress, height: 2)
                        .offset(y: geo.size.height - 2)
                }
            }
            .shadow(color: .black.opacity(0.3), radius: 10, y: 3)
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
