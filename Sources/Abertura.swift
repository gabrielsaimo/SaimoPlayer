import SwiftUI
import AppKit
import AVFoundation

/// Azul-marinho do último quadro da abertura: é a cor da janela enquanto o
/// vídeo carrega, para não piscar preto nem branco antes da arte.
let corDaAbertura = NSColor(srgbRed: 0x0b / 255, green: 0x0f / 255, blue: 0x2a / 255, alpha: 1)

/// A abertura animada do app (`abertura-h.mp4`, copiado para Resources pelo
/// build.sh), na janela inteira, sem som. Clique ou qualquer tecla pula; ao
/// terminar, some num esmaecer curto. Se o vídeo não começar em 1,5 s (arquivo
/// ausente, decodificador ocupado), a abertura sai da frente: o app nunca
/// fica preso nela.
struct Abertura: View {
    let aoTerminar: () -> Void

    @State private var saindo = false

    var body: some View {
        AberturaSuperficie(aoTerminar: sair)
            .background(Color(nsColor: corDaAbertura))
            .opacity(saindo ? 0 : 1)
            .ignoresSafeArea()
    }

    private func sair() {
        guard !saindo else { return }
        withAnimation(.easeOut(duration: 0.25)) { saindo = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) { aoTerminar() }
    }
}

private struct AberturaSuperficie: NSViewRepresentable {
    let aoTerminar: () -> Void

    func makeNSView(context: Context) -> AberturaView {
        let view = AberturaView()
        view.aoTerminar = aoTerminar
        view.iniciar()
        return view
    }

    func updateNSView(_ nsView: AberturaView, context: Context) {
        nsView.aoTerminar = aoTerminar
    }

    static func dismantleNSView(_ nsView: AberturaView, coordinator: ()) {
        nsView.encerrar()
    }
}

final class AberturaView: NSView {
    var aoTerminar: (() -> Void)?

    private let camada = AVPlayerLayer()
    private var player: AVPlayer?
    private var observadorFim: NSObjectProtocol?
    private var monitorTeclas: Any?
    private var terminou = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        let raiz = CALayer()
        raiz.backgroundColor = corDaAbertura.cgColor
        layer = raiz
        camada.videoGravity = .resizeAspectFill
        camada.backgroundColor = corDaAbertura.cgColor
        camada.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        raiz.addSublayer(camada)
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        camada.frame = bounds
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.backgroundColor = corDaAbertura
    }

    func iniciar() {
        guard let url = Bundle.main.url(forResource: "abertura-h", withExtension: "mp4") else {
            DispatchQueue.main.async { self.fim() }
            return
        }
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        camada.player = player
        self.player = player

        observadorFim = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.fim() }
        }
        // Clique é tratado em mouseDown; tecla, aqui, engolida para não
        // chegar ao player nem aos atalhos enquanto a abertura está na tela.
        monitorTeclas = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] evento in
            guard let self else { return evento }
            let engoliu: Bool = MainActor.assumeIsolated {
                guard !self.terminou else { return false }
                self.fim()
                return true
            }
            return engoliu ? nil : evento
        }
        player.play()

        // Rede de segurança: 1,5 s sem o vídeo andar e a abertura sai.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, !self.terminou else { return }
            if item.status != .readyToPlay || player.currentTime().seconds <= 0 {
                self.fim()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        fim()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func fim() {
        guard !terminou else { return }
        terminou = true
        encerrar()
        window?.backgroundColor = .windowBackgroundColor
        aoTerminar?()
    }

    func encerrar() {
        player?.pause()
        if let observadorFim { NotificationCenter.default.removeObserver(observadorFim) }
        observadorFim = nil
        if let monitorTeclas { NSEvent.removeMonitor(monitorTeclas) }
        monitorTeclas = nil
    }
}
