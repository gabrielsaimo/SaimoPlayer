import SwiftUI
import AppKit

/// As abas da barra do topo, na ordem da TV Box.
enum Aba: String, CaseIterable, Identifiable {
    case buscar, inicio, aoVivo, eventos, onDemand, favoritos, radios, extras, ajustes

    var id: String { rawValue }

    var titulo: String {
        switch self {
        case .buscar: return "Buscar"
        case .inicio: return "Início"
        case .aoVivo: return "Ao vivo"
        case .eventos: return "Eventos"
        case .onDemand: return "On Demand"
        case .favoritos: return "Favoritos"
        case .radios: return "Rádios"
        case .extras: return "Extras"
        case .ajustes: return "Ajustes"
        }
    }

    var icone: String {
        switch self {
        case .buscar: return "magnifyingglass"
        case .inicio: return "house.fill"
        case .aoVivo: return "play.tv.fill"
        case .eventos: return "sportscourt.fill"
        case .onDemand: return "film.stack.fill"
        case .favoritos: return "star.fill"
        case .radios: return "radio.fill"
        case .extras: return "plus.rectangle.on.rectangle"
        case .ajustes: return "gearshape.fill"
        }
    }

    /// A aba que a seção aberta representa. Sem seção é o vídeo: Ao vivo (ou On Demand se arquivo em reprodução).
    @MainActor
    static func de(_ secao: VodSecao?) -> Aba {
        if secao == nil && PlayerModel.shared.playingFile != nil {
            return .onDemand
        }
        switch secao {
        case nil: return .aoVivo
        case .inicio: return .inicio
        case .eventos: return .eventos
        case .ondemand, .filmes, .series, .animes, .doramas: return .onDemand
        case .favoritos: return .favoritos
        case .radios: return .radios
        case .extras: return .extras
        case .buscar: return .buscar
        case .ajustes: return .ajustes
        }
    }

    /// Navegar pela barra não empilha telas: cada aba abre do começo, como
    /// na TV, onde o menu do topo sempre leva à tela inicial de cada parte.
    @MainActor
    func abrir() {
        let estado = VodEstado.shared
        estado.serieAberta = nil
        estado.explorando = false
        switch self {
        case .aoVivo:
            // O vídeo volta para o lugar dele; a rádio para, porque o ao
            // vivo volta a tocar.
            Radios.shared.parar()
            if PlayerModel.shared.playingFile != nil {
                PlayerModel.shared.voltarAoVivo()
            }
            estado.secao = nil
        case .inicio: estado.secao = .inicio
        case .eventos: estado.secao = .eventos
        case .onDemand: estado.secao = .ondemand
        case .favoritos: estado.secao = .favoritos
        case .radios: estado.secao = .radios
        case .extras: estado.secao = .extras
        case .buscar: estado.secao = .buscar
        case .ajustes: estado.secao = .ajustes
        }
    }
}

/// A barra do topo, a mesma em todas as telas: o ícone do app, as abas, a
/// engrenagem dos ajustes e o relógio.
///
/// É de vidro (Liquid Glass no macOS 26): sobre o vídeo, sobre a imagem
/// larga do destaque ou sobre o fundo do app, deixa ver o que passa por baixo.
/// A aba aberta é uma cápsula de vidro que desliza até a escolhida.
struct BarraDoTopo: View {
    @ObservedObject var model: PlayerModel
    @ObservedObject private var estado = VodEstado.shared
    @ObservedObject private var radios = Radios.shared
    /// Em tela cheia não há botões de janela à esquerda: a barra encosta.
    var telaCheia: Bool

    @Namespace private var espaco

    private var abas: [Aba] {
        // Extras só aparece com o código digitado, e some sem deixar vão.
        Aba.allCases.filter { aba in
            switch aba {
            case .extras: return model.restrictedUnlocked
            case .ajustes: return false
            default: return true
            }
        }
    }

    var body: some View {
        let atual = Aba.de(estado.secao)
        ZStack {
            // As abas de navegação perfeitamente centralizadas na largura da tela
            GrupoDeVidro(espacamento: 4) {
                ViewThatFits(in: .horizontal) {
                    fileiraDeAbas(atual, comNome: true)
                    fileiraDeAbas(atual, comNome: false)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            // Elementos das extremidades (esquerda e direita)
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 30, height: 30)
                    .help("Saimo TV")
                    .padding(.leading, telaCheia ? 22 : 84)

                Spacer(minLength: 0)
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .contentShape(Rectangle())
                    .gesture(WindowDragGesture())

                if radios.tocando != nil {
                    RadioNaBarra()
                }

                Button { Aba.ajustes.abrir() } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .foregroundStyle(atual == .ajustes ? Color.black : Color.white)
                        .background {
                            if atual == .ajustes { Circle().fill(Color.white) }
                        }
                        .vidro(Circle(), interativo: true)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Ajustes")

                Relogio()
                    .padding(.leading, 4)
                    .padding(.trailing, 22)
            }
        }
        .frame(height: Tema.alturaDaBarra)
        .background(alignment: .top) {
            // O degradê faz a barra se ler sobre qualquer imagem, sem caixa.
            LinearGradient(colors: [.black.opacity(0.55), .black.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: Tema.alturaDaBarra + 24)
                .allowsHitTesting(false)
        }
        .environment(\.colorScheme, .dark)
    }

    private func fileiraDeAbas(_ atual: Aba, comNome: Bool) -> some View {
        HStack(spacing: 2) {
            ForEach(abas) { aba in
                botao(aba, atual: atual, comNome: comNome)
            }
        }
        .padding(4)
        .vidroCapsula()
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: atual)
    }

    private func botao(_ aba: Aba, atual: Aba, comNome: Bool) -> some View {
        let escolhida = aba == atual
        return Button { aba.abrir() } label: {
            HStack(spacing: 6) {
                Image(systemName: aba.icone)
                    .font(.system(size: 13, weight: .semibold))
                if comNome {
                    Text(aba.titulo)
                        .font(.system(size: 14, weight: escolhida ? .semibold : .medium))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .padding(.horizontal, comNome ? 13 : 10)
            .padding(.vertical, 7)
            .foregroundStyle(escolhida ? Color.black : Color.white.opacity(0.92))
            .background {
                if escolhida {
                    Capsule().fill(Color.white)
                        .matchedGeometryEffect(id: "aba", in: espaco)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(AbaSobMouse())
        .help(comNome ? aba.titulo : "\(aba.titulo)")
    }
}

/// A aba sob o ponteiro ganha um véu claro, como a aba focada na TV.
private struct AbaSobMouse: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Modificador(configuration: configuration)
    }

    private struct Modificador: View {
        let configuration: Configuration
        @State private var sobre = false
        var body: some View {
            configuration.label
                .background(Capsule().fill(.white.opacity(sobre ? 0.12 : 0)))
                .scaleEffect(configuration.isPressed ? 0.95 : 1)
                .animation(.easeOut(duration: 0.12), value: sobre)
                .onHover { sobre = $0 }
        }
    }
}

/// A rádio que está tocando, na barra: o nome e o botão de parar, para ela
/// não ficar tocando escondida de outra aba.
private struct RadioNaBarra: View {
    @ObservedObject private var radios = Radios.shared

    var body: some View {
        if let radio = radios.tocando {
            HStack(spacing: 8) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundStyle(Tema.acento)
                    .symbolEffect(.variableColor.iterative, isActive: radios.noAr)
                Text(radio.nome)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: 160)
                Button { radios.parar() } label: {
                    Image(systemName: "stop.fill").font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.plain)
                .help("Parar a rádio")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .vidroCapsula(interativo: true)
            .onTapGesture { Aba.radios.abrir() }
            .help("Abrir Rádios")
        }
    }
}
