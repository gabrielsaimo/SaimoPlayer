import SwiftUI
import AppKit

/// As cores e as peças de vidro do app, as mesmas da TV Box.
///
/// A paleta sai do ícone: fundo quase preto, um ciano como único destaque e o
/// vermelho do "ao vivo". Uma cor de acento só é o que mantém a tela calma.
enum Tema {
    static let acento = Color(red: 0x4F / 255, green: 0xE3 / 255, blue: 0xD0 / 255)
    static let aoVivo = Color(red: 1, green: 0x4D / 255, blue: 0x4F / 255)
    static let fundo = Color(red: 0x0B / 255, green: 0x0E / 255, blue: 0x14 / 255)
    static let cartao = Color.white.opacity(0.07)
    static let textoSecundario = Color(red: 0xA8 / 255, green: 0xB4 / 255, blue: 0xC0 / 255)
    static let textoApagado = Color.white.opacity(0.4)

    /// Altura da barra do topo: o conteúdo das telas começa abaixo dela.
    static let alturaDaBarra: CGFloat = 64
    /// Margem lateral das telas, a mesma das fileiras e do destaque.
    static let margem: CGFloat = 40

    /// As cores das categorias nos cartões do On Demand.
    static let corFilmes = Color(red: 0x4F / 255, green: 0xE3 / 255, blue: 0xD0 / 255)
    static let corSeries = Color(red: 0x7A / 255, green: 0xA2 / 255, blue: 1)
    static let corAnimes = Color(red: 1, green: 0xB4 / 255, blue: 0x54 / 255)
    static let corDoramas = Color(red: 1, green: 0x7E / 255, blue: 0xB6 / 255)
}

// MARK: - Fundo

/// O fundo do app: o quase preto da TV com manchas de azul, ciano e roxo,
/// como a imagem de fundo dela. Desenhado, não baixado: acompanha qualquer
/// tamanho de janela sem esticar pixel.
struct FundoDoApp: View {
    var body: some View {
        ZStack {
            Tema.fundo
            RadialGradient(colors: [Color(red: 0.16, green: 0.30, blue: 0.55).opacity(0.55), .clear],
                           center: UnitPoint(x: 0.12, y: 0.05), startRadius: 0, endRadius: 700)
            RadialGradient(colors: [Color(red: 0.12, green: 0.55, blue: 0.55).opacity(0.35), .clear],
                           center: UnitPoint(x: 0.75, y: 0.0), startRadius: 0, endRadius: 600)
            RadialGradient(colors: [Color(red: 0.38, green: 0.18, blue: 0.55).opacity(0.45), .clear],
                           center: UnitPoint(x: 0.3, y: 1.0), startRadius: 0, endRadius: 800)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Vidro

/// Liquid Glass no macOS 26 em diante; antes dele, o material translúcido de
/// sempre. O app roda a partir do macOS 15, então toda peça de vidro passa
/// por aqui em vez de chamar `glassEffect` direto.
extension View {
    /// Vidro numa forma qualquer.
    @ViewBuilder
    func vidro<Forma: Shape>(_ forma: Forma, tinta: Color? = nil, interativo: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(Self.vidroComo(tinta: tinta, interativo: interativo), in: forma)
        } else {
            self.background {
                ZStack {
                    forma.fill(.ultraThinMaterial)
                    if let tinta { forma.fill(tinta.opacity(0.35)) }
                    forma.stroke(.white.opacity(0.12), lineWidth: 0.5)
                }
            }
        }
    }

    /// Vidro em cápsula: botões, pílulas e a barra do topo.
    func vidroCapsula(tinta: Color? = nil, interativo: Bool = false) -> some View {
        vidro(Capsule(), tinta: tinta, interativo: interativo)
    }

    /// Vidro em retângulo arredondado: painéis e cartões flutuantes.
    func vidroPainel(raio: CGFloat = 18, tinta: Color? = nil) -> some View {
        vidro(RoundedRectangle(cornerRadius: raio, style: .continuous), tinta: tinta)
    }

    @available(macOS 26.0, *)
    private static func vidroComo(tinta: Color?, interativo: Bool) -> Glass {
        var vidro = Glass.regular
        if let tinta { vidro = vidro.tint(tinta.opacity(0.6)) }
        if interativo { vidro = vidro.interactive() }
        return vidro
    }

    /// Marca a peça para se fundir às vizinhas quando o vidro anda (a aba
    /// escolhida deslizando de uma aba para a outra).
    @ViewBuilder
    func vidroID(_ id: String, em espaco: Namespace.ID) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffectID(id, in: espaco)
        } else {
            self.matchedGeometryEffect(id: id, in: espaco)
        }
    }
}

/// Agrupa peças de vidro vizinhas para que se misturem como uma só superfície
/// (`GlassEffectContainer`). Antes do macOS 26 só devolve o conteúdo.
struct GrupoDeVidro<Conteudo: View>: View {
    var espacamento: CGFloat = 12
    @ViewBuilder let conteudo: () -> Conteudo

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: espacamento) { conteudo() }
        } else {
            conteudo()
        }
    }
}

/// Botão de vidro: `.glass` ou `.glassProminent` no macOS 26, cápsula de
/// material antes dele. O proeminente leva a cor de acento.
struct BotaoDeVidro: ButtonStyle {
    var proeminente = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .foregroundStyle(proeminente ? Color.black : Color.white)
            .background {
                if proeminente {
                    Capsule().fill(Color.white)
                } else {
                    Capsule().fill(.ultraThinMaterial)
                    Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
                }
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

extension View {
    /// O botão de vidro do sistema quando existe; o nosso antes do macOS 26.
    @ViewBuilder
    func botaoDeVidro(proeminente: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if proeminente {
                self.buttonStyle(.glassProminent).tint(.white).foregroundStyle(.black)
                    .controlSize(.large)
            } else {
                self.buttonStyle(.glass).controlSize(.large)
            }
        } else {
            self.buttonStyle(BotaoDeVidro(proeminente: proeminente))
        }
    }
}

// MARK: - Foco

/// O realce de foco da TV, no mouse: o cartão sob o ponteiro cresce um pouco e
/// ganha a borda ciano. O teclado (Tab) mostra a mesma borda.
struct CartaoEmFoco: ButtonStyle {
    var raio: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        Modificador(configuration: configuration, raio: raio)
    }

    private struct Modificador: View {
        let configuration: Configuration
        let raio: CGFloat
        @State private var sobre = false
        @Environment(\.isFocused) private var focado

        var body: some View {
            configuration.label
                .overlay {
                    RoundedRectangle(cornerRadius: raio + 3, style: .continuous)
                        .strokeBorder(Tema.acento, lineWidth: 2.5)
                        .padding(-4)
                        .opacity(sobre || focado ? 1 : 0)
                }
                .scaleEffect(configuration.isPressed ? 0.98 : (sobre ? 1.03 : 1))
                .animation(.easeOut(duration: 0.14), value: sobre)
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
                .onHover { sobre = $0 }
                .contentShape(Rectangle())
        }
    }
}

// MARK: - Imagens

/// Imagens da rede guardadas na memória enquanto o app está aberto.
///
/// `AsyncImage` baixa de novo toda vez que a célula volta à tela: rolar uma
/// fileira para lá e para cá refazia cada pedido. Aqui cada endereço é
/// baixado uma vez (o cache do URLSession ainda guarda em disco).
@MainActor
final class ImagensRemotas: ObservableObject {
    static let shared = ImagensRemotas()

    private let cache = NSCache<NSString, NSImage>()
    private var pedidas = Set<String>()
    @Published private(set) var versao = 0
    private let sessao: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 32 << 20, diskCapacity: 512 << 20,
                                   directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                                    .appendingPathComponent("imagens"))
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: config)
    }()

    private init() { cache.countLimit = 600 }

    func imagem(_ endereco: String) -> NSImage? {
        if let pronta = cache.object(forKey: endereco as NSString) { return pronta }
        pedir(endereco)
        return nil
    }

    private func pedir(_ endereco: String) {
        guard !pedidas.contains(endereco), let url = URL(string: endereco) else { return }
        pedidas.insert(endereco)
        let sessao = self.sessao
        Task {
            guard let (dados, _) = try? await sessao.data(from: url),
                  let imagem = NSImage(data: dados) else { return }
            cache.setObject(imagem, forKey: endereco as NSString)
            versao &+= 1
        }
    }
}

/// Uma imagem da rede que ocupa o quadro inteiro, com a reserva até chegar.
struct ImagemRemota<Reserva: View>: View {
    let endereco: String?
    var modo: ContentMode = .fill
    @ViewBuilder var reserva: () -> Reserva
    @ObservedObject private var imagens = ImagensRemotas.shared

    var body: some View {
        if let endereco, !endereco.isEmpty, let imagem = imagens.imagem(endereco) {
            Image(nsImage: imagem)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: modo)
                .transition(.opacity)
        } else {
            reserva()
        }
    }
}

extension ImagemRemota where Reserva == Color {
    init(_ endereco: String?, modo: ContentMode = .fill) {
        self.init(endereco: endereco, modo: modo) { Color.clear }
    }
}

// MARK: - Selos

/// "AO VIVO" em vermelho, com o placar ou o tempo de jogo quando há.
struct SeloAoVivo: View {
    var texto = "AO VIVO"

    var body: some View {
        Text(texto)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Tema.aoVivo, in: Capsule())
    }
}

/// A barra fina de progresso das capas e dos cartões: ciano sobre trilho.
struct BarraDeProgresso: View {
    let fracao: Double
    var altura: CGFloat = 4
    var cor: Color = Tema.acento

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.22))
                Capsule().fill(cor)
                    .frame(width: max(altura, geo.size.width * min(max(fracao, 0), 1)))
            }
        }
        .frame(height: altura)
    }
}

/// O relógio do topo, como na TV: horas e minutos, sem segundos.
struct Relogio: View {
    var tamanho: CGFloat = 17

    var body: some View {
        TimelineView(.everyMinute) { contexto in
            Text(contexto.date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                .font(.system(size: tamanho, weight: .medium).monospacedDigit())
                .foregroundStyle(.white)
        }
    }
}
