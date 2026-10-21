import SwiftUI
import AppKit

/// Preferências do app gravadas em disco (Application Support/SaimoTV/ajustes.json)
/// e no UserDefaults, garantindo que sobreviva a fechamento e atualização do app.
enum Preferencias {
    private static let chaveAbrirNoCanal = "ajustes.abrirNoCanal"
    private static let chaveUpscaling    = "ajustes.upscaling"
    private static let chaveFillScreen   = "ajustes.fillScreen"
    private static let chaveAlwaysOnTop  = "ajustes.alwaysOnTop"
    private static let chaveShowStats        = "ajustes.showStats"
    private static let chaveIsMuted          = "ajustes.isMuted"
    private static let chaveAudioInteligente = "ajustes.audioInteligente"
    private static let chaveDetachedList     = "ajustes.detachedList"

    static let upscalingMudou        = Notification.Name("SaimoUpscalingMudou")
    static let audioInteligenteMudou = Notification.Name("SaimoAudioInteligenteMudou")

    private static var arquivoURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("SaimoTV", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("ajustes.json")
    }

    private static func lerMapa() -> [String: Any] {
        guard let data = try? Data(contentsOf: arquivoURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return obj
    }

    private static func gravar(_ chave: String, _ valor: Any) {
        var mapa = lerMapa()
        mapa[chave] = valor
        if let data = try? JSONSerialization.data(withJSONObject: mapa, options: [.prettyPrinted]) {
            try? data.write(to: arquivoURL, options: .atomic)
        }
        UserDefaults.standard.set(valor, forKey: chave)
        UserDefaults.standard.synchronize()
    }

    private static func lerBool(_ chave: String, padrao: Bool = false) -> Bool {
        let mapa = lerMapa()
        if let v = mapa[chave] as? Bool { return v }
        if UserDefaults.standard.object(forKey: chave) != nil {
            return UserDefaults.standard.bool(forKey: chave)
        }
        return padrao
    }

    private static func lerString(_ chave: String, padrao: String) -> String {
        let mapa = lerMapa()
        if let v = mapa[chave] as? String { return v }
        return UserDefaults.standard.string(forKey: chave) ?? padrao
    }

    /// Ao abrir o app: a tela inicial (como na TV) ou direto o último canal.
    static var abrirNoCanal: Bool {
        get { lerBool(chaveAbrirNoCanal) }
        set { gravar(chaveAbrirNoCanal, newValue) }
    }

    /// Super Resolução (Upscaling): "off" (padrão), "hd" ou "4k".
    static var upscaling: String {
        get { lerString(chaveUpscaling, padrao: "off") }
        set {
            gravar(chaveUpscaling, newValue)
            NotificationCenter.default.post(name: upscalingMudou, object: nil)
        }
    }

    static var fillScreen: Bool {
        get { lerBool(chaveFillScreen) }
        set { gravar(chaveFillScreen, newValue) }
    }

    static var alwaysOnTop: Bool {
        get { lerBool(chaveAlwaysOnTop) }
        set { gravar(chaveAlwaysOnTop, newValue) }
    }

    static var showStats: Bool {
        get { lerBool(chaveShowStats) }
        set { gravar(chaveShowStats, newValue) }
    }

    static var isMuted: Bool {
        get { lerBool(chaveIsMuted) }
        set { gravar(chaveIsMuted, newValue) }
    }

    /// Áudio Inteligente: normaliza dinamicamente o volume entre diferentes fontes e canais.
    static var audioInteligente: Bool {
        get { lerBool(chaveAudioInteligente, padrao: true) }
        set {
            gravar(chaveAudioInteligente, newValue)
            NotificationCenter.default.post(name: audioInteligenteMudou, object: nil)
        }
    }

    static var detachedList: Bool {
        get { lerBool(chaveDetachedList) }
        set { gravar(chaveDetachedList, newValue) }
    }

    static func rotuloUpscaling(_ modo: String) -> String {
        switch modo {
        case "hd": return "Nitidez HD (MetalFX · 720p → Full HD)"
        case "4k": return "Super Resolução Ultra (MetalFX · até 4K)"
        default:   return "Desligado"
        }
    }
}

/// Os ajustes, em seções como na TV Box: reprodução, geral, canais e sistema.
/// Cada linha diz o que faz e o valor de agora; clicar troca.
struct TelaAjustes: View {
    @ObservedObject var model: PlayerModel
    @ObservedObject private var epg = EPGService.shared
    @ObservedObject private var connect = SaimoConnect.shared
    @ObservedObject private var listas = ListasEstado.shared

    private var versao: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Text("Ajustes")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)

                    secao("Reprodução") {
                        linha("Super Resolução (Upscaling)", Preferencias.rotuloUpscaling(model.upscaling),
                              icone: "sparkles") {
                            switch model.upscaling {
                            case "off": model.upscaling = "hd"
                            case "hd":  model.upscaling = "4k"
                            default:    model.upscaling = "off"
                            }
                        }
                        alternador("Preencher a tela", "Corta as bordas em vez de mostrar faixas pretas",
                                   icone: "rectangle.arrowtriangle.2.outward", valor: $model.fillScreen)
                        alternador("Áudio Inteligente", "Nivela o volume entre canais e fontes diferentes",
                                   icone: "waveform.badge.magnifyingglass", valor: $model.audioInteligente)
                        alternador("Manter à frente", "A janela fica por cima das outras",
                                   icone: "pin.fill", valor: $model.alwaysOnTop)
                        alternador("Estatísticas do vídeo", "Resolução, bitrate e buffer no canto da imagem",
                                   icone: "chart.bar.xaxis", valor: $model.showStats)
                        alternador("Sem som", "Silencia o vídeo e o ao vivo",
                                   icone: "speaker.slash.fill", valor: $model.isMuted)
                    }

                    secao("Geral") {
                        linha("Ao abrir o app", model.abrirNoCanal ? "Ir direto ao último canal" : "Mostrar a tela inicial",
                              icone: "house.fill") {
                            model.abrirNoCanal.toggle()
                        }
                        alternador("Lista de canais em janela separada",
                                   "Uma janela ao lado do player, como antes (⇧⌘L)",
                                   icone: "sidebar.leading", valor: $model.detachedList)
                    }

                    secao("Listas") {
                        linha("Lista de canais", listas.canais ?? "Desligada", icone: "tv") {
                            listas.editando = true
                        }
                        linha("Lista de filmes e séries", listas.filmes ?? "Desligada", icone: "film.stack") {
                            listas.editando = true
                        }
                        linha("Restaurar padrão", "Volta aos endereços de fábrica", icone: "arrow.counterclockwise") {
                            Links.restaurarPadrao()
                        }
                        if listas.canais != nil {
                            linha("Desligar a lista de canais", "Remove canais, rádios e guia deste Mac",
                                  icone: "trash") {
                                Links.aplicar(Links.planejar(canais: "", filmes: listas.filmes ?? ""))
                            }
                        }
                        if listas.filmes != nil {
                            linha("Desligar a lista de filmes e séries", "Remove a lista de filmes e séries deste Mac",
                                  icone: "trash") {
                                Links.aplicar(Links.planejar(canais: listas.canais ?? "", filmes: ""))
                            }
                        }
                    }

                    secao("Canais") {
                        linha("Importar lista .m3u", "Junta os canais de um arquivo à lista", icone: "square.and.arrow.down") {
                            ChannelListActions.importList(into: model)
                        }
                        linha("Adicionar canal por endereço", "Cole o URL de um fluxo .m3u8", icone: "link.badge.plus") {
                            ChannelListActions.addByURL(into: model)
                        }
                        linha("Exportar playlist", "Salva a lista com os links do app", icone: "square.and.arrow.up") {
                            model.exportPlaylist()
                        }
                        linha("Atualizar guia", "Busca a programação de novo (⇧⌘G)", icone: "calendar.badge.clock") {
                            EPGService.shared.refresh(channels: model.channels)
                        }
                        linha("Programação completa", "A grade de todos os canais", icone: "list.bullet.rectangle") {
                            model.showGuide = true
                        }
                    }

                    secao("Saimo Connect") {
                        informacao("Controle pelo celular",
                                   connect.ativo
                                   ? "No app Saimo do celular, toque em Conectar e escolha \"\(connect.nome)\" (\(ProxyServer.lanAddress() ?? "sem rede"):\(SaimoConnect.porta))"
                                   : "Indisponível: a porta \(SaimoConnect.porta) está ocupada",
                                   icone: "iphone.radiowaves.left.and.right")
                        informacao("Celulares autorizados", rotuloDosCelulares, icone: "iphone")
                        linha("Esquecer todos os celulares", "Na próxima conexão o Mac pergunta de novo",
                              icone: "iphone.slash") {
                            connect.esquecerTodos()
                        }
                    }

                    secao("Sistema") {
                        linha("Procurar atualização", "v\(versao)", icone: "arrow.down.circle") {
                            Atualizacao.shared.procurar(manual: true)
                        }
                    }

                    Text("Saimo TV \(versao) para Mac")
                        .font(.system(size: 12))
                        .foregroundStyle(Tema.textoApagado)
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, Tema.margem)
                .padding(.top, Tema.alturaDaBarra + 20)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        }
        .sheet(isPresented: $listas.editando) {
            FormularioListasView { listas.editando = false }
        }
    }

    private var rotuloDosCelulares: String {
        let n = connect.autorizados
        let base = n == 0 ? "Nenhum celular autorizado" : n == 1 ? "1 celular autorizado" : "\(n) celulares autorizados"
        guard !connect.conectados.isEmpty else { return base }
        return base + " · conectado agora: " + connect.conectados.joined(separator: ", ")
    }

    private func informacao(_ titulo: String, _ detalhe: String, icone: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icone)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Tema.acento)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo).font(.system(size: 15, weight: .medium)).foregroundStyle(.white)
                Text(detalhe).font(.system(size: 12)).foregroundStyle(Tema.textoSecundario)
                    .textSelection(.enabled)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func secao<Conteudo: View>(_ titulo: String, @ViewBuilder _ conteudo: () -> Conteudo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titulo.uppercased())
                .font(.system(size: 12, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(Tema.acento)
                .padding(.leading, 6)
            VStack(spacing: 0) { conteudo() }
                .vidroPainel(raio: 18)
        }
    }

    private func linha(_ titulo: String, _ detalhe: String, icone: String,
                       acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            HStack(spacing: 14) {
                Image(systemName: icone)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Tema.acento)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(titulo).font(.system(size: 15, weight: .medium)).foregroundStyle(.white)
                    Text(detalhe).font(.system(size: 12)).foregroundStyle(Tema.textoSecundario)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(LinhaSobMouse())
    }

    private func alternador(_ titulo: String, _ detalhe: String, icone: String,
                            valor: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icone)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Tema.acento)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo).font(.system(size: 15, weight: .medium)).foregroundStyle(.white)
                Text(detalhe).font(.system(size: 12)).foregroundStyle(Tema.textoSecundario)
            }
            Spacer()
            Toggle("", isOn: valor)
                .toggleStyle(.switch)
                .tint(Tema.acento)
                .labelsHidden()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }
}

/// A linha sob o ponteiro clareia, como a linha focada na TV.
private struct LinhaSobMouse: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Modificador(configuration: configuration)
    }

    private struct Modificador: View {
        let configuration: Configuration
        @State private var sobre = false
        var body: some View {
            configuration.label
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(configuration.isPressed ? 0.14 : sobre ? 0.07 : 0)))
                .onHover { sobre = $0 }
        }
    }
}
