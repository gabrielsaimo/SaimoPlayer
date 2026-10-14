import SwiftUI

/// A série aberta no acervo: a ficha e os episódios na mesma tela, como na TV Box.
///
/// Antes eram duas paradas: a ficha, com um "Ver episódios", e depois uma lista
/// de texto, temporada embaixo de temporada, em que cada linha dizia só
/// "Episódio 7" e um botão. Para saber de que episódio se tratava era preciso
/// abrir. Aqui fica o que a TV Box mostra: a imagem larga da série ao fundo, a
/// capa, a logo, os selos e a sinopse; embaixo as temporadas em pílulas e os
/// episódios em cartões com a imagem da cena, o nome, o resumo, a duração, o
/// quanto já foi visto e a marca de assistido.
///
/// Abre na temporada em que se está, com o episódio a continuar marcado e à
/// vista, e o botão grande toca justamente ele.
struct SerieTela: View {
    @ObservedObject var model: PlayerModel
    let serie: Serie
    let episodios: [Episodio]
    /// De onde a série veio, para o favorito saber achá-la de novo.
    let letra: String
    let voltar: () -> Void
    let tocar: (Episodio) -> Void
    /// Abre outro título — vindo da filmografia de um ator.
    let abrirTitulo: (Vod.Achado) -> Void

    @ObservedObject private var favoritos = VodFavoritos.shared
    @ObservedObject private var imagens = LogoLoader.shared
    @State private var ficha: Ficha?
    @State private var carregando = true
    @State private var ator: Ficha.Pessoa?
    @State private var temporada: Int
    @State private var versao: String
    /// Nome, resumo, imagem e duração vindos do TMDB, quando a série tem id.
    @State private var detalhes: [Int: Fichas.EpisodioTMDB] = [:]
    /// O cartão encostado à esquerda da fileira, que as setas empurram.
    @State private var posicao: String?

    /// O episódio por onde a série continua, decidido uma vez ao abrir.
    private let partida: Partida?

    struct Partida {
        let temporada: Int
        let numero: Int
        /// Já começado (ou no ar): o botão diz "Continuar", não "Assistir".
        let comecado: Bool
        let noAr: Bool
    }

    init(model: PlayerModel, serie: Serie, episodios: [Episodio], letra: String,
         voltar: @escaping () -> Void, tocar: @escaping (Episodio) -> Void,
         abrirTitulo: @escaping (Vod.Achado) -> Void) {
        self.model = model
        self.serie = serie
        self.episodios = episodios
        self.letra = letra
        self.voltar = voltar
        self.tocar = tocar
        self.abrirTitulo = abrirTitulo
        let noAr = model.episodioNoAr.flatMap { $0.serie == serie.nomeCompleto ? $0 : nil }
        let partida = Self.ondeContinuar(serie.nomeCompleto, episodios, noAr: noAr)
        self.partida = partida
        _temporada = State(initialValue: partida?.temporada
                           ?? episodios.map(\.temporada).min() ?? 1)
        // A versão do que está no ar; senão a dublada, que é o que a lista
        // toca primeiro em todo lugar.
        let versoes = Set(episodios.map(\.versao))
        _versao = State(initialValue: noAr?.versao
                        ?? (versoes.contains("dub") ? "dub" : versoes.sorted().first ?? "dub"))
    }

    private static func marca(_ t: Int, _ n: Int) -> String { "\(t)-\(n)" }

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
        .onExitCommand { if ator != nil { ator = nil } else { voltar() } }
        .task(id: serie.id) {
            carregando = true
            ficha = await Fichas.de(serie.nomeCompleto, serie: true)
            carregando = false
            if !(ficha?.elenco.isEmpty ?? true) { await Fichas.aquecer() }
        }
        .task(id: temporada) {
            detalhes = [:]
            detalhes = await Fichas.temporada(serie.nomeCompleto, temporada)
        }
    }

    // MARK: - Onde continuar

    /// O episódio no ar; senão o que ficou pela metade mais recentemente;
    /// senão o seguinte ao último assistido; senão o primeiro.
    static func ondeContinuar(_ nome: String, _ lista: [Episodio],
                              noAr: EpisodioNoAr?) -> Partida? {
        if let noAr {
            return Partida(temporada: noAr.temporada, numero: noAr.numero, comecado: true, noAr: true)
        }
        var vistos = Set<String>()
        let ordem = lista.map { ($0.temporada, $0.numero) }
            .sorted { $0 < $1 }
            .filter { vistos.insert(marca($0.0, $0.1)).inserted }
        guard let primeiro = ordem.first else { return nil }

        // O "continue assistindo" já guarda do mais recente para o mais antigo.
        let prefixo = "s|\(nome)|"
        if let andamento = Progresso.emAndamento().first(where: { $0.chave.hasPrefix(prefixo) }) {
            let campos = andamento.chave.dropFirst(prefixo.count).split(separator: "|")
            if campos.count == 2, let t = Int(campos[0]), let n = Int(campos[1]),
               ordem.contains(where: { $0 == (t, n) }) {
                return Partida(temporada: t, numero: n, comecado: true, noAr: false)
            }
        }
        if let ultimo = ordem.lastIndex(where: {
            Progresso.visto(Progresso.chaveEpisodio(nome, $0.0, $0.1))
        }), ultimo + 1 < ordem.count {
            let seguinte = ordem[ultimo + 1]
            return Partida(temporada: seguinte.0, numero: seguinte.1, comecado: true, noAr: false)
        }
        return Partida(temporada: primeiro.0, numero: primeiro.1, comecado: false, noAr: false)
    }

    // MARK: - Dados

    private var temporadas: [Int] { Set(episodios.map(\.temporada)).sorted() }

    /// Dublado primeiro, como no resto do app.
    private var versoes: [String] {
        Set(episodios.map(\.versao)).sorted { ($0 == "leg" ? 1 : 0, $0) < ($1 == "leg" ? 1 : 0, $1) }
    }

    /// Um por número, na versão escolhida quando ela existe.
    private func daTemporada(_ t: Int) -> [Episodio] {
        let daqui = episodios.filter { $0.temporada == t }
        return Set(daqui.map(\.numero)).sorted().compactMap { n in
            let candidatos = daqui.filter { $0.numero == n }
            return candidatos.first { $0.versao == versao } ?? candidatos.first
        }
    }

    private func episodioDaPartida() -> Episodio? {
        guard let partida else { return nil }
        let candidatos = episodios.filter { $0.temporada == partida.temporada && $0.numero == partida.numero }
        return candidatos.first { $0.versao == versao } ?? candidatos.first
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
                // O texto fica sobre o escuro; a série aparece do outro lado.
                LinearGradient(
                    stops: [.init(color: .black.opacity(0.96), location: 0),
                            .init(color: .black.opacity(0.82), location: 0.45),
                            .init(color: .black.opacity(0.15), location: 1)],
                    startPoint: .leading, endPoint: .trailing)
                LinearGradient(colors: [.clear, .black.opacity(0.92)],
                               startPoint: .center, endPoint: .bottom)
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Conteúdo

    private var conteudo: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                botaoVoltar("Voltar", acao: voltar)

                HStack(alignment: .top, spacing: 30) {
                    capa
                    VStack(alignment: .leading, spacing: 12) {
                        Text("SÉRIE")
                            .font(.system(size: 12, weight: .bold))
                            .tracking(2)
                            .foregroundStyle(Tema.acento)
                        titulo
                        if let frase = ficha?.frase, !frase.isEmpty {
                            Text(frase).font(.system(size: 15)).italic()
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(1)
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
                                .lineLimit(4)
                                .frame(maxWidth: 680, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .help(sinopse)
                                .padding(.top, 6)
                        }
                    }
                    Spacer(minLength: 0)
                }

                blocoDeEpisodios

                if let elenco = ficha?.elenco, !elenco.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .lastTextBaseline) {
                            Text("Elenco").font(.system(size: 18, weight: .semibold))
                            Spacer()
                            if let ficha, !ficha.assinatura.isEmpty {
                                Text("Criação: \(ficha.assinatura)")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.6))
                                    .lineLimit(1)
                            }
                        }
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

    /// A logo da série quando o TMDB tem uma; senão o nome escrito.
    @ViewBuilder
    private var titulo: some View {
        let nome = Text(Generos.semAno(serie.titulo))
            .font(.system(size: 38, weight: .bold))
            .lineLimit(2)
            .foregroundStyle(.white)
        if let endereco = ficha?.logo, let url = URL(string: endereco) {
            AsyncImage(url: url) { fase in
                if let imagem = fase.image {
                    imagem.resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 420, maxHeight: 110, alignment: .leading)
                        .shadow(color: .black.opacity(0.6), radius: 8)
                        .accessibilityLabel(serie.titulo)
                } else {
                    nome
                }
            }
        } else {
            nome
        }
    }

    private var capa: some View {
        let endereco = ficha?.capa ?? Generos.capa(serie.nomeCompleto, serie: true)
        return ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.08))
            Text(String(serie.titulo.prefix(1)).uppercased())
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(Tema.acento.opacity(0.7))
            if let endereco, let url = URL(string: endereco) {
                AsyncImage(url: url) { imagem in
                    imagem.resizable().aspectRatio(contentMode: .fill)
                } placeholder: { Color.clear }
            }
        }
        .frame(width: 190, height: 285)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.6), radius: 18, y: 8)
    }

    @ViewBuilder
    private var selos: some View {
        if let ficha {
            HStack(spacing: 8) {
                if ficha.nota > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill").font(.system(size: 11))
                        Text(String(format: "%.1f", ficha.nota))
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.yellow)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.25)))
                }
                if !ficha.ano.isEmpty { Selo(texto: ficha.ano) }
                if let minutos = ficha.duracao, minutos > 0 { Selo(texto: "\(minutos) min/ep") }
                let n = ficha.temporadas ?? temporadas.count
                if n > 0 { Selo(texto: n == 1 ? "1 temporada" : "\(n) temporadas") }
                if let nota = ficha.classificacao, !nota.isEmpty {
                    Selo(texto: nota, cor: corDaClassificacao(nota))
                }
            }
        } else if carregando {
            ProgressView().controlSize(.small)
        } else {
            Selo(texto: temporadas.count == 1 ? "1 temporada" : "\(temporadas.count) temporadas")
        }
    }

    private var botoes: some View {
        let item = VodFavoritos.Item(titulo: serie.titulo, serie: true, letra: letra,
                                     reservado: false, ano: serie.ano)
        let marcado = favoritos.contem(serie.titulo, serie: true, ano: serie.ano)
        let alvo = episodioDaPartida()
        let rotulo: String = {
            guard let partida, let alvo else { return "Assistir" }
            if partida.noAr { return "Voltar ao episódio" }
            let onde = "T\(alvo.temporada) E\(alvo.numero)"
            return partida.comecado ? "Continuar \(onde)" : "Assistir \(onde)"
        }()
        return HStack(spacing: 12) {
            Button {
                if let alvo { tocar(alvo) }
            } label: {
                Label(rotulo, systemImage: "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 26).padding(.vertical, 11)
                    .background(.white, in: RoundedRectangle(cornerRadius: 9))
                    .foregroundStyle(.black)
            }
            .buttonStyle(CresceNoFoco())
            .keyboardShortcut(.defaultAction)
            .disabled(alvo == nil)

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

    // MARK: - Episódios

    private var blocoDeEpisodios: some View {
        let lista = daTemporada(temporada)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Text("Episódios").font(.system(size: 22, weight: .semibold))
                Spacer()
                if versoes.count > 1 {
                    HStack(spacing: 6) {
                        ForEach(versoes, id: \.self) { v in
                            pilula(v == "leg" ? "Legendado" : "Dublado", ativa: versao == v) { versao = v }
                        }
                    }
                }
                setas(lista)
            }

            // As temporadas em pílulas, na mesma fila; trocar de pílula troca
            // a fileira de baixo.
            if temporadas.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(temporadas, id: \.self) { t in
                            pilula("Temporada \(t)", ativa: temporada == t) {
                                guard temporada != t else { return }
                                temporada = t
                                posicao = alvoDaFileira(t)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(lista) { ep in
                        cartao(ep).id(Self.marca(ep.temporada, ep.numero))
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
            }
            .scrollPosition(id: $posicao, anchor: .leading)
            .onAppear {
                // Um ciclo depois: a fileira preguiçosa ainda não montou os cartões.
                let alvo = alvoDaFileira(temporada)
                DispatchQueue.main.async { posicao = alvo }
            }
        }
    }

    /// Onde a fileira começa: um cartão antes do episódio a continuar, para
    /// ele aparecer com o anterior ao lado; nas outras temporadas, o primeiro.
    private func alvoDaFileira(_ t: Int) -> String? {
        let lista = daTemporada(t)
        if let partida, partida.temporada == t,
           let i = lista.firstIndex(where: { $0.numero == partida.numero }) {
            let ep = lista[max(i - 1, 0)]
            return Self.marca(ep.temporada, ep.numero)
        }
        return lista.first.map { Self.marca($0.temporada, $0.numero) }
    }

    /// Setas para quem usa mouse sem rolagem lateral: andam três cartões.
    private func setas(_ lista: [Episodio]) -> some View {
        let marcas = lista.map { Self.marca($0.temporada, $0.numero) }
        let atual = posicao.flatMap { marcas.firstIndex(of: $0) } ?? 0
        func andar(_ passo: Int) {
            guard !marcas.isEmpty else { return }
            let destino = min(max(atual + passo, 0), marcas.count - 1)
            withAnimation(.easeInOut(duration: 0.25)) { posicao = marcas[destino] }
        }
        return HStack(spacing: 6) {
            Button { andar(-3) } label: { seta("chevron.left") }
                .buttonStyle(.plain)
                .disabled(atual == 0)
                .help("Episódios anteriores")
            Button { andar(3) } label: { seta("chevron.right") }
                .buttonStyle(.plain)
                .disabled(atual >= marcas.count - 1)
                .help("Próximos episódios")
        }
    }

    private func seta(_ simbolo: String) -> some View {
        Image(systemName: simbolo)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white.opacity(0.85))
            .frame(width: 30, height: 30)
            .background(Color.white.opacity(0.12), in: Circle())
    }

    private func pilula(_ texto: String, ativa: Bool, acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            Text(texto)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(Capsule().fill(ativa ? Color.white : Color.white.opacity(0.12)))
                .foregroundStyle(ativa ? .black : .white.opacity(0.85))
        }
        .buttonStyle(.plain)
    }

    /// Um episódio: a imagem da cena, número e nome, o resumo e o quanto já
    /// foi visto. O episódio a continuar ganha a moldura da cor do app.
    private func cartao(_ ep: Episodio) -> some View {
        let chave = Progresso.chaveEpisodio(serie.nomeCompleto, ep.temporada, ep.numero)
        let info = detalhes[ep.numero]
        let nome = info.map(\.nome).flatMap { $0.isEmpty ? nil : $0 } ?? "Episódio \(ep.numero)"
        let destaque = partida.map { $0.temporada == ep.temporada && $0.numero == ep.numero } ?? false
        let noAr = destaque && partida?.noAr == true
        let fracao: Double? = noAr
            ? (model.duration > 0 ? min(max(model.position / model.duration, 0), 1) : nil)
            : Progresso.fracao(chave)
        let visto = !noAr && Progresso.visto(chave)
        let linhaDeBaixo = [
            info?.duracao.flatMap { $0 > 0 ? "\($0) min" : nil },
            ep.versao != versao ? (ep.versao == "leg" ? "Legendado" : "Dublado") : nil,
        ].compactMap { $0 }.joined(separator: " · ")

        return Button { tocar(ep) } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                    if let endereco = info?.imagem, let url = URL(string: endereco),
                       let img = imagens.image(for: url) {
                        Image(nsImage: img)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Text("\(ep.numero)")
                            .font(.system(size: 40, weight: .semibold, design: .rounded))
                            .foregroundStyle(Tema.acento.opacity(0.8))
                    }
                }
                .frame(width: 288, height: 162)
                .overlay(alignment: .topLeading) {
                    if destaque {
                        Label(noAr ? "Assistindo" : (partida?.comecado == true ? "Continuar" : "Comece aqui"),
                              systemImage: "play.fill")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Tema.acento, in: Capsule())
                            .foregroundStyle(.white)
                            .padding(8)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if visto {
                        Label("Assistido", systemImage: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(.black.opacity(0.7), in: Capsule())
                            .foregroundStyle(Tema.acento)
                            .padding(8)
                    }
                }
                .overlay(alignment: .bottom) {
                    if let fracao, fracao > 0 {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(Color.white.opacity(0.25))
                                Rectangle().fill(Tema.acento)
                                    .frame(width: geo.size.width * fracao)
                            }
                        }
                        .frame(height: 4)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(destaque ? Tema.acento : .clear, lineWidth: 2))

                Text("\(ep.numero). \(nome)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let sinopse = info?.sinopse, !sinopse.isEmpty {
                    Text(sinopse)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.leading)
                } else {
                    Text(" ").font(.system(size: 12)).lineLimit(2, reservesSpace: true)
                }
                if !linhaDeBaixo.isEmpty {
                    Text(linhaDeBaixo)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(width: 288, alignment: .leading)
        }
        .buttonStyle(CresceNoFoco())
        .help(noAr ? "No ar agora: voltar ao vídeo" : "Assistir o episódio \(ep.numero)")
    }
}
