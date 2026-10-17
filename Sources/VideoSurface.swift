import SwiftUI
import AppKit
import AVKit
@preconcurrency import AVFoundation
import Metal
import MetalFX
import QuartzCore
import CoreVideo
import Combine

/// Motor de Super Resolução (Upscaling) nativo para Apple Silicon (M1–M4 Pro/Max).
///
/// Combina o `MTLFXSpatialScaler` (MetalFX da Apple) para reconstrução espacial
/// até 4K (3840×2160) com um passe Metal de Contrast-Adaptive Sharpening (CAS)
/// somente em luminância, com supressão de ruído de compressão e trava anti-halo.
@MainActor
final class MetalFXVideoEngine {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private var textureCache: CVMetalTextureCache?

    private var spatialScaler: MTLFXSpatialScaler?
    private var upscaledTexture: MTLTexture?
    private var lastSrcWidth: Int = 0
    private var lastSrcHeight: Int = 0
    private var lastOutWidth: Int = 0
    private var lastOutHeight: Int = 0

    init?() {
        guard let dev = MTLCreateSystemDefaultDevice(),
              let queue = dev.makeCommandQueue() else { return nil }
        self.device = dev
        self.commandQueue = queue

        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, dev, nil, &cache)
        self.textureCache = cache

        guard let library = try? dev.makeLibrary(source: Self.metalShaderSource, options: nil),
              let vertexFn = library.makeFunction(name: "saimoVertex"),
              let fragmentFn = library.makeFunction(name: "saimoCasFragment") else {
            return nil
        }

        let pipeDesc = MTLRenderPipelineDescriptor()
        pipeDesc.vertexFunction = vertexFn
        pipeDesc.fragmentFunction = fragmentFn
        pipeDesc.colorAttachments[0].pixelFormat = .bgra8Unorm

        guard let pso = try? dev.makeRenderPipelineState(descriptor: pipeDesc) else {
            return nil
        }
        self.pipelineState = pso

        let sampDesc = MTLSamplerDescriptor()
        sampDesc.minFilter = .linear
        sampDesc.magFilter = .linear
        sampDesc.sAddressMode = .clampToEdge
        sampDesc.tAddressMode = .clampToEdge
        guard let samp = dev.makeSamplerState(descriptor: sampDesc) else { return nil }
        self.sampler = samp
    }

    private func ensureScaler(srcW: Int, srcH: Int, mode: String) -> (MTLFXSpatialScaler, MTLTexture)? {
        let targetW: Int
        let targetH: Int
        if mode == "4k" {
            // Super Resolução Ultra: escala vídeos HD/FHD para 4K UHD (3840×2160)
            targetW = max(srcW, 3840)
            targetH = max(srcH, 2160)
        } else {
            // Nitidez HD: escala 720p/SD para Full HD (1920×1080) ou 1080p para QHD (2560×1440)
            if srcH < 1080 {
                targetW = 1920
                targetH = 1080
            } else {
                targetW = max(srcW, 2560)
                targetH = max(srcH, 1440)
            }
        }

        if let scaler = spatialScaler,
           let outTex = upscaledTexture,
           lastSrcWidth == srcW,
           lastSrcHeight == srcH,
           lastOutWidth == targetW,
           lastOutHeight == targetH {
            return (scaler, outTex)
        }

        guard MTLFXSpatialScalerDescriptor.supportsDevice(device) else { return nil }
        let desc = MTLFXSpatialScalerDescriptor()
        desc.inputWidth = srcW
        desc.inputHeight = srcH
        desc.outputWidth = targetW
        desc.outputHeight = targetH
        desc.colorTextureFormat = .bgra8Unorm
        desc.outputTextureFormat = .bgra8Unorm
        desc.colorProcessingMode = .perceptual

        guard let scaler = desc.makeSpatialScaler(device: device) else { return nil }

        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: targetW,
            height: targetH,
            mipmapped: false
        )
        texDesc.storageMode = .private
        texDesc.usage = scaler.outputTextureUsage.union([.shaderRead, .renderTarget])

        guard let outTex = device.makeTexture(descriptor: texDesc) else { return nil }

        self.spatialScaler = scaler
        self.upscaledTexture = outTex
        self.lastSrcWidth = srcW
        self.lastSrcHeight = srcH
        self.lastOutWidth = targetW
        self.lastOutHeight = targetH
        return (scaler, outTex)
    }

    func render(
        pixelBuffer: CVPixelBuffer,
        into metalLayer: CAMetalLayer,
        gravity: AVLayerVideoGravity,
        mode: String
    ) -> Bool {
        guard let cache = textureCache else { return false }
        let srcW = CVPixelBufferGetWidth(pixelBuffer)
        let srcH = CVPixelBufferGetHeight(pixelBuffer)
        guard srcW > 16, srcH > 16 else { return false }

        var cvTex: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            cache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            srcW,
            srcH,
            0,
            &cvTex
        )
        guard status == kCVReturnSuccess,
              let cvTex,
              let inputTexture = CVMetalTextureGetTexture(cvTex),
              let drawable = metalLayer.nextDrawable(),
              let cmd = commandQueue.makeCommandBuffer() else {
            return false
        }

        // Estágio 1: Reconstrução Espacial Hardware Apple MetalFX
        let sourceForCas: MTLTexture
        if let (scaler, outTex) = ensureScaler(srcW: srcW, srcH: srcH, mode: mode) {
            scaler.colorTexture = inputTexture
            scaler.outputTexture = outTex
            scaler.inputContentWidth = srcW
            scaler.inputContentHeight = srcH
            scaler.encode(commandBuffer: cmd)
            sourceForCas = outTex
        } else {
            sourceForCas = inputTexture
        }

        // Estágio 2: Renderização com proporção exata + CAS em luminância (sem halos e sem alterar cores)
        let drawW = Float(drawable.texture.width)
        let drawH = Float(drawable.texture.height)
        guard drawW > 0, drawH > 0 else { return false }

        let viewAspect = drawW / drawH
        let videoAspect = Float(srcW) / Float(srcH)
        var scaleX: Float = 1.0
        var scaleY: Float = 1.0

        if gravity == .resizeAspectFill {
            if videoAspect > viewAspect {
                scaleX = videoAspect / viewAspect
            } else {
                scaleY = viewAspect / videoAspect
            }
        } else {
            if videoAspect > viewAspect {
                scaleY = viewAspect / videoAspect
            } else {
                scaleX = videoAspect / viewAspect
            }
        }

        let passDesc = MTLRenderPassDescriptor()
        passDesc.colorAttachments[0].texture = drawable.texture
        passDesc.colorAttachments[0].loadAction = .clear
        passDesc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        passDesc.colorAttachments[0].storeAction = .store

        guard let enc = cmd.makeRenderCommandEncoder(descriptor: passDesc) else { return false }
        enc.setRenderPipelineState(pipelineState)
        enc.setFragmentTexture(sourceForCas, index: 0)
        enc.setFragmentSamplerState(sampler, index: 0)

        var vertexParams = SIMD2<Float>(scaleX, scaleY)
        enc.setVertexBytes(&vertexParams, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)

        let sharpness: Float = (mode == "4k") ? 0.55 : 0.32
        var fragParams = SIMD4<Float>(
            1.0 / Float(sourceForCas.width),
            1.0 / Float(sourceForCas.height),
            sharpness,
            (mode == "4k") ? 1.0 : 0.0
        )
        enc.setFragmentBytes(&fragParams, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)

        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        enc.endEncoding()

        cmd.present(drawable)
        cmd.commit()
        return true
    }

    private static let metalShaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOut {
        float4 position [[position]];
        float2 uv;
    };

    vertex VertexOut saimoVertex(
        uint vid [[vertex_id]],
        constant float2 &scale [[buffer(0)]]
    ) {
        const float2 positions[4] = {
            float2(-1.0, -1.0),
            float2( 1.0, -1.0),
            float2(-1.0,  1.0),
            float2( 1.0,  1.0)
        };
        const float2 uvs[4] = {
            float2(0.0, 1.0),
            float2(1.0, 1.0),
            float2(0.0, 0.0),
            float2(1.0, 0.0)
        };
        VertexOut out;
        out.position = float4(positions[vid] * scale, 0.0, 1.0);
        out.uv = uvs[vid];
        return out;
    }

    inline float luma(float3 rgb) {
        return dot(rgb, float3(0.2126, 0.7152, 0.0722));
    }

    // Contrast-Adaptive Sharpening (CAS) puro em luminância (Rec.709):
    // - Não altera matiz, saturação nem gama;
    // - Ignora áreas lisas/ruído de compressão (noise floor);
    // - Trava o resultado entre o mínimo e máximo locais (zero halos brancos/pretos).
    fragment float4 saimoCasFragment(
        VertexOut in [[stage_in]],
        texture2d<float> tex [[texture(0)]],
        sampler samp [[sampler(0)]],
        constant float4 &params [[buffer(0)]]
    ) {
        float2 uv = in.uv;
        float2 px = params.xy;
        float strength = params.z;

        float3 c  = tex.sample(samp, uv).rgb;
        float3 n  = tex.sample(samp, uv + float2( 0.0, -px.y)).rgb;
        float3 s  = tex.sample(samp, uv + float2( 0.0,  px.y)).rgb;
        float3 w  = tex.sample(samp, uv + float2(-px.x,  0.0)).rgb;
        float3 e  = tex.sample(samp, uv + float2( px.x,  0.0)).rgb;
        float3 nw = tex.sample(samp, uv + float2(-px.x, -px.y)).rgb;
        float3 ne = tex.sample(samp, uv + float2( px.x, -px.y)).rgb;
        float3 sw = tex.sample(samp, uv + float2(-px.x,  px.y)).rgb;
        float3 se = tex.sample(samp, uv + float2( px.x,  px.y)).rgb;

        float lc  = luma(c);
        float ln  = luma(n);
        float ls  = luma(s);
        float lw  = luma(w);
        float le  = luma(e);
        float lnw = luma(nw);
        float lne = luma(ne);
        float lsw = luma(sw);
        float lse = luma(se);

        float mnL = min(lc, min(min(ln, ls), min(lw, le)));
        float mxL = max(lc, max(max(ln, ls), max(lw, le)));
        float mnDiag = min(min(lnw, lne), min(lsw, lse));
        float mxDiag = max(max(lnw, lne), max(lsw, lse));
        mnL = 0.5 * (mnL + min(mnL, mnDiag));
        mxL = 0.5 * (mxL + max(mxL, mxDiag));

        float contrast = mxL - mnL;
        // Supressão de ruído de compressão em áreas planas (pele, céu, gramado)
        float noiseGate = smoothstep(0.015, 0.055, contrast);

        // Peso adaptativo CAS: menos agressivo em bordas que já têm contraste máximo
        float amp = sqrt(clamp(min(mnL, 1.0 - mxL) / max(mxL, 0.0001), 0.0, 1.0));
        float weight = -1.0 / mix(9.5, 5.2, strength);
        float wL = amp * weight * noiseGate;

        float avgCross = (ln + ls + lw + le);
        float sharpenedL = ((avgCross * wL + lc) / (1.0 + 4.0 * wL));
        // Anti-ringing: impede que qualquer pixel ultrapasse o envelope local
        sharpenedL = clamp(sharpenedL, mnL, mxL);

        float delta = sharpenedL - lc;
        float3 outRGB = clamp(c + delta, 0.0, 1.0);
        return float4(outRGB, 1.0);
    }
    """
}

/// Video surface backed by an AVPlayerLayer + optional MetalFX Super-Resolution layer.
///
/// AVPlayerView ships nice controls but exposes no public API to toggle
/// Picture in Picture or full screen programmatically, so the layer is driven
/// directly and paired with our own AVPictureInPictureController.
@MainActor
final class PlayerLayerView: NSView {
    let playerLayer = AVPlayerLayer()
    private let metalLayer = CAMetalLayer()
    private var engine: MetalFXVideoEngine?
    private var videoOutput: AVPlayerItemVideoOutput?
    private weak var attachedItem: AVPlayerItem?
    private var itemCancellable: AnyCancellable?
    private var renderTimer: Timer?
    private var lastPixelBuffer: CVPixelBuffer?

    var onDoubleClick: (() -> Void)?
    /// Clique simples: na multi tela é o que escolhe a tela ativa.
    var onClick: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
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

        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.isOpaque = true
        metalLayer.backgroundColor = NSColor.black.cgColor
        metalLayer.colorspace = CGColorSpace(name: CGColorSpace.itur_709)
        metalLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        metalLayer.isHidden = true
        root.addSublayer(metalLayer)

        aplicarUpscaling()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(upscalingMudou),
            name: Preferencias.upscalingMudou,
            object: nil
        )
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    @objc private func upscalingMudou() {
        aplicarUpscaling()
    }

    func bindPlayer(_ player: AVPlayer) {
        if playerLayer.player !== player {
            playerLayer.player = player
            itemCancellable = player.publisher(for: \.currentItem, options: [.initial, .new])
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    self?.sincronizarOutput()
                }
        }
        sincronizarOutput()
    }

    func aplicarUpscaling() {
        // Nunca usa CALayer.filters: no Apple Silicon eles forçam rasterização
        // dupla no WindowServer e criam halos artificiais.
        playerLayer.filters = nil
        layer?.filters = nil

        let modo = Preferencias.upscaling
        if modo == "off" {
            pararMotorMetal()
            return
        }

        if engine == nil {
            engine = MetalFXVideoEngine()
        }
        sincronizarOutput()
        iniciarLoopSeNecessario()
        desenharQuadroMetalFX(forcarRedesenho: true)
    }

    private func sincronizarOutput() {
        let modo = Preferencias.upscaling
        guard modo != "off", let item = playerLayer.player?.currentItem else {
            removerOutputAtual()
            metalLayer.isHidden = true
            return
        }
        if attachedItem === item, videoOutput != nil { return }
        removerOutputAtual()

        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
        ]
        let out = AVPlayerItemVideoOutput(pixelBufferAttributes: attrs)
        item.add(out)
        videoOutput = out
        attachedItem = item
        lastPixelBuffer = nil
        // Mantém o playerLayer visível até o primeiro quadro MetalFX ficar pronto
        metalLayer.isHidden = true
    }

    private func removerOutputAtual() {
        if let out = videoOutput, let item = attachedItem {
            item.remove(out)
        }
        videoOutput = nil
        attachedItem = nil
        lastPixelBuffer = nil
    }

    private func iniciarLoopSeNecessario() {
        guard renderTimer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.desenharQuadroMetalFX()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        renderTimer = t
    }

    private func pararMotorMetal() {
        renderTimer?.invalidate()
        renderTimer = nil
        removerOutputAtual()
        metalLayer.isHidden = true
    }

    private func desenharQuadroMetalFX(forcarRedesenho: Bool = false) {
        let modo = Preferencias.upscaling
        guard modo != "off",
              let engine,
              let player = playerLayer.player,
              !player.isExternalPlaybackActive,
              let out = videoOutput else {
            metalLayer.isHidden = true
            return
        }

        if attachedItem !== player.currentItem {
            sincronizarOutput()
        }

        var bufferParaDesenhar: CVPixelBuffer?
        let itemTime = out.itemTime(forHostTime: CACurrentMediaTime())
        if itemTime.isValid, out.hasNewPixelBuffer(forItemTime: itemTime),
           let novo = out.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) {
            lastPixelBuffer = novo
            bufferParaDesenhar = novo
        } else if forcarRedesenho {
            bufferParaDesenhar = lastPixelBuffer
        }

        guard let pb = bufferParaDesenhar else { return }

        if let cs = CVImageBufferGetColorSpace(pb)?.takeUnretainedValue(),
           metalLayer.colorspace !== cs {
            metalLayer.colorspace = cs
        }

        atualizarTamanhoDrawable()
        if engine.render(pixelBuffer: pb, into: metalLayer, gravity: playerLayer.videoGravity, mode: modo) {
            if metalLayer.isHidden {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                metalLayer.isHidden = false
                CATransaction.commit()
            }
        }
    }

    private func atualizarTamanhoDrawable() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        if metalLayer.contentsScale != scale {
            metalLayer.contentsScale = scale
        }
        let w = max(bounds.width * scale, 1)
        let h = max(bounds.height * scale, 1)
        let target = CGSize(width: w, height: h)
        if metalLayer.drawableSize != target {
            metalLayer.drawableSize = target
        }
    }

    override var isFlipped: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            renderTimer?.invalidate()
            renderTimer = nil
        } else if Preferencias.upscaling != "off" {
            iniciarLoopSeNecessario()
        }
    }

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
        metalLayer.frame = bounds
        atualizarTamanhoDrawable()
        CATransaction.commit()
        if !metalLayer.isHidden {
            desenharQuadroMetalFX(forcarRedesenho: true)
        }
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
        view.playerLayer.videoGravity = gravity
        view.bindPlayer(player)
        view.onDoubleClick = onDoubleClick
        view.onClick = onClick
        onReady(view)
        return view
    }

    func updateNSView(_ view: PlayerLayerView, context: Context) {
        view.bindPlayer(player)
        if view.playerLayer.videoGravity != gravity {
            view.playerLayer.videoGravity = gravity
        }
        view.onDoubleClick = onDoubleClick
        view.onClick = onClick
    }
}
