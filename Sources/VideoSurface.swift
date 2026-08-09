import SwiftUI
import AppKit
import AVKit
import AVFoundation

/// Video surface backed by an AVPlayerLayer.
///
/// AVPlayerView ships nice controls but exposes no public API to toggle
/// Picture in Picture or full screen programmatically, so the layer is driven
/// directly and paired with our own AVPictureInPictureController.
final class PlayerLayerView: NSView {
    let playerLayer = AVPlayerLayer()
    var onDoubleClick: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        let root = CALayer()
        root.backgroundColor = NSColor.black.cgColor
        layer = root
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = NSColor.black.cgColor
        root.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onDoubleClick?() } else { super.mouseDown(with: event) }
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

    func makeNSView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView(frame: .zero)
        view.playerLayer.player = player
        view.playerLayer.videoGravity = gravity
        view.onDoubleClick = onDoubleClick
        onReady(view)
        return view
    }

    func updateNSView(_ view: PlayerLayerView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
        if view.playerLayer.videoGravity != gravity { view.playerLayer.videoGravity = gravity }
        view.onDoubleClick = onDoubleClick
    }
}
