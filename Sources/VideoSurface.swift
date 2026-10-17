import SwiftUI
import AppKit
import AVKit
import AVFoundation
import CoreImage

/// Video surface backed by an AVPlayerLayer.
///
/// AVPlayerView ships nice controls but exposes no public API to toggle
/// Picture in Picture or full screen programmatically, so the layer is driven
/// directly and paired with our own AVPictureInPictureController.
final class PlayerLayerView: NSView {
    let playerLayer = AVPlayerLayer()
    var onDoubleClick: (() -> Void)?
    /// Clique simples: na multi tela é o que escolhe a tela ativa.
    var onClick: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerUsesCoreImageFilters = true
        let root = CALayer()
        root.backgroundColor = NSColor.black.cgColor
        // Na multi tela as duas superfícies ficam lado a lado: o vídeo de uma
        // não pode vazar por cima da outra.
        root.masksToBounds = true
        layer = root
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = NSColor.black.cgColor
        // Camada hospedada não recebe `layout()` em toda mudança de tamanho
        // (entrar em tela cheia, abrir a segunda tela): sem isto o vídeo
        // ficava no tamanho antigo, um cobrindo a janela e o outro pequeno
        // no canto.
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        root.addSublayer(playerLayer)
        aplicarUpscaling()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(upscalingMudou),
            name: Preferencias.upscalingMudou,
            object: nil
        )
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func upscalingMudou() {
        aplicarUpscaling()
    }

    func aplicarUpscaling() {
        let modo = Preferencias.upscaling
        var filtros: [CIFilter] = []
        switch modo {
        case "hd":
            if let sharpen = CIFilter(name: "CISharpenLuminance") {
                sharpen.setDefaults()
                sharpen.setValue(0.65, forKey: kCIInputSharpnessKey)
                sharpen.setValue(1.6, forKey: kCIInputRadiusKey)
                filtros.append(sharpen)
            }
            if let unsharp = CIFilter(name: "CIUnsharpMask") {
                unsharp.setDefaults()
                unsharp.setValue(1.4, forKey: kCIInputRadiusKey)
                unsharp.setValue(0.45, forKey: kCIInputIntensityKey)
                filtros.append(unsharp)
            }
            playerLayer.magnificationFilter = .trilinear
        case "4k":
            if let sharpen = CIFilter(name: "CISharpenLuminance") {
                sharpen.setDefaults()
                sharpen.setValue(1.1, forKey: kCIInputSharpnessKey)
                sharpen.setValue(2.0, forKey: kCIInputRadiusKey)
                filtros.append(sharpen)
            }
            if let unsharp = CIFilter(name: "CIUnsharpMask") {
                unsharp.setDefaults()
                unsharp.setValue(1.8, forKey: kCIInputRadiusKey)
                unsharp.setValue(0.75, forKey: kCIInputIntensityKey)
                filtros.append(unsharp)
            }
            if let color = CIFilter(name: "CIColorControls") {
                color.setDefaults()
                color.setValue(1.035, forKey: kCIInputContrastKey)
                color.setValue(1.03, forKey: kCIInputSaturationKey)
                filtros.append(color)
            }
            playerLayer.magnificationFilter = .trilinear
        default:
            playerLayer.magnificationFilter = .linear
        }
        playerLayer.filters = filtros.isEmpty ? nil : filtros
        layer?.filters = filtros.isEmpty ? nil : filtros
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        ajustarVideo()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        ajustarVideo()
    }

    private func ajustarVideo() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
        } else {
            onClick?()
            super.mouseDown(with: event)
        }
    }
}

/// AirPlay picker. Handing it the player is what lets AVFoundation switch to
/// external playback instead of only mirroring the screen.
struct RoutePicker: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.player = player
        view.isRoutePickerButtonBordered = false
        view.setRoutePickerButtonColor(.white, for: .normal)
        view.setRoutePickerButtonColor(.controlAccentColor, for: .active)
        return view
    }

    func updateNSView(_ view: AVRoutePickerView, context: Context) {
        if view.player !== player { view.player = player }
    }
}

struct VideoSurface: NSViewRepresentable {
    let player: AVPlayer
    let gravity: AVLayerVideoGravity
    let onReady: (PlayerLayerView) -> Void
    let onDoubleClick: () -> Void
    var onClick: (() -> Void)? = nil

    func makeNSView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView(frame: .zero)
        view.playerLayer.player = player
        view.playerLayer.videoGravity = gravity
        view.onDoubleClick = onDoubleClick
        view.onClick = onClick
        onReady(view)
        return view
    }

    func updateNSView(_ view: PlayerLayerView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
        if view.playerLayer.videoGravity != gravity { view.playerLayer.videoGravity = gravity }
        view.onDoubleClick = onDoubleClick
        view.onClick = onClick
    }
}
