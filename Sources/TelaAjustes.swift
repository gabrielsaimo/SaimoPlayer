import SwiftUI
import AppKit

/// Preferências do app que não moram no modelo do player.
enum Preferencias {
    private static let chaveAbrirNoCanal = "ajustes.abrirNoCanal"
    private static let chaveUpscaling = "ajustes.upscaling"
    static let upscalingMudou = Notification.Name("SaimoUpscalingMudou")

    /// Ao abrir o app: a tela inicial (como na TV) ou direto o último canal.
    static var abrirNoCanal: Bool {
        get { UserDefaults.standard.bool(forKey: chaveAbrirNoCanal) }
        set { UserDefaults.standard.set(newValue, forKey: chaveAbrirNoCanal) }
    }

    /// Super Resolução (Upscaling): "off" (padrão), "hd" ou "4k".
    static var upscaling: String {
        get { UserDefaults.standard.string(forKey: chaveUpscaling) ?? "off" }
        set {
            UserDefaults.standard.set(newValue, forKey: chaveUpscaling)
            NotificationCenter.default.post(name: upscalingMudou, object: nil)
        }
    }

    static func rotuloUpscaling(_ modo: String) -> String {
        switch modo {
        case "hd": return "Nitidez HD (720p → Full HD)"
        case "4k": return "Super Resolução Ultra (Full HD → 4K)"
        default:   return "Desligado"
        }
    }
}

/// Os ajustes, em seções como na TV Box: reprodução, geral, canais e sistema.
/// Cada linha diz o que faz e o valor de agora; clicar troca.
struct TelaAjustes: View {
    @ObservedObject var model: PlayerModel
    @ObservedObject private var epg = EPGService.shared
    @State private var abrirNoCanal = Preferencias.abrirNoCanal
    @State private var upscaling = Preferencias.upscaling

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
                        linha("Super Resolução (Upscaling)", Preferencias.rotuloUpscaling(upscaling),
                              icone: "sparkles") {
                            let proximo: String
                            switch upscaling {
                            case "off": proximo = "hd"
                            case "hd":  proximo = "4k"
                            default:    proximo = "off"
                            }
                            upscaling = proximo
                            Preferencias.upscaling = proximo
                        }
                        alternador("Preencher a tela", "Corta as bordas em vez de mostrar faixas pretas",
                                   icone: "rectangle.arrowtriangle.2.outward", valor: $model.fillScreen)
                        alternador("Manter à frente", "A janela fica por cima das outras",
                                   icone: "pin.fill", valor: $model.alwaysOnTop)
                        alternador("Estatísticas do vídeo", "Resolução, bitrate e buffer no canto da imagem",
                                   icone: "chart.bar.xaxis", valor: $model.showStats)
                        alternador("Sem som", "Silencia o vídeo e o ao vivo",
                                   icone: "speaker.slash.fill", valor: $model.isMuted)
                    }

                    secao("Geral") {
                        linha("Ao abrir o app", abrirNoCanal ? "Ir direto ao último canal" : "Mostrar a tela inicial",
                              icone: "house.fill") {
                            abrirNoCanal.toggle()
                            Preferencias.abrirNoCanal = abrirNoCanal
                        }
                        alternador("Lista de canais em janela separada",
                                   "Uma janela ao lado do player, como antes (⇧⌘L)",
                                   icone: "sidebar.leading", valor: $model.detachedList)
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
