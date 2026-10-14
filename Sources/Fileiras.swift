import SwiftUI
import AppKit

/// Fileiras de cartões, como na TV Box: a tela inicial, o On Demand, as
/// páginas de cada categoria, as rádios e os eventos são todos assim — um
/// destaque em cima, com o título sob o ponteiro e a imagem larga dele ao
/// fundo, e fileiras que correm para o lado.
///
/// O cartão leva a própria ação: a fileira não sabe se aquilo é um filme, uma
/// série, um canal, uma rádio ou um atalho — ela desenha e chama.
struct CartaoFila: Identifiable {
    enum Tipo { case capa, largo, secao, evento }

    var id: String
    var titulo: String
    /// Linha de baixo do cartão (o programa no ar, o estilo da rádio).
    var subtitulo: String? = nil
    /// Endereço da capa (ou do logo, no cartão largo).
    var capa: String? = nil
    /// Sem capa pronta: o nome com que se procura uma no TMDB, e se é série.
    var procurar: (titulo: String, serie: Bool)? = nil
    /// Logo de canal, pelo carregador dos logos (guardado em disco).
    var logoCanal: URL? = nil
    var progresso: Double? = nil
    /// Selo do canto: "4K", o placar ao vivo, o horário do jogo.
    var selo: String? = nil
    var seloAoVivo = false
    /// O título por trás do cartão, para o destaque do topo buscar a ficha.
    var alvo: (titulo: String, serie: Bool)? = nil
    /// Linha de cima e texto do destaque quando o cartão não é um título.
    var meta: String? = nil
    var sinopse: String? = nil
    /// Título cuja imagem larga vai ao fundo quando o cartão não é um.
    var fundoDe: (titulo: String, serie: Bool)? = nil
    /// Imagem larga já conhecida (o jogo não tem ficha).
    var fundo: String? = nil
    /// Cartão de categoria: as capas da colagem, o ícone e a cor dela.
    var colagem: [String] = []
    var icone: String? = nil
    var cor: Color? = nil
    /// Cartão de jogo: os escudos e o logo da liga.
    var escudos: (casa: String, fora: String, nomeCasa: String, nomeFora: String)? = nil
    var logoLiga: String? = nil
    /// Estrela no canto: favoritar sem abrir.
    var favorito: (marcado: Bool, alternar: () -> Void)? = nil
    /// Menu do botão direito (tirar do "continue assistindo"...).
    var menu: [(String, () -> Void)] = []
    let acao: () -> Void

    var inicial: String {
        String(titulo.first { $0.isLetter || $0.isNumber } ?? "•").uppercased()
    }
}

struct Fila: Identifiable {
    let titulo: String
    var tipo: CartaoFila.Tipo = .capa
    let cartoes: [CartaoFila]
    var id: String { titulo }
}

// MARK: - Destaque

/// O que o destaque do topo mostra, trocado pelo cartão sob o ponteiro.
///
/// Espera o ponteiro descansar um pouco antes de pedir a ficha: quem passa o
/// mouse por uma fileira inteira não precisa de um pedido ao TMDB por capa.
@MainActor
final class DestaqueEstado: ObservableObject {
    @Published var titulo = ""
    @Published var meta = ""
    @Published var metaComNota = false
    @Published var sinopse = ""
    @Published var fundo: String?
    /// Logo do título (TMDB), no lugar do nome quando existe.
    @Published var logo: String?

    private var trabalho: Task<Void, Never>?
    private var padraoTitulo = ""
    private var padraoMeta = ""
    private var padraoSinopse = ""

    func padrao(_ titulo: String, _ meta: String, _ sinopse: String = "") {
        padraoTitulo = titulo
        padraoMeta = meta
        padraoSinopse = sinopse
        voltarAoPadrao()
    }

    func voltarAoPadrao() {
        trabalho?.cancel()
        titulo = padraoTitulo
        meta = padraoMeta
        metaComNota = false
        sinopse = padraoSinopse
        fundo = nil
        logo = nil
    }

    func mostrar(_ cartao: CartaoFila) {
        trabalho?.cancel()
        titulo = cartao.alvo.map { Generos.semAno($0.titulo) } ?? cartao.titulo
        logo = nil
        metaComNota = false
        meta = cartao.meta
            ?? cartao.subtitulo.map { "agora: \($0)" }
            ?? cartao.alvo.map { $0.serie ? "Série" : "Filme" }
            ?? ""
        sinopse = cartao.sinopse ?? ""
        if let fundo = cartao.fundo { self.fundo = fundo }
        guard let alvo = cartao.alvo ?? cartao.fundoDe else {
            if cartao.fundo == nil { fundo = nil }
            return
        }
        let soFundo = cartao.alvo == nil
        trabalho = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(soFundo ? 250 : 380))
            guard !Task.isCancelled else { return }
            guard let ficha = await Fichas.de(alvo.titulo, serie: alvo.serie), !Task.isCancelled,
                  let self else { return }
            withAnimation(.easeInOut(duration: 0.35)) { self.fundo = ficha.fundo }
            guard !soFundo else { return }
            var partes: [String] = []
            if ficha.nota > 0 { partes.append(String(format: "%.1f", ficha.nota).replacingOccurrences(of: ".", with: ",")) }
            if !ficha.ano.isEmpty { partes.append(ficha.ano) }
            if let t = ficha.temporadas { partes.append(t == 1 ? "1 temporada" : "\(t) temporadas") }
            let generos = ficha.generos.prefix(3).joined(separator: ", ")
            if !generos.isEmpty { partes.append(generos) }
            self.meta = partes.joined(separator: "  ·  ")
            self.metaComNota = ficha.nota > 0
            self.sinopse = ficha.sinopse
            self.logo = ficha.logo
        }
    }
}

/// O título, a linha de números e a sinopse do destaque.
struct DestaqueTopo: View {
    @ObservedObject var estado: DestaqueEstado

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(estado.titulo)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .shadow(color: .black.opacity(0.5), radius: 8, y: 2)
            if !estado.meta.isEmpty {
                HStack(spacing: 5) {
                    if estado.metaComNota {
                        Image(systemName: "star.fill").font(.system(size: 13))
                    }
                    Text(estado.meta)
                        .font(.system(size: 16, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(Tema.acento)
            }
            if !estado.sinopse.isEmpty {
                Text(estado.sinopse)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
                    .lineSpacing(2)
                    .frame(maxWidth: 680, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.easeInOut(duration: 0.2), value: estado.titulo)
    }
}

/// A imagem larga do destaque, ao fundo da tela inteira, apagando para a
/// esquerda (onde fica o texto) e para baixo (onde ficam as fileiras).
struct FundoDoDestaque: View {
    @ObservedObject var estado: DestaqueEstado

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let fundo = estado.fundo {
                    ImagemRemota(fundo)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .id(fundo)
                        .transition(.opacity)
                    LinearGradient(
                        stops: [.init(color: Tema.fundo.opacity(0.95), location: 0),
                                .init(color: Tema.fundo.opacity(0.55), location: 0.45),
                                .init(color: Tema.fundo.opacity(0.1), location: 1)],
                        startPoint: .leading, endPoint: .trailing)
                    LinearGradient(
                        stops: [.init(color: .clear, location: 0.25),
                                .init(color: Tema.fundo.opacity(0.85), location: 0.62),
                                .init(color: Tema.fundo, location: 1)],
                        startPoint: .top, endPoint: .bottom)
                }
            }
            .animation(.easeInOut(duration: 0.4), value: estado.fundo)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Uma tela em fileiras: o fundo, o destaque e as fileiras embaixo.
///
/// O destaque fica parado no alto, como na TV; só as fileiras rolam.
struct TelaEmFileiras<Topo: View>: View {
    /// Não observado aqui: só o destaque e o fundo mudam com o ponteiro, e
    /// redesenhar as fileiras a cada cartão sob o mouse pesaria à toa.
    let destaque: DestaqueEstado
    let filas: [Fila]
    var carregando = false
    var vazio = "Nada aqui por enquanto"
    /// O que vai no lugar do destaque, quando a tela tem algo seu (a rádio
    /// tocando). Sem ele, o destaque.
    @ViewBuilder var topo: () -> Topo

    var body: some View {
        GeometryReader { geo in
            let alturaDestaque = min(max(geo.size.height * 0.3, 150), 270)
            ZStack(alignment: .topLeading) {
                FundoDoDestaque(estado: destaque)
                VStack(alignment: .leading, spacing: 0) {
                    topo()
                        .padding(.horizontal, Tema.margem)
                        .padding(.top, Tema.alturaDaBarra + 12)
                        .frame(height: Tema.alturaDaBarra + 12 + alturaDestaque, alignment: .top)

                    if filas.isEmpty {
                        VStack(spacing: 10) {
                            if carregando { ProgressView().controlSize(.small) }
                            Text(carregando ? "Carregando…" : vazio)
                                .foregroundStyle(.white.opacity(0.55))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView(.vertical) {
                            LazyVStack(alignment: .leading, spacing: 30) {
                                ForEach(filas) { fila in
                                    FileiraView(fila: fila, destaque: destaque)
                                }
                            }
                            .padding(.top, 6)
                            .padding(.bottom, 40)
                        }
                        .scrollIndicators(.hidden)
                        .mask(
                            LinearGradient(stops: [.init(color: .clear, location: 0),
                                                   .init(color: .black, location: 0.025),
                                                   .init(color: .black, location: 1)],
                                           startPoint: .top, endPoint: .bottom))
                    }
                }
            }
        }
    }
}

extension TelaEmFileiras where Topo == DestaqueTopo {
    init(destaque: DestaqueEstado, filas: [Fila], carregando: Bool = false,
         vazio: String = "Nada aqui por enquanto") {
        self.init(destaque: destaque, filas: filas, carregando: carregando, vazio: vazio) {
            DestaqueTopo(estado: destaque)
        }
    }
}

// MARK: - Fileira

/// Uma fileira: o nome em cima e os cartões correndo para o lado. Com o
/// mouse sobre ela aparecem setas de vidro nas pontas, para quem não tem
/// trackpad andar a fileira de página em página.
struct FileiraView: View {
    let fila: Fila
    let destaque: DestaqueEstado

    @State private var primeiro: String?
    @State private var sobre = false

    private var largura: CGFloat {
        switch fila.tipo {
        case .capa: return 150
        case .largo: return 262
        case .secao: return 330
        case .evento: return 330
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(fila.titulo)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, Tema.margem)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 18) {
                    ForEach(fila.cartoes) { cartao in
                        Button(action: cartao.acao) {
                            CartaoView(cartao: cartao, tipo: fila.tipo, largura: largura)
                        }
                        .buttonStyle(CartaoEmFoco(raio: fila.tipo == .capa ? 10 : 14))
                        .onHover { if $0 { destaque.mostrar(cartao) } }
                        .contextMenu {
                            if let favorito = cartao.favorito {
                                Button(favorito.marcado ? "Remover dos favoritos" : "Favoritar",
                                       action: favorito.alternar)
                            }
                            ForEach(Array(cartao.menu.enumerated()), id: \.offset) { _, item in
                                Button(item.0, action: item.1)
                            }
                        }
                        .help(cartao.titulo)
                        .id(cartao.id)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, Tema.margem)
                // A moldura do foco passa da borda do cartão.
                .padding(.vertical, 6)
            }
            .scrollIndicators(.hidden)
            .scrollPosition(id: $primeiro, anchor: .leading)
            .overlay { setas }
        }
        .onHover { sobre = $0 }
    }

    @ViewBuilder
    private var setas: some View {
        if sobre, fila.cartoes.count > 3 {
            HStack {
                seta("chevron.left", passo: -1)
                Spacer()
                seta("chevron.right", passo: 1)
            }
            .padding(.horizontal, 8)
            .transition(.opacity)
        }
    }

    private func seta(_ simbolo: String, passo: Int) -> some View {
        Button {
            let ids = fila.cartoes.map(\.id)
            let atual = primeiro.flatMap { ids.firstIndex(of: $0) } ?? 0
            let pagina = 4
            let alvo = min(max(atual + passo * pagina, 0), max(ids.count - 1, 0))
            withAnimation(.easeInOut(duration: 0.35)) { primeiro = ids[alvo] }
        } label: {
            Image(systemName: simbolo)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .vidro(Circle(), interativo: true)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Cartões

struct CartaoView: View {
    let cartao: CartaoFila
    let tipo: CartaoFila.Tipo
    let largura: CGFloat

    var body: some View {
        switch tipo {
        case .capa: CapaCartao(cartao: cartao, largura: largura)
        case .largo: LargoCartao(cartao: cartao, largura: largura)
        case .secao: SecaoCartao(cartao: cartao, largura: largura)
        case .evento: EventoCartao(cartao: cartao, largura: largura)
        }
    }
}

/// O pôster com o nome embaixo; a barra do quanto foi visto vai na própria
/// capa, que é onde o olho já está.
private struct CapaCartao: View {
    let cartao: CartaoFila
    let largura: CGFloat
    @ObservedObject private var capas = Capas.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Tema.cartao)
                ImagemRemota(endereco: cartao.capa) { reserva }
                    .frame(width: largura, height: largura * 1.5)
                    .clipped()
                if let progresso = cartao.progresso, progresso > 0 {
                    BarraDeProgresso(fracao: progresso)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                }
            }
            .frame(width: largura, height: largura * 1.5)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .topLeading) {
                if let selo = cartao.selo {
                    Text(selo)
                        .font(.system(size: 10, weight: .heavy))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.black.opacity(0.65), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(6)
                }
            }
            .overlay(alignment: .topTrailing) { estrela }
            .shadow(color: .black.opacity(0.35), radius: 8, y: 4)

            Text(cartao.titulo)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(2, reservesSpace: true)
                .frame(width: largura, alignment: .leading)
        }
    }

    @ViewBuilder
    private var reserva: some View {
        if let procurar = cartao.procurar, let imagem = capas.imagem(para: procurar.titulo, serie: procurar.serie) {
            Image(nsImage: imagem).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
        } else {
            Text(cartao.inicial)
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .foregroundStyle(Tema.acento.opacity(0.6))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var estrela: some View {
        if let favorito = cartao.favorito, favorito.marcado {
            Image(systemName: "star.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.yellow)
                .padding(5)
                .background(.black.opacity(0.5), in: Circle())
                .padding(6)
        }
    }
}

/// O cartão largo: canal, rádio. O logo no meio, o selo "AO VIVO" no canto e
/// a barra do programa embaixo.
private struct LargoCartao: View {
    let cartao: CartaoFila
    let largura: CGFloat
    @ObservedObject private var logos = LogoLoader.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.13), .white.opacity(0.05)],
                                         startPoint: .top, endPoint: .bottom))
                logo
                    .frame(width: largura * 0.5, height: largura * 0.56 * 0.55)
            }
            .frame(width: largura, height: largura * 0.56)
            .overlay(alignment: .topLeading) {
                if cartao.seloAoVivo {
                    SeloAoVivo(texto: cartao.selo ?? "AO VIVO").padding(9)
                }
            }
            .overlay(alignment: .bottom) {
                if let progresso = cartao.progresso {
                    BarraDeProgresso(fracao: progresso, altura: 3)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1))

            Text(cartao.titulo)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(cartao.subtitulo ?? " ")
                .font(.system(size: 12))
                .foregroundStyle(Tema.textoSecundario)
                .lineLimit(1)
        }
        .frame(width: largura, alignment: .leading)
    }

    @ViewBuilder
    private var logo: some View {
        if let url = cartao.logoCanal, let imagem = logos.image(for: url) {
            Image(nsImage: imagem).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
        } else if let capa = cartao.capa {
            ImagemRemota(endereco: capa, modo: .fit) { inicial }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            inicial
        }
    }

    private var inicial: some View {
        Text(cartao.inicial)
            .font(.system(size: 40, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.85))
    }
}

/// O cartão de categoria do On Demand: colagem de capas, o ícone na cor
/// dela, o nome e quantos títulos tem.
private struct SecaoCartao: View {
    let cartao: CartaoFila
    let largura: CGFloat

    var body: some View {
        let altura = largura * 0.58
        ZStack(alignment: .bottomLeading) {
            HStack(spacing: 0) {
                ForEach(Array(cartao.colagem.prefix(4).enumerated()), id: \.offset) { _, capa in
                    ImagemRemota(capa)
                        .frame(width: largura / 4, height: altura)
                        .clipped()
                }
            }
            .frame(width: largura, height: altura, alignment: .leading)
            .background(Tema.cartao)
            LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.85)],
                           startPoint: .top, endPoint: .bottom)
            HStack(spacing: 12) {
                Image(systemName: cartao.icone ?? "film")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.8))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(cartao.cor ?? Tema.acento))
                VStack(alignment: .leading, spacing: 1) {
                    Text(cartao.titulo)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let subtitulo = cartao.subtitulo {
                        Text(subtitulo)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
            .padding(16)
        }
        .frame(width: largura, height: altura)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(.white.opacity(0.1), lineWidth: 1))
    }
}

/// O cartão de jogo: o selo (ao vivo com placar, ou o horário), o logo da
/// liga, os dois escudos e, embaixo, o jogo e o canal.
private struct EventoCartao: View {
    let cartao: CartaoFila
    let largura: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.13), .white.opacity(0.05)],
                                         startPoint: .top, endPoint: .bottom))
                if let escudos = cartao.escudos {
                    HStack(spacing: 18) {
                        escudo(escudos.casa, escudos.nomeCasa)
                        Text("x")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white.opacity(0.5))
                        escudo(escudos.fora, escudos.nomeFora)
                    }
                }
            }
            .frame(width: largura, height: largura * 0.48)
            .overlay(alignment: .topLeading) {
                Group {
                    if cartao.seloAoVivo {
                        SeloAoVivo(texto: cartao.selo ?? "AO VIVO")
                    } else if let selo = cartao.selo {
                        Text(selo)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(.white.opacity(0.16), in: Capsule())
                    }
                }
                .padding(9)
            }
            .overlay(alignment: .topTrailing) {
                if let liga = cartao.logoLiga, !liga.isEmpty {
                    LogoDeLiga(endereco: liga).frame(width: 24, height: 24).padding(9)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(cartao.seloAoVivo ? Tema.aoVivo.opacity(0.45) : .white.opacity(0.08), lineWidth: 1))

            Text(cartao.titulo)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(cartao.subtitulo ?? " ")
                .font(.system(size: 12))
                .foregroundStyle(Tema.textoSecundario)
                .lineLimit(1)
        }
        .frame(width: largura, alignment: .leading)
    }

    private func escudo(_ endereco: String, _ nome: String) -> some View {
        LogoDeLiga(endereco: endereco, inicial: String(nome.prefix(1)).uppercased())
            .frame(width: 64, height: 64)
    }
}

/// Escudo ou logo de liga pelo carregador dos logos (guarda em disco e não
/// pisca a cada atualização da agenda).
struct LogoDeLiga: View {
    let endereco: String
    var inicial = ""
    @ObservedObject private var logos = LogoLoader.shared

    var body: some View {
        if let url = URL(string: endereco.emAltaResolucao), !endereco.isEmpty, let imagem = logos.image(for: url) {
            Image(nsImage: imagem).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
        } else {
            Circle().fill(.white.opacity(0.1))
                .overlay(Text(inicial).font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7)))
        }
    }
}
