import AppKit
import MediaPlayer

/// O que está no ar, para a Central de Controle e os apps de "tocando agora".
///
/// O macOS mostra ali o que cada app declara: título, linha de apoio, imagem e
/// tempo. Antes ia só o nome do canal, sem imagem, e filme e série não iam de
/// jeito nenhum. Agora vai a logo do canal com o programa do guia, e no filme
/// ou episódio a logo do título, a mesma que a TV Box usa (ou a capa, quando o
/// TMDB não tem logo), com duração e posição.
///
/// As logos de canal e de título são brancas sobre transparente: soltas, sumiam
/// no fundo claro da Central. Por isso a imagem é montada num quadrado escuro.
@MainActor
final class TocandoAgora {

    static let shared = TocandoAgora()

    private let centro = MPNowPlayingInfoCenter.default()
    private var info: [String: Any] = [:]
    /// Identifica o que está no ar: uma resposta atrasada de outro título é
    /// descartada, e uma reconexão do mesmo não busca a imagem de novo.
    private var marca = ""
    private var programa = ""
    private var busca: Task<Void, Never>?

    private init() {}

    // MARK: - Ao vivo

    func aoVivo(_ canal: Channel) {
        comandos(arquivo: false)
        let nova = "c:\(canal.id)"
        let arte = nova == marca ? info[MPMediaItemPropertyArtwork] : nil
        if nova != marca { busca?.cancel() }
        marca = nova
        programa = EPGService.shared.nowNext(for: canal)?.current.title ?? ""
        info = [
            MPMediaItemPropertyTitle: canal.name,
            MPMediaItemPropertyArtist: programa.isEmpty ? "Ao vivo" : programa,
            MPMediaItemPropertyAlbumTitle: "Saimo TV",
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
        ]
        if let arte { info[MPMediaItemPropertyArtwork] = arte }
        publicar(tocando: true)
        guard arte == nil, let logo = canal.logo else { return }
        busca = Task { [marca] in
            guard let imagem = await Self.baixar(logo.absoluteString) else { return }
            self.colocar(Self.quadro(logo: imagem), se: marca)
        }
    }

    // MARK: - Filme e episódio

    func arquivo(nome: String, episodio: EpisodioNoAr?) {
        comandos(arquivo: true)
        let nova = episodio.map { "e:\($0.serie)|\($0.temporada)|\($0.numero)" } ?? "f:\(nome)"
        // Reconexão ou troca de fonte do mesmo título: o que já foi montado vale.
        guard nova != marca else { return }
        busca?.cancel()
        marca = nova
        programa = ""
        let titulo = episodio.map { "T\($0.temporada) E\($0.numero)" } ?? Generos.semAno(nome)
        let apoio = episodio.map { Generos.semAno($0.serie) } ?? "Saimo TV"
        info = [
            MPMediaItemPropertyTitle: titulo,
            MPMediaItemPropertyArtist: apoio,
            MPMediaItemPropertyAlbumTitle: "Saimo TV",
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
            MPNowPlayingInfoPropertyIsLiveStream: false,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: 0.0,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
        ]
        publicar(tocando: true)

        let serie = episodio != nil
        let nomeDaFicha = episodio?.serie ?? nome
        busca = Task { [marca] in
            // O nome do episódio vem do TMDB, como no painel de episódios.
            if let ep = episodio {
                let nomes = await Fichas.temporada(ep.serie, ep.temporada)
                if let nomeDoEp = nomes[ep.numero]?.nome, !nomeDoEp.isEmpty {
                    self.trocar(MPMediaItemPropertyTitle, "T\(ep.temporada) E\(ep.numero) · \(nomeDoEp)", se: marca)
                }
            }
            let ficha = await Self.ficha(nomeDaFicha, serie: serie)
            if Task.isCancelled { return }
            // No filme, a linha de apoio é quem dirigiu, como o artista de um disco.
            if !serie, let quem = ficha?.assinatura, !quem.isEmpty {
                self.trocar(MPMediaItemPropertyArtist, quem, se: marca)
            }
            if let logo = await Self.baixar(ficha?.logo) {
                self.colocar(Self.quadro(logo: logo), se: marca)
            } else if let capa = await Self.baixar(ficha?.capa ?? Generos.capa(nomeDaFicha, serie: serie)) {
                self.colocar(capa, se: marca)
            }
        }
    }

    // MARK: - Relógio

    /// A cada segundo do player, e logo depois de pausar ou pular: posição,
    /// duração e velocidade, e no ao vivo o programa que entrou no guia.
    func tique(posicao: Double, duracao: Double, tocando: Bool, velocidade: Float, canal: Channel?) {
        guard !info.isEmpty else { return }
        if let canal {
            let agora = EPGService.shared.nowNext(for: canal)?.current.title ?? ""
            if agora != programa {
                programa = agora
                info[MPMediaItemPropertyArtist] = agora.isEmpty ? "Ao vivo" : agora
            }
        } else {
            if duracao > 0 { info[MPMediaItemPropertyPlaybackDuration] = duracao }
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = max(posicao, 0)
        }
        info[MPNowPlayingInfoPropertyPlaybackRate] = tocando ? Double(velocidade) : 0.0
        publicar(tocando: tocando)
    }

    /// Nada no ar: a Central volta a não mostrar o app.
    func limpar() {
        busca?.cancel()
        busca = nil
        marca = ""
        programa = ""
        info = [:]
        centro.nowPlayingInfo = nil
        centro.playbackState = .stopped
    }

    // MARK: - Comandos

    /// Pausa, posição e avanço só existem no filme e no episódio: ao vivo não
    /// pausa, em nenhum app. O "tocar/pausar" fica ligado no ao vivo e é
    /// ignorado pelo player; desligado, a tecla de mídia do teclado iria parar
    /// noutro app (o Música abre sozinho). Já "anterior/próximo" troca de canal
    /// e, num filme, levaria para o ao vivo no meio da sessão.
    private func comandos(arquivo: Bool) {
        let c = MPRemoteCommandCenter.shared()
        c.pauseCommand.isEnabled = arquivo
        c.changePlaybackPositionCommand.isEnabled = arquivo
        c.skipForwardCommand.isEnabled = arquivo
        c.skipBackwardCommand.isEnabled = arquivo
        c.nextTrackCommand.isEnabled = !arquivo
        c.previousTrackCommand.isEnabled = !arquivo
    }

    // MARK: - Peças

    private func publicar(tocando: Bool) {
        centro.nowPlayingInfo = info
        centro.playbackState = tocando ? .playing : .paused
    }

    private func trocar(_ chave: String, _ valor: String, se quem: String) {
        guard quem == marca, !info.isEmpty else { return }
        info[chave] = valor
        centro.nowPlayingInfo = info
    }

    private func colocar(_ imagem: NSImage, se quem: String) {
        guard quem == marca, !info.isEmpty else { return }
        info[MPMediaItemPropertyArtwork] = Self.arte(Caixa(imagem: imagem))
        centro.nowPlayingInfo = info
    }

    /// A ficha pode estar a caminho por outra tela — e aí `Fichas.de` responde
    /// nulo em vez de pedir de novo. Algumas tentativas cobrem esse intervalo.
    private static func ficha(_ titulo: String, serie: Bool) async -> Ficha? {
        guard Generos.id(titulo, serie: serie) != nil else { return nil }
        for _ in 0..<4 {
            if let ficha = await Fichas.de(titulo, serie: serie) { return ficha }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if Task.isCancelled { return nil }
        }
        return nil
    }

    /// Pelo mesmo carregador das logos da lista, com o mesmo cache em disco.
    private static func baixar(_ endereco: String?) async -> NSImage? {
        guard let endereco, let url = URL(string: endereco) else { return nil }
        for _ in 0..<40 {
            if let imagem = LogoLoader.shared.image(for: url) { return imagem }
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return nil }
        }
        return nil
    }

    /// A logo centrada num quadrado escuro de 600 px, com margem: o "tocando
    /// agora" espera uma imagem quadrada, e as logos são largas e transparentes.
    private static func quadro(logo: NSImage) -> NSImage {
        let lado = 600
        let tamanho = NSSize(width: lado, height: lado)
        let area = NSRect(origin: .zero, size: tamanho)
        guard let mapa = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: lado, pixelsHigh: lado,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return logo }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: mapa)
        NSColor(calibratedWhite: 0.09, alpha: 1).setFill()
        area.fill()
        if logo.size.width > 0, logo.size.height > 0 {
            logo.draw(in: encaixe(logo.size, em: area.insetBy(dx: 60, dy: 60)),
                      from: .zero, operation: .sourceOver, fraction: 1)
        }
        NSGraphicsContext.restoreGraphicsState()

        let imagem = NSImage(size: tamanho)
        imagem.addRepresentation(mapa)
        return imagem
    }

    /// Centraliza `tamanho` em `area`, o maior que couber.
    private static func encaixe(_ tamanho: NSSize, em area: NSRect) -> NSRect {
        let escala = min(area.width / tamanho.width, area.height / tamanho.height)
        let w = tamanho.width * escala, h = tamanho.height * escala
        return NSRect(x: area.midX - w / 2, y: area.midY - h / 2, width: w, height: h)
    }

    /// O sistema pede a imagem de outra fila; ela não muda depois de montada.
    private final class Caixa: @unchecked Sendable {
        let imagem: NSImage
        init(imagem: NSImage) { self.imagem = imagem }
    }

    /// Fora do ator principal de propósito: o pedido da imagem chega de outra
    /// fila, e um bloco preso à principal derrubaria o app ali.
    nonisolated private static func arte(_ caixa: Caixa) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: caixa.imagem.size) { _ in caixa.imagem }
    }
}
