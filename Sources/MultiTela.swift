import SwiftUI
import AVFoundation

/// Qual das duas telas da multi tela.
enum LadoDaTela {
    case principal, segunda
}

/// A segunda tela da multi tela: um canal ao vivo ao lado do principal.
///
/// O principal continua sendo o PlayerModel inteiro, com guia, PiP e
/// estatísticas. Esta é o mínimo para um canal ficar no ar: abre pelo mesmo
/// proxy, desce para a fonte seguinte enquanto a atual não entrega imagem e
/// reconecta com espera crescente depois que já tocou — a mesma regra do
/// principal, sem o resto.
@MainActor
final class SegundaTela: ObservableObject {
    @Published private(set) var canal: Channel?
    @Published private(set) var carregando = false
    @Published private(set) var fonte = 0
    @Published private(set) var status = ""

    let player = AVPlayer()

    private var observadores: [NSKeyValueObservation] = []
    private var avisos: [NSObjectProtocol] = []
    private var vigia: Timer?
    /// Muda a cada abertura e a cada parada: uma reconexão agendada que chega
    /// depois disso é de um canal que já saiu da tela.
    private var geracao = 0
    private var tocouDesdeAbertura = false
    private var fontesTentadas = 0
    private var tentativas = 0
    private var ultimoRelogio: Double = -1
    private var paradoDesde: Date?

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        // AirPlay e Chromecast ficam com a tela principal.
        player.allowsExternalPlayback = false
    }

    func tocar(_ novo: Channel) {
        canal = novo
        fontesTentadas = 0
        tentativas = 0
        tocouDesdeAbertura = false
        Log.shared.write("multi tela: abrindo \(novo.name)")
        abrir()
    }

    func parar() {
        geracao += 1
        vigia?.invalidate(); vigia = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        desmontarObservadores()
        canal = nil
        carregando = false
        status = ""
    }

    func aplicarSom(volume: Double, mudo: Bool) {
        player.volume = Float(volume)
        player.isMuted = mudo
    }

    func irAoVivo() {
        guard player.currentItem != nil else { return }
        player.seek(to: .positiveInfinity)
        player.play()
    }

    private func abrir() {
        guard let canal else { return }
        geracao += 1
        desmontarObservadores()
        let asset = AVURLAsset(url: ProxyServer.shared.link(for: canal), options: [
            "AVURLAssetHTTPHeaderFieldsKey": [
                "User-Agent": Upstream.userAgent,
                "Accept": "*/*",
            ]
        ])
        let item = AVPlayerItem(asset: asset)
        switch Preferencias.zeroDelay {
        case "equilibrado":
            item.preferredForwardBufferDuration = 2.5
            item.automaticallyPreservesTimeOffsetFromLive = true
            item.configuredTimeOffsetFromLive = CMTime(seconds: 4.0, preferredTimescale: 600)
        case "agressivo":
            item.preferredForwardBufferDuration = 1.2
            item.automaticallyPreservesTimeOffsetFromLive = true
            item.configuredTimeOffsetFromLive = CMTime(seconds: 2.0, preferredTimescale: 600)
        default:
            item.preferredForwardBufferDuration = 6.0
            item.automaticallyPreservesTimeOffsetFromLive = false
            item.configuredTimeOffsetFromLive = .invalid
        }

        observadores.append(item.observe(\.status, options: [.new]) { [weak self] it, _ in
            let falhou = it.status == .failed
            let motivo = it.error?.localizedDescription ?? "erro desconhecido"
            let pronto = it.status == .readyToPlay
            Task { @MainActor in
                if falhou { self?.falhou(motivo) } else if pronto { self?.ficouPronto() }
            }
        })
        observadores.append(player.observe(\.timeControlStatus, options: [.new]) { [weak self] p, _ in
            let tocando = p.timeControlStatus == .playing
            Task { @MainActor in self?.carregando = !tocando }
        })
        avisos.append(NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.falhou("falha ao reproduzir") }
            })

        ultimoRelogio = -1
        paradoDesde = nil
        carregando = true
        status = "carregando…"
        fonte = ProxyServer.shared.variantIndex(canal)
        player.replaceCurrentItem(with: item)
        player.play()
        vigia?.invalidate()
        vigia = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.vigiar() }
        }
    }

    private func ficouPronto() {
        tocouDesdeAbertura = true
        tentativas = 0
        fontesTentadas = 0
        status = "no ar"
        if Preferencias.zeroDelay != "off" {
            irAoVivo()
        }
    }

    /// A fonte no ar (o proxy pode trocar sozinho) e o relógio do player:
    /// parado tempo demais é queda, como no principal.
    private func vigiar() {
        guard let canal, player.currentItem != nil else { return }
        let indice = ProxyServer.shared.variantIndex(canal)
        if fonte != indice { fonte = indice }

        let agora = player.currentTime().seconds
        if agora.isFinite, agora > ultimoRelogio + 0.25 {
            ultimoRelogio = agora
            paradoDesde = nil
            return
        }
        guard player.timeControlStatus == .waitingToPlayAtSpecifiedRate else {
            paradoDesde = nil
            return
        }
        guard let desde = paradoDesde else { paradoDesde = Date(); return }
        let limite: TimeInterval = tocouDesdeAbertura ? 30 : 8
        guard Date().timeIntervalSince(desde) > limite else { return }
        paradoDesde = nil
        falhou(tocouDesdeAbertura ? "travado sem dados" : "fonte não entregou imagem")
    }

    private func falhou(_ motivo: String) {
        guard let canal else { return }
        let esta = geracao

        // Antes da primeira imagem o problema é a fonte: desce para a seguinte.
        if !tocouDesdeAbertura, canal.variants.count > 1, fontesTentadas + 1 < canal.variants.count {
            fontesTentadas += 1
            let proxima = (ProxyServer.shared.variantIndex(canal) + 1) % canal.variants.count
            ProxyServer.shared.forceVariant(canal, proxima)
            status = "tentando a fonte \(proxima + 1) de \(canal.variants.count)…"
            Log.shared.write("multi tela: \(canal.name): \(motivo) — indo para a fonte \(proxima + 1)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self, self.geracao == esta else { return }
                self.abrir()
            }
            return
        }

        tentativas += 1
        guard tentativas <= 8 else {
            status = "falhou: \(motivo)"
            carregando = false
            return
        }
        let espera = min(pow(1.6, Double(tentativas)), 20)
        status = "reconectando (\(tentativas))…"
        Log.shared.write("multi tela: \(canal.name): \(motivo) — reconectando")
        DispatchQueue.main.asyncAfter(deadline: .now() + espera) { [weak self] in
            guard let self, self.geracao == esta else { return }
            self.abrir()
        }
    }

    private func desmontarObservadores() {
        observadores.forEach { $0.invalidate() }
        observadores.removeAll()
        avisos.forEach { NotificationCenter.default.removeObserver($0) }
        avisos.removeAll()
    }
}

extension PlayerModel {
    /// O canal da tela ativa: é o que a lista marca e o que a faixa de baixo
    /// descreve.
    var canalAtivo: Channel? {
        multiTela && segundaAtiva ? segunda.canal : selectedChannel
    }

    /// A seleção que a lista de canais mostra e muda: a da tela ativa.
    var selecaoDaLista: UUID? {
        multiTela && segundaAtiva ? segunda.canal?.id : selection
    }

    /// Canal escolhido na lista ou no guia. Vai para a tela ativa, e com o
    /// acervo aberto fecha o acervo — escolher um canal é querer assisti-lo.
    func escolherNaLista(_ id: UUID?) {
        guard id != selecaoDaLista else { return }
        if multiTela && segundaAtiva {
            guard let id, let canal = channels.first(where: { $0.id == id }) else { return }
            tocarNaSegunda(canal)
        } else {
            selection = id
        }
        if VodEstado.shared.secao != nil { VodEstado.shared.secao = nil }
    }

    func alternarMultiTela() {
        if multiTela {
            fecharTela(segundaAtiva ? .principal : .segunda)
        } else {
            guard playingFile == nil else { return }
            multiTela = true
            segundaAtiva = true
            applyVolume()
            Log.shared.write("multi tela: aberta")
        }
    }

    func ativarTela(_ lado: LadoDaTela) {
        guard multiTela, segundaAtiva != (lado == .segunda) else { return }
        segundaAtiva = lado == .segunda
        applyVolume()
    }

    func tocarNaSegunda(_ canal: Channel) {
        guard multiTela else { return }
        segundaAtiva = true
        segunda.tocar(canal)
        applyVolume()
    }

    /// Fecha uma das telas e fica só com a outra. Fechar a principal leva o
    /// canal da segunda para ela.
    func fecharTela(_ lado: LadoDaTela) {
        guard multiTela else { return }
        let daSegunda = segunda.canal
        segunda.parar()
        multiTela = false
        segundaAtiva = false
        applyVolume()
        if lado == .principal, let daSegunda, daSegunda.id != selection {
            selection = daSegunda.id
        }
        Log.shared.write("multi tela: fechada")
    }

    /// A lista de canais mudou: se o canal da segunda tela saiu dela, a
    /// segunda tela fecha junto.
    func conferirSegundaTela() {
        guard multiTela, let canal = segunda.canal,
              !channels.contains(where: { $0.id == canal.id }) else { return }
        fecharTela(.segunda)
    }

    /// O acervo abriu: o ao vivo para por inteiro, nas duas telas. Filme ou
    /// episódio no ar continua como estava — só o ao vivo é que para.
    func suspenderAoVivo() {
        if multiTela {
            if let canal = segunda.canal, canal.id != selection { Remuxer.shared.encerrar(canal.id) }
            fecharTela(.segunda)
        }
        guard playingFile == nil, player.currentItem != nil else { return }
        stop()
        if let canal = selectedChannel { Remuxer.shared.encerrar(canal.id) }
        Log.shared.write("ao vivo parado: acervo aberto")
    }

    /// O acervo fechou: volta ao último canal, a menos que um filme tenha
    /// entrado no lugar.
    func retomarAoVivo() {
        guard aoVivoPendente || (playingFile == nil && player.currentItem == nil) else { return }
        play()
    }
}

/// O que vai por cima de cada tela da multi tela: a borda da ativa, o nome do
/// canal com a fonte no ar e o botão de fechar. Na segunda tela ainda vazia,
/// o convite para escolher o canal.
struct MolduraDaTela: View {
    @ObservedObject var model: PlayerModel
    @ObservedObject private var segunda: SegundaTela
    let lado: LadoDaTela
    /// Acompanha os controles: o rótulo some junto com eles.
    let rotuloVisivel: Bool

    init(model: PlayerModel, lado: LadoDaTela, rotuloVisivel: Bool) {
        self.model = model
        self._segunda = ObservedObject(wrappedValue: model.segunda)
        self.lado = lado
        self.rotuloVisivel = rotuloVisivel
    }

    private var ativa: Bool { model.segundaAtiva == (lado == .segunda) }
    private var canal: Channel? { lado == .principal ? model.selectedChannel : segunda.canal }

    var body: some View {
        ZStack {
            if lado == .segunda, segunda.canal == nil { escolha }
            VStack {
                HStack(alignment: .top) {
                    if let canal { rotulo(canal) }
                    Spacer(minLength: 8)
                    Button { model.fecharTela(lado) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 24, height: 24)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Fechar esta tela")
                }
                Spacer()
            }
            .padding(12)
            .opacity(rotuloVisivel || canal == nil ? 1 : 0)
            .allowsHitTesting(rotuloVisivel || canal == nil)
            .animation(.easeInOut(duration: 0.22), value: rotuloVisivel)
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .overlay {
            Rectangle()
                .strokeBorder(ativa ? Tema.acento : Color.clear, lineWidth: 3)
                .allowsHitTesting(false)
        }
    }

    private func rotulo(_ canal: Channel) -> some View {
        HStack(spacing: 6) {
            Image(systemName: ativa && !model.isMuted ? "speaker.wave.2.fill" : "speaker.slash.fill")
                .font(.system(size: 10))
                .frame(width: 14)
            Text(canal.name)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            if carregando {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.6)
                    .frame(width: 9, height: 9)
            }
            Text(fonte(canal))
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .help(ativa ? "Tela ativa: com som, e é ela que a lista troca"
                    : "Clique na tela para ativá-la")
    }

    private var carregando: Bool {
        lado == .principal ? model.isLoadingSource : segunda.carregando
    }

    private func fonte(_ canal: Channel) -> String {
        if lado == .segunda, segunda.status.hasPrefix("falhou") || segunda.status.hasPrefix("tentando")
            || segunda.status.hasPrefix("reconectando") {
            return segunda.status
        }
        let indice = lado == .principal ? model.sourceIndex : segunda.fonte
        return "fonte \(min(indice, canal.variants.count - 1) + 1)/\(canal.variants.count)"
    }

    private var escolha: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.split.2x1")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.white.opacity(0.7))
            Text("Escolha o canal da segunda tela")
                .font(.system(size: 15, weight: .semibold))
            Text("Clique num canal da lista ou escolha aqui.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
            HStack(spacing: 10) {
                Menu("Escolher canal") {
                    ForEach(model.gruposDeCanais, id: \.categoria) { grupo in
                        Menu(grupo.categoria.rawValue) {
                            ForEach(grupo.canais) { canal in
                                Button(canal.name) { model.tocarNaSegunda(canal) }
                            }
                        }
                    }
                }
                .fixedSize()
                if !model.detachedList, !Interface.shared.painelCanais {
                    Button("Mostrar lista") { Interface.shared.painelCanais = true }
                }
            }
        }
        .padding(24)
        .contentShape(Rectangle())
        .onTapGesture { model.ativarTela(.segunda) }
    }
}
