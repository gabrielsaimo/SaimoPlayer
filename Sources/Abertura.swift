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
///
/// Esta parte não desenha nada: só acha a janela assim que ela existe e põe a
/// abertura por cima de tudo o que há nela — barra de título, controles do
/// player e o que mais o SwiftUI montar. Por dentro da árvore do SwiftUI ela
/// ficava atrás da barra de controles.
struct Abertura: NSViewRepresentable {
    let aoTerminar: () -> Void

    func makeNSView(context: Context) -> AchaJanela {
        let view = AchaJanela()
        view.aoAchar = { janela in AberturaView.cobrir(janela, aoTerminar: aoTerminar) }
        return view
    }

    func updateNSView(_ nsView: AchaJanela, context: Context) {}
}

final class AchaJanela: NSView {
    var aoAchar: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window, let aoAchar else { return }
        self.aoAchar = nil
        aoAchar(window)
    }
}

final class AberturaView: NSView {
    private var aoTerminar: (() -> Void)?

    private let camada = AVPlayerLayer()
    private var player: AVPlayer?
    private var observadorFim: NSObjectProtocol?
    private var monitorTeclas: Any?
    private var terminou = false

    /// Põe a abertura sobre a janela inteira, acima da barra de título.
    static func cobrir(_ janela: NSWindow, aoTerminar: @escaping () -> Void) {
        janela.backgroundColor = corDaAbertura
        guard let moldura = janela.contentView?.superview else {
            aoTerminar()
            return
        }
        let view = AberturaView(frame: moldura.bounds)
        view.autoresizingMask = [.width, .height]
        view.aoTerminar = aoTerminar
        moldura.addSubview(view, positioned: .above, relativeTo: nil)
        view.iniciar()
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        let raiz = CALayer()
        raiz.backgroundColor = corDaAbertura.cgColor
        layer = raiz
        camada.videoGravity = .resizeAspectFill
        camada.backgroundColor = corDaAbertura.cgColor
        camada.frame = bounds
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

    private func iniciar() {
        // O canal já abre por baixo; sem som até a abertura sair.
        PlayerModel.shared.silenciadoPelaAbertura = true
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

    // Todo clique na janela é dela enquanto está na tela; depois, nenhum.
    override func hitTest(_ point: NSPoint) -> NSView? {
        terminou ? nil : self
    }

    override func mouseDown(with event: NSEvent) { fim() }
    override func rightMouseDown(with event: NSEvent) { fim() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func fim() {
        guard !terminou else { return }
        terminou = true
        player?.pause()
        if let observadorFim { NotificationCenter.default.removeObserver(observadorFim) }
        observadorFim = nil
        if let monitorTeclas { NSEvent.removeMonitor(monitorTeclas) }
        monitorTeclas = nil
        PlayerModel.shared.silenciadoPelaAbertura = false
        aoTerminar?()
        aoTerminar = nil
        NSAnimationContext.runAnimationGroup({ contexto in
            contexto.duration = 0.25
            contexto.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                self.window?.backgroundColor = .windowBackgroundColor
                self.camada.player = nil
                self.player = nil
                self.removeFromSuperview()
            }
        })
    }
}
