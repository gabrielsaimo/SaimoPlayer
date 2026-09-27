import SwiftUI

/// O título que a ficha mostra, com o bastante para chegar até ele.
struct FichaAlvo: Identifiable, Equatable {
    let titulo: String
    let serie: Bool
    let ano: String
    let letra: String
    let reservado: Bool
    var id: String { (serie ? "s:" : "f:") + titulo + "|" + ano }
    var nomeCompleto: String { ano.isEmpty ? titulo : "\(titulo) (\(ano))" }
}

/// A ficha de um título, ocupando a área do acervo.
///
/// Antes era uma folha pequena por cima da grade, com texto e pouco mais. Agora
/// é o que a TV Box mostra: a imagem larga do filme ao fundo, escurecendo da
/// esquerda para a direita, a capa, os números em selos, a sinopse, e o elenco
/// em fotos redondas. Tocar num ator abre quem ele é e as capas de tudo que ele
/// tem no acervo — e tocar numa dessas capas abre a ficha daquele título.
///
/// "Assistir" não toca daqui: devolve à grade, que é quem sabe escolher fonte
/// e temporada. Assim o caminho até o vídeo é um só.
struct FichaTela: View {
    let alvo: FichaAlvo
    let assistir: () -> Void
    let fechar: () -> Void
    /// Abre a ficha de outro título — vindo da filmografia de um ator.
    let abrirTitulo: (Vod.Achado) -> Void

    @ObservedObject private var favoritos = VodFavoritos.shared
    @State private var ficha: Ficha?
    @State private var carregando = true
    @State private var ator: Ficha.Pessoa?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black
            if let ator {
                AtorTela(pessoa: ator, voltar: { self.ator = nil }, abrir: abrirTitulo)
                    .transition(.opacity)
            } else {
                fundo
                conteudo
            }
        }
        .animation(.easeInOut(duration: 0.18), value: ator?.id)
        .onExitCommand { if ator != nil { ator = nil } else { fechar() } }
        .task(id: alvo.id) {
            ficha = nil
            carregando = true
            ficha = await Fichas.de(alvo.titulo, serie: alvo.serie)
            carregando = false
            // O índice para a filmografia fica pronto enquanto se lê a ficha.
            if !(ficha?.elenco.isEmpty ?? true) { await Fichas.aquecer() }
        }
    }

    // MARK: - Fundo

    private var fundo: some View {
        GeometryReader { geo in
            ZStack {
                if let endereco = ficha?.fundo, let url = URL(string: endereco) {
                    AsyncImage(url: url, transaction: Transaction(animation: .easeIn(duration: 0.35))) { fase in
                        if let imagem = fase.image {
                            imagem.resizable().aspectRatio(contentMode: .fill)
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                        }
                    }
                }
                // O texto fica sobre o escuro; o filme aparece do outro lado.
                LinearGradient(
                    stops: [.init(color: .black.opacity(0.96), location: 0),
                            .init(color: .black.opacity(0.82), location: 0.45),
                            .init(color: .black.opacity(0.15), location: 1)],
                    startPoint: .leading, endPoint: .trailing)
                LinearGradient(colors: [.clear, .black.opacity(0.9)],
                               startPoint: .center, endPoint: .bottom)
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Conteúdo

    private var conteudo: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                botaoVoltar("Voltar", acao: fechar)

                HStack(alignment: .top, spacing: 30) {
                    capa
                    VStack(alignment: .leading, spacing: 12) {
                        Text(tipo)
                            .font(.system(size: 12, weight: .bold))
                            .tracking(2)
                            .foregroundStyle(Color.accentColor)
                        Text(Generos.semAno(alvo.titulo))
                            .font(.system(size: 38, weight: .bold))
                            .lineLimit(2)
                            .foregroundStyle(.white)
                        if let frase = ficha?.frase, !frase.isEmpty {
                            Text(frase).font(.system(size: 15)).italic()
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        selos
                        if let generos = ficha?.generos, !generos.isEmpty {
                            Text(generos.joined(separator: "  ·  "))
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.65))
                        }
                        botoes.padding(.top, 6)
                        if let sinopse = ficha?.sinopse, !sinopse.isEmpty {
                            Text(sinopse)
                                .font(.system(size: 15))
                                .lineSpacing(3)
                                .foregroundStyle(.white.opacity(0.9))
                                .frame(maxWidth: 680, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 6)
                        } else if !carregando {
                            Text("Sem ficha para este título.")
                                .font(.system(size: 14)).foregroundStyle(.secondary)
                        }
                        creditos
                    }
                    Spacer(minLength: 0)
                }

                if let elenco = ficha?.elenco, !elenco.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Elenco").font(.system(size: 18, weight: .semibold))
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 18) {
                                ForEach(elenco) { pessoa in
                                    Button { ator = pessoa } label: { FotoDePessoa(pessoa: pessoa) }
                                        .buttonStyle(CresceNoFoco())
                                        .help("Ver o que \(pessoa.nome) tem no acervo")
                                }
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 4)
                        }
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 26)
        }
    }

    private var tipo: String {
        alvo.serie ? "SÉRIE" : "FILME"
    }

    private var capa: some View {
        let endereco = ficha?.capa ?? Generos.capa(alvo.nomeCompleto, serie: alvo.serie)
        return ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.08))
            Text(String(alvo.titulo.prefix(1)).uppercased())
                .font(.system(size: 60, weight: .semibold))
                .foregroundStyle(Color.accentColor.opacity(0.7))
            if let endereco, let url = URL(string: endereco) {
                AsyncImage(url: url) { imagem in
                    imagem.resizable().aspectRatio(contentMode: .fill)
                } placeholder: { Color.clear }
            }
        }
        .frame(width: 220, height: 330)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.6), radius: 18, y: 8)
    }

    @ViewBuilder
    private var selos: some View {
        if let ficha {
            HStack(spacing: 8) {
                if ficha.nota > 0 {
                    Selo(texto: String(format: "★ %.1f", ficha.nota), cor: .yellow)
                }
                if !ficha.ano.isEmpty { Selo(texto: ficha.ano) }
                if let minutos = ficha.duracao, minutos > 0 {
                    Selo(texto: alvo.serie ? "\(minutos) min/ep" : duracao(minutos))
                }
                if let n = ficha.temporadas {
                    Selo(texto: n == 1 ? "1 temporada" : "\(n) temporadas")
                }
                if let nota = ficha.classificacao, !nota.isEmpty {
                    Selo(texto: nota, cor: corDaClassificacao(nota))
                }
            }
        } else if carregando {
            ProgressView().controlSize(.small)
        }
    }

    private var botoes: some View {
        let item = VodFavoritos.Item(titulo: alvo.titulo, serie: alvo.serie, letra: alvo.letra,
                                     reservado: alvo.reservado, ano: alvo.ano)
        let marcado = favoritos.contem(alvo.titulo, serie: alvo.serie, ano: alvo.ano)
        let andamento = alvo.serie ? nil : Progresso.fracao(Progresso.chaveFilme(alvo.titulo))
        return HStack(spacing: 12) {
            Button(action: assistir) {
                Label(alvo.serie ? "Ver episódios"
                          : (andamento ?? 0) > 0 ? "Continuar" : "Assistir",
                      systemImage: "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 26).padding(.vertical, 11)
                    .background(.white, in: RoundedRectangle(cornerRadius: 9))
                    .foregroundStyle(.black)
            }
            .buttonStyle(CresceNoFoco())
            .keyboardShortcut(.defaultAction)

            Button { favoritos.alternar(item) } label: {
                Label(marcado ? "Nos favoritos" : "Favoritar",
                      systemImage: marcado ? "star.fill" : "star")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 20).padding(.vertical, 11)
                    .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
                    .foregroundStyle(marcado ? .yellow : .white)
            }
            .buttonStyle(CresceNoFoco())
        }
    }

    @ViewBuilder
    private var creditos: some View {
        if let ficha {
            let linhas: [(String, String)] = [
                (alvo.serie ? "Criação" : "Direção", ficha.assinatura),
                ("Roteiro", ficha.roteiro),
                ("Produção", ficha.produtora),
            ].filter { !$0.1.isEmpty }
            if !linhas.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(linhas, id: \.0) { rotulo, valor in
                        (Text("\(rotulo): ").font(.system(size: 13, weight: .semibold))
                            + Text(valor).font(.system(size: 13)).foregroundColor(.white.opacity(0.65)))
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    /// 142 minutos vira "2h 22min": é assim que se lê duração de filme.
    private func duracao(_ minutos: Int) -> String {
        minutos < 60 ? "\(minutos) min" : "\(minutos / 60)h \(String(format: "%02d", minutos % 60))min"
    }

    /// As cores da classificação indicativa brasileira, as mesmas do celular.
    private func corDaClassificacao(_ nota: String) -> Color {
        switch nota.uppercased() {
        case "L": return Color(red: 0.06, green: 0.73, blue: 0.51)
        case "10": return Color(red: 0.23, green: 0.51, blue: 0.96)
        case "12": return Color(red: 0.96, green: 0.62, blue: 0.04)
        case "14": return Color(red: 0.98, green: 0.45, blue: 0.09)
        case "16", "18": return Color(red: 0.94, green: 0.27, blue: 0.27)
        default: return .white.opacity(0.8)
        }
    }
}

// MARK: - Ator

/// Uma pessoa e o que ela tem neste acervo, em capas.
///
/// Em cima, numa faixa, quem ela é: a foto, de onde é, a biografia. Embaixo,
/// as capas do que dá para assistir daqui — e só isso: a filmografia inteira
/// do TMDB, com setenta títulos que não abrem, seria uma lista que frustra.
struct AtorTela: View {
    let pessoa: Ficha.Pessoa
    let voltar: () -> Void
    let abrir: (Vod.Achado) -> Void

    @State private var perfil: Fichas.Perfil?
    @State private var trabalhos: [Fichas.Trabalho] = []
    @State private var carregando = true

    private let colunas = [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 20)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                botaoVoltar("Voltar à ficha", acao: voltar)

                HStack(alignment: .center, spacing: 26) {
                    FotoRedonda(endereco: perfil?.foto ?? pessoa.foto, nome: pessoa.nome, tamanho: 140)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(perfil?.nome.isEmpty == false ? perfil!.nome : pessoa.nome)
                            .font(.system(size: 34, weight: .bold))
                        if let dados = perfil?.dados, !dados.isEmpty {
                            Text(dados).font(.system(size: 14)).foregroundStyle(Color.accentColor)
                        }
                        if let bio = perfil?.biografia, !bio.isEmpty {
                            Text(bio)
                                .font(.system(size: 14))
                                .lineSpacing(2)
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(4)
                                .frame(maxWidth: 820, alignment: .leading)
                        }
                    }
                }

                HStack(spacing: 12) {
                    Text(carregando ? "Procurando no acervo…"
                         : trabalhos.count == 1 ? "1 título no acervo"
                         : "\(trabalhos.count) títulos no acervo")
                        .font(.system(size: 19, weight: .semibold))
                    if carregando { ProgressView().controlSize(.small) }
                }

                if !carregando && trabalhos.isEmpty {
                    Text("Aparece aqui só o que dá para assistir neste app.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }

                LazyVGrid(columns: colunas, alignment: .leading, spacing: 22) {
                    ForEach(trabalhos) { trabalho in
                        Button { abrir(trabalho.achado) } label: { CapaDeTrabalho(trabalho: trabalho) }
                            .buttonStyle(CresceNoFoco())
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 26)
        }
        .background(
            LinearGradient(colors: [Color(red: 0.05, green: 0.12, blue: 0.13), .black],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea())
        .task(id: pessoa.id) {
            async let perfilPedido = Fichas.perfil(pessoa.id)
            async let obras = Fichas.acervoDe(ator: pessoa.id)
            trabalhos = await obras
            carregando = false
            perfil = await perfilPedido
        }
    }
}

// MARK: - Peças

@MainActor
private func botaoVoltar(_ texto: String, acao: @escaping () -> Void) -> some View {
    Button(action: acao) {
        Label(texto, systemImage: "chevron.left")
            .font(.system(size: 14, weight: .medium))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.white.opacity(0.1), in: Capsule())
    }
    .buttonStyle(.plain)
    .foregroundStyle(.white.opacity(0.85))
    .help("Voltar (Esc)")
}

private struct Selo: View {
    let texto: String
    var cor: Color = .white.opacity(0.9)

    var body: some View {
        Text(texto)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(cor)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.25)))
    }
}

/// Cresce um pouco sob o mouse e ao ser pressionado: resposta imediata, sem
/// mexer no layout de ninguém em volta.
private struct CresceNoFoco: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Modificador(configuration: configuration)
    }

    private struct Modificador: View {
        let configuration: Configuration
        @State private var sobre = false
        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.97 : (sobre ? 1.05 : 1))
                .animation(.easeOut(duration: 0.12), value: sobre)
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
                .onHover { sobre = $0 }
                .contentShape(Rectangle())
        }
    }
}

private struct FotoRedonda: View {
    let endereco: String?
    let nome: String
    let tamanho: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.1))
            Text(String(nome.prefix(1)).uppercased())
                .font(.system(size: tamanho * 0.36, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
            if let endereco, let url = URL(string: endereco) {
                AsyncImage(url: url) { imagem in
                    imagem.resizable().aspectRatio(contentMode: .fill)
                } placeholder: { Color.clear }
            }
        }
        .frame(width: tamanho, height: tamanho)
        .clipShape(Circle())
    }
}

private struct FotoDePessoa: View {
    let pessoa: Ficha.Pessoa

    var body: some View {
        VStack(spacing: 7) {
            FotoRedonda(endereco: pessoa.foto, nome: pessoa.nome, tamanho: 96)
            Text(pessoa.nome)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(pessoa.papel)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
        }
        .frame(width: 116)
    }
}

private struct CapaDeTrabalho: View {
    let trabalho: Fichas.Trabalho

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.08))
                Text(String(trabalho.achado.titulo.prefix(1)).uppercased())
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Color.accentColor.opacity(0.7))
                if let endereco = trabalho.capa, let url = URL(string: endereco) {
                    AsyncImage(url: url) { imagem in
                        imagem.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: { Color.clear }
                }
            }
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(trabalho.achado.nomeCompleto)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(trabalho.papel.isEmpty ? (trabalho.achado.serie ? "Série" : "Filme") : trabalho.papel)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
        }
    }
}
