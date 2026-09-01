import SwiftUI

/// O acervo em grade, no lugar do vídeo.
///
/// Escolher filme por lista de texto é escolher no escuro: o que identifica um
/// filme é a capa. A grade ocupa a área do player inteira, com as capas grandes
/// o bastante para reconhecer de longe, e a letra fica numa régua no topo, de
/// modo que percorrer o acervo seja um gesto só.
struct VodGridView: View {
    @ObservedObject var model: PlayerModel
    @ObservedObject private var estado = VodEstado.shared
    @ObservedObject private var capas = Capas.shared
    @ObservedObject private var favoritos = VodFavoritos.shared

    @State private var carregando = false
    @State private var selecaoFonte: SelecaoFonte?

    private let colunas = [GridItem(.adaptive(minimum: 168, maximum: 220), spacing: 18)]

    private struct OpcaoFonte: Identifiable {
        let versao: String
        let url: String
        let numero: Int
        let total: Int
        var id: String { "\(numero)|\(url)" }
    }

    private struct SelecaoFonte: Identifiable {
        let id = UUID()
        let nome: String
        let detalhe: String
        let chave: String
        let opcoes: [OpcaoFonte]
    }

    var body: some View {
        VStack(spacing: 0) {
            cabecalho
            Divider()
            if estado.secao != .favoritos { reguaDeLetras; Divider() }
            conteudo
        }
        .background(Color.black)
        .task { await abrir() }
        .onChange(of: estado.secao) { antiga, nova in
            // Busca é sempre sobre a seção aberta: carregar "mae" de Extras
            // para Filmes mostraria uma lista que ninguém pediu.
            if antiga != nova { estado.busca = "" }
            Task { await abrir() }
        }
        .sheet(item: $selecaoFonte) { selecao in
            seletorDeFontes(selecao)
        }
    }

    // MARK: - Topo

    private func seletorDeFontes(_ selecao: SelecaoFonte) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(selecao.nome)
                .font(.title2.weight(.semibold))
            Text("Escolha a fonte")
                .foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(selecao.opcoes) { opcao in
                        Button {
                            selecaoFonte = nil
                            tocar(selecao.nome, [opcao.url],
                                  detalhe: detalheDaFonte(selecao.detalhe, opcao),
                                  chave: selecao.chave)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(rotulo(opcao.versao)) · Fonte \(opcao.numero) de \(opcao.total)")
                                        .font(.system(size: 14, weight: .medium))
                                    Text(origem(opcao.url))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "play.fill")
                            }
                            .padding(10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(Color.white.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            Button("Cancelar", role: .cancel) { selecaoFonte = nil }
                .keyboardShortcut(.cancelAction)
        }
        .padding(22)
        .frame(minWidth: 440, minHeight: 260)
    }

    private var cabecalho: some View {
        HStack(spacing: 12) {
            Text(estado.secao?.titulo ?? "Acervo")
                .font(.system(size: 20, weight: .semibold))
            if let serie = estado.serieAberta {
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                Text(serie.nomeCompleto).font(.system(size: 17))
                Button {
                    estado.serieAberta = nil
                } label: {
                    Label("Voltar", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            if carregando { ProgressView().controlSize(.small) }
            Spacer()
            TextField(estado.tudo ? "Buscar em todo o acervo" : "Buscar", text: $estado.busca)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
            Button {
                estado.secao = nil
            } label: {
                Label("Fechar", systemImage: "xmark")
            }
            .help("Voltar ao vídeo")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    /// Vinte e sete letras não cabem numa coluna sem roubar a tela da grade;
    /// numa régua, cabem todas e sobra espaço para as capas.
    private var reguaDeLetras: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // Procurar um título sem saber a letra dele é o caso comum;
                // "Tudo" põe o acervo inteiro sob a mesma busca — o da seção
                // aberta: em Filmes só filmes, em Séries só séries, em Extras
                // só extras.
                Button {
                    estado.tudo = true
                    estado.serieAberta = nil
                    estado.ancora = nil
                    if estado.achadosDe != estado.secao { estado.achados = [] }
                    Task { await carregarTudo() }
                } label: {
                    Text("Tudo")
                        .font(.system(size: 13, weight: estado.tudo ? .bold : .regular))
                        .padding(.vertical, 5)
                        .padding(.horizontal, 10)
                        .background(estado.tudo ? Color.accentColor.opacity(0.35) : Color.white.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Todo o acervo desta seção, para buscar de uma vez")

                ForEach(gavetasVisiveis) { gaveta in
                    let ativa = !estado.tudo && gaveta.letra == estado.letra
                    Button {
                        estado.letra = gaveta.letra
                        estado.tudo = false
                        estado.serieAberta = nil
                        estado.busca = ""
                        estado.ancora = nil
                        Task { await carregar() }
                    } label: {
                        Text(gaveta.letra)
                            .font(.system(size: 13, weight: ativa ? .bold : .regular))
                            .frame(minWidth: 26)
                            .padding(.vertical, 5)
                            .padding(.horizontal, 6)
                            .background(ativa ? Color.accentColor.opacity(0.35) : Color.white.opacity(0.06),
                                        in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help("\(quantos(gaveta)) títulos")
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
        }
    }

    private var gavetasVisiveis: [Vod.Gaveta] {
        estado.gavetas.filter { gaveta in
            switch estado.secao {
            case .extras: return gaveta.reservados > 0
            case .series: return gaveta.series > 0
            default: return gaveta.filmes > 0
            }
        }
    }

    private func quantos(_ gaveta: Vod.Gaveta) -> Int {
        switch estado.secao {
        case .extras: return gaveta.reservados
        case .series: return gaveta.series
        default: return gaveta.filmes
        }
    }

    // MARK: - Grade

    @ViewBuilder
    private var conteudo: some View {
        if let serie = estado.serieAberta {
            episodiosDe(serie)
        } else if estado.secao == .favoritos {
            grade(itensFavoritos)
        } else if estado.tudo {
            grade(itensDeTudo)
        } else if estado.letra.isEmpty {
            aviso("Escolha uma letra")
        } else if estado.secao == .series {
            grade(itensSeries)
        } else {
            grade(itensFilmes)
        }
    }

    /// O que uma célula precisa mostrar, venha de filme, série ou favorito.
    private struct Cartao: Identifiable {
        let titulo: String
        let ano: String
        let serie: Bool
        let detalhe: String
        let progresso: Double?
        let letra: String
        let reservado: Bool
        let abrir: () -> Void
        var nomeCompleto: String { ano.isEmpty ? titulo : "\(titulo) (\(ano))" }
        var id: String { (serie ? "s:" : "f:") + nomeCompleto }
    }

    private func grade(_ itens: [Cartao]) -> some View {
        let visiveis = estado.busca.isEmpty ? itens : itens.filter {
            $0.nomeCompleto.localizedCaseInsensitiveContains(estado.busca)
        }
        return Group {
            if visiveis.isEmpty {
                aviso(carregando ? "Carregando…" : "Nada aqui")
            } else {
                ScrollViewReader { rolagem in
                    ScrollView {
                        LazyVGrid(columns: colunas, spacing: 22) {
                            ForEach(visiveis) { cartao in
                                celula(cartao).id(cartao.id)
                            }
                        }
                        .padding(18)
                    }
                    .onAppear {
                        guard let alvo = estado.ancora else { return }
                        // Um quadro depois: a grade precisa existir antes de
                        // saber rolar até uma célula dela.
                        DispatchQueue.main.async { rolagem.scrollTo(alvo, anchor: .center) }
                    }
                }
            }
        }
    }

    private func celula(_ cartao: Cartao) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .bottom) {
                capa(cartao.nomeCompleto, serie: cartao.serie)
                if let visto = cartao.progresso {
                    // A barra vai na própria capa: é onde o olho já está.
                    ProgressView(value: visto)
                        .progressViewStyle(.linear)
                        .tint(.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.bottom, 6)
                }
            }
            .overlay(alignment: .topTrailing) { estrela(cartao) }
            .contentShape(Rectangle())
            .onTapGesture { cartao.abrir() }

            Text(cartao.nomeCompleto)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(2, reservesSpace: true)
                .foregroundStyle(.white)
            Text(cartao.detalhe)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
        }
        .help(cartao.nomeCompleto)
    }

    private func estrela(_ cartao: Cartao) -> some View {
        let item = VodFavoritos.Item(titulo: cartao.titulo, serie: cartao.serie,
                                     letra: cartao.letra, reservado: cartao.reservado,
                                     ano: cartao.ano)
        let marcado = favoritos.contem(cartao.titulo, serie: cartao.serie, ano: cartao.ano)
        return Button {
            favoritos.alternar(item)
        } label: {
            Image(systemName: marcado ? "star.fill" : "star")
                .font(.system(size: 12, weight: .semibold))
                .padding(5)
                .background(.black.opacity(0.45), in: Circle())
                .foregroundStyle(marcado ? .yellow : .white.opacity(0.8))
        }
        .buttonStyle(.plain)
        .padding(6)
        .help(marcado ? "Remover dos favoritos" : "Favoritar")
    }

    /// A capa chega da rede quando a célula aparece; até lá a moldura segura o
    /// lugar, para a grade não pular de altura enquanto rola.
    private func capa(_ titulo: String, serie: Bool) -> some View {
        let imagem = capas.imagem(para: titulo, serie: serie)
        return ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.07))
            if let imagem {
                Image(nsImage: imagem)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: serie ? "tv" : "film")
                    .font(.system(size: 26))
                    .foregroundStyle(.white.opacity(0.25))
            }
        }
        .frame(height: 250)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Itens

    private var itensFilmes: [Cartao] {
        estado.titulosFilme.map { filme in
            Cartao(titulo: filme.titulo,
                   ano: "",
                   serie: false,
                   detalhe: detalheFilme(filme),
                   progresso: Progresso.fracao(Progresso.chaveFilme(filme.titulo)),
                   letra: estado.letra,
                   reservado: estado.reservado) {
                tocarFilme(filme)
            }
        }
    }

    private var itensSeries: [Cartao] {
        estado.titulosSerie.map { serie in
            Cartao(titulo: serie.titulo,
                   ano: serie.ano,
                   serie: true,
                   detalhe: "\(serie.episodios) episódios",
                   progresso: nil,
                   letra: estado.letra,
                   reservado: false) {
                estado.ancora = "s:" + serie.nomeCompleto
                abrirSerie(serie, letra: estado.letra)
            }
        }
    }

    /// O índice só tem nome, tipo e letra; as fontes ficam para a hora de
    /// abrir, que é quando vale a pena baixar o pedaço daquela letra.
    private var itensDeTudo: [Cartao] {
        estado.achados.filter { $0.serie == (estado.secao == .series) }.map { achado in
            Cartao(titulo: achado.titulo,
                   ano: achado.ano,
                   serie: achado.serie,
                   detalhe: achado.serie ? "Série" : "Filme",
                   progresso: achado.serie ? nil
                       : Progresso.fracao(Progresso.chaveFilme(achado.titulo)),
                   letra: achado.letra,
                   reservado: estado.secao == .extras) {
                Task { await abrirAchado(achado, reservado: estado.secao == .extras) }
            }
        }
    }

    private var itensFavoritos: [Cartao] {
        favoritos.itens.map { item in
            Cartao(titulo: item.titulo,
                   ano: item.ano,
                   serie: item.serie,
                   detalhe: item.serie ? "Série" : "Filme",
                   progresso: item.serie ? nil
                       : Progresso.fracao(Progresso.chaveFilme(item.titulo)),
                   letra: item.letra,
                   reservado: item.reservado) {
                Task { await abrirFavorito(item) }
            }
        }
    }

    private func detalheFilme(_ filme: Filme) -> String {
        let versoes = filme.fontes.keys.sorted().map(rotulo).joined(separator: " · ")
        let fontes = filme.fontes.values.reduce(0) { $0 + $1.count }
        return fontes > 1 ? "\(versoes) · \(fontes) fontes" : versoes
    }

    // MARK: - Episódios

    private func episodiosDe(_ serie: Serie) -> some View {
        let temporadas = Set(estado.episodios.map(\.temporada)).sorted()
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(temporadas, id: \.self) { temporada in
                    Text("Temporada \(temporada)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.top, 18)
                        .padding(.horizontal, 18)
                    ForEach(daTemporada(temporada)) { episodio in
                        linhaEpisodio(serie, episodio)
                        Divider().padding(.leading, 18)
                    }
                }
            }
        }
    }

    private func daTemporada(_ temporada: Int) -> [Episodio] {
        estado.episodios.filter { $0.temporada == temporada }
            .sorted { ($0.numero, $0.versao) < ($1.numero, $1.versao) }
    }

    private func linhaEpisodio(_ serie: Serie, _ episodio: Episodio) -> some View {
        let chave = Progresso.chaveEpisodio(
            serie.nomeCompleto, episodio.temporada, episodio.numero)
        let detalhe = "Temporada \(episodio.temporada), episódio \(episodio.numero)"
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Episódio \(episodio.numero)").foregroundStyle(.white)
                    Text(rotulo(episodio.versao))
                        .font(.caption).foregroundStyle(.white.opacity(0.5))
                    if episodio.urls.count > 1 {
                        Text("\(episodio.urls.count) fontes")
                            .font(.caption).foregroundStyle(.white.opacity(0.5))
                    }
                }
                if let visto = Progresso.fracao(chave) {
                    ProgressView(value: visto)
                        .progressViewStyle(.linear)
                        .frame(width: 220)
                        .controlSize(.mini)
                }
            }
            Spacer()
            Button("Assistir") {
                escolherFonte(nome: serie.nomeCompleto,
                              fontes: [episodio.versao: episodio.urls],
                              detalhe: detalhe, chave: chave)
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    // MARK: - Ações

    private func abrir() async {
        guard let secao = estado.secao else { return }
        if estado.gavetas.isEmpty { estado.gavetas = await Vod.indice() }
        estado.filmes = secao.pedeFilmes
        estado.reservado = secao == .extras
        guard secao != .favoritos else { return }
        if estado.tudo {
            if estado.achados.isEmpty || estado.achadosDe != secao { await carregarTudo() }
            return
        }
        // A letra escolhida antes continua valendo; só quando ela não serve
        // para esta seção é que se começa do zero.
        if !gavetasVisiveis.contains(where: { $0.letra == estado.letra }) {
            estado.letra = gavetasVisiveis.first?.letra ?? ""
            estado.titulosFilme = []
            estado.titulosSerie = []
        }
        await carregar()
    }

    private func carregar() async {
        guard !estado.letra.isEmpty else { return }
        carregando = true
        defer { carregando = false }
        if estado.secao == .series {
            estado.titulosSerie = await Vod.series(letra: estado.letra)
            estado.titulosFilme = []
        } else {
            estado.titulosFilme = await Vod.filmes(letra: estado.letra,
                                                   reservados: estado.reservado)
            estado.titulosSerie = []
        }
    }

    private func abrirSerie(_ serie: Serie, letra: String) {
        Task {
            carregando = true
            estado.episodios = await Vod.episodios(letra: letra, serie: serie)
            carregando = false
            estado.serieAberta = serie
        }
    }

    private func tocarFilme(_ filme: Filme) {
        escolherFonte(nome: filme.titulo, fontes: filme.fontes, detalhe: "Filme",
                      chave: Progresso.chaveFilme(filme.titulo))
    }

    private func carregarTudo() async {
        carregando = true
        defer { carregando = false }
        if estado.secao == .extras {
            // Fora do índice de busca, então a lista sai dos arquivos por letra.
            estado.achados = await Vod.todosReservados(gavetasVisiveis.map(\.letra))
        } else {
            estado.achados = await Vod.todos()
        }
        estado.achadosDe = estado.secao
    }

    private func abrirAchado(_ achado: Vod.Achado, reservado: Bool) async {
        await abrirFavorito(VodFavoritos.Item(titulo: achado.titulo, serie: achado.serie,
                                              letra: achado.letra, reservado: reservado,
                                              ano: achado.ano))
    }

    private func abrirFavorito(_ item: VodFavoritos.Item) async {
        carregando = true
        defer { carregando = false }
        if item.serie {
            guard let achada = await Vod.series(letra: item.letra)
                .first(where: {
                    $0.titulo == item.titulo && (item.ano.isEmpty || $0.ano == item.ano)
                }) else { return }
            estado.episodios = await Vod.episodios(letra: item.letra, serie: achada)
            estado.serieAberta = achada
        } else {
            guard let achado = await Vod.filmes(letra: item.letra, reservados: item.reservado)
                .first(where: { $0.titulo == item.titulo }) else { return }
            tocarFilme(achado)
        }
    }

    /// Uma única fonte abre direto. Com duas ou mais, nenhuma ganha prioridade
    /// escondida: idioma, número e servidor ficam visíveis antes do play.
    private func escolherFonte(nome: String, fontes: [String: [String]],
                               detalhe: String, chave: String) {
        let ordenadas = fontes.keys.sorted {
            let esquerda = ($0 == "leg" ? 1 : 0, $0)
            let direita = ($1 == "leg" ? 1 : 0, $1)
            return esquerda < direita
        }
        let pares = ordenadas.flatMap { versao in
            (fontes[versao] ?? []).map { (versao, $0) }
        }
        let opcoes = pares.enumerated().map { indice, par in
            OpcaoFonte(versao: par.0, url: par.1,
                       numero: indice + 1, total: pares.count)
        }
        guard let unica = opcoes.first else { return }
        if opcoes.count == 1 {
            tocar(nome, [unica.url], detalhe: detalheDaFonte(detalhe, unica), chave: chave)
        } else {
            selecaoFonte = SelecaoFonte(nome: nome, detalhe: detalhe,
                                        chave: chave, opcoes: opcoes)
        }
    }

    private func detalheDaFonte(_ base: String, _ opcao: OpcaoFonte) -> String {
        "\(base) · \(rotulo(opcao.versao)) · Fonte \(opcao.numero) de \(opcao.total)"
    }

    private func origem(_ url: String) -> String {
        URL(string: url)?.host?.replacingOccurrences(of: "www.", with: "")
            ?? "Servidor não identificado"
    }

    private func tocar(_ nome: String, _ urls: [String], detalhe: String, chave: String) {
        let destinos = urls.compactMap(URL.init(string:))
        guard !destinos.isEmpty else { return }
        // Guarda onde a pessoa estava: é para esta célula que a grade volta
        // quando ela reabrir para escolher o próximo.
        estado.ancora = estado.serieAberta.map { "s:" + $0.nomeCompleto } ?? ("f:" + nome)
        model.playFile(destinos, nome: nome, detalhe: detalhe, chave: chave)
        estado.secao = nil
    }

    private func rotulo(_ versao: String) -> String {
        versao == "leg" ? "Legendado" : "Dublado"
    }

    private func aviso(_ texto: String) -> some View {
        VStack {
            Spacer()
            Text(texto).foregroundStyle(.white.opacity(0.5))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
