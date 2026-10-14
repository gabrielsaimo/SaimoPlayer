import SwiftUI

/// O acervo, no lugar do vídeo: as telas da barra do topo que não são o ao
/// vivo — Início, On Demand e as páginas das categorias, Eventos, Favoritos,
/// Rádios, Buscar, Ajustes — e, por trás delas, a grade de A a Z, a ficha e a
/// tela da série.
///
/// As telas em fileiras só dizem o que foi escolhido (`AcoesDoAcervo`); quem
/// sabe abrir a ficha, montar a série e escolher a fonte é esta.
struct VodGridView: View {
    @ObservedObject var model: PlayerModel
    @ObservedObject private var estado = VodEstado.shared
    @ObservedObject private var favoritos = VodFavoritos.shared

    @State private var carregando = false
    /// As fileiras publicadas, baixadas uma vez por abertura da janela.
    @State private var filasDeDestaque: [Destaques.Fila] = []
    /// Os nomes do acervo comum. Serve de peneira para "continue assistindo":
    /// os extras ficam de fora do índice de busca de propósito, e é justamente
    /// esse "de fora" que não pode reaparecer numa fileira da tela inicial.
    @State private var nomesDoAcervo: Set<String> = []
    @State private var selecaoFonte: SelecaoFonte?
    /// O título cuja ficha está aberta, ou nulo.
    @State private var fichaAberta: Cartao?

    private let colunas = [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 20, alignment: .top)]

    private struct OpcaoFonte: Identifiable {
        let versao: String
        let url: String
        let numero: Int
        let total: Int
        /// "4k", "fhd", "hd"… quando a lista de origem anuncia. Vazio é o
        /// caso comum, e não quer dizer ruim: quase nenhuma lista declara.
        let qualidade: String?
        var id: String { "\(numero)|\(url)" }
        var selo: String? { qualidade.map { $0.uppercased() } }
    }

    private struct SelecaoFonte: Identifiable {
        let id = UUID()
        let nome: String
        let detalhe: String
        let chave: String
        let opcoes: [OpcaoFonte]
    }

    var body: some View {
        conteudo
            .task { await abrir() }
            .onChange(of: estado.secao) { antiga, nova in
                // Busca é sempre sobre a seção aberta: carregar "mae" de Extras
                // para Filmes mostraria uma lista que ninguém pediu.
                if antiga != nova { estado.busca = "" }
                Task { await abrir() }
            }
            .onChange(of: estado.explorando) { _, _ in Task { await abrir() } }
            .sheet(item: $selecaoFonte) { selecao in
                seletorDeFontes(selecao)
            }
            .overlay {
                if let cartao = fichaAberta {
                    FichaTela(
                        alvo: FichaAlvo(titulo: cartao.titulo, serie: cartao.serie, ano: cartao.ano,
                                        letra: cartao.letra, reservado: cartao.reservado),
                        assistir: {
                            fichaAberta = nil
                            cartao.abrir()
                        },
                        fechar: { fichaAberta = nil },
                        abrirTitulo: abrirDaFilmografia)
                    // Uma ficha nova para cada título: sem isto, abrir um filme a
                    // partir da filmografia reaproveitava a ficha anterior, que
                    // continuava com o ator aberto por cima do título novo.
                    .id(cartao.id)
                    .contentMargins(.top, Tema.alturaDaBarra, for: .scrollContent)
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: fichaAberta?.id)
    }

    /// O que as telas em fileiras pedem.
    private var acoes: AcoesDoAcervo {
        AcoesDoAcervo(
            abrirTitulo: { abrirDaFilmografia($0) },
            abrirDestaque: { item in
                if item.serie {
                    Task { await abrirDestaque(item) }
                } else {
                    fichaAberta = cartaoDeDestaque(item)
                }
            },
            continuar: { andamento in
                Task { await abrirPorNome(andamento.titulo, serie: andamento.serie) }
            },
            abrirFavorito: { item in
                if item.serie {
                    Task { await abrirFavorito(item) }
                } else {
                    fichaAberta = Cartao(titulo: item.titulo, ano: item.ano, serie: false, detalhe: "Filme",
                                         progresso: Progresso.fracao(Progresso.chaveFilme(item.titulo)),
                                         letra: item.letra, reservado: item.reservado) {
                        Task { await abrirFavorito(item) }
                    }
                }
            },
            abrirColecao: { serie, episodios in
                estado.episodios = episodios
                estado.letraDaSerie = ""
                estado.serieAberta = serie
            })
    }

    // MARK: - Telas

    @ViewBuilder
    private var conteudo: some View {
        if let serie = estado.serieAberta {
            episodiosDe(serie)
        } else {
            switch estado.secao {
            case .inicio:
                TelaInicio(model: model, acoes: acoes, filasDeDestaque: filasDeDestaque,
                           nomesDoAcervo: nomesDoAcervo, carregando: carregando)
            case .ondemand:
                TelaOnDemand(model: model, tipo: nil, acoes: acoes,
                             filasDeDestaque: filasDeDestaque, nomesDoAcervo: nomesDoAcervo)
            case .filmes, .series, .animes, .doramas:
                if estado.explorando {
                    telaDaGrade
                } else {
                    TelaOnDemand(model: model, tipo: estado.secao, acoes: acoes,
                                 filasDeDestaque: filasDeDestaque, nomesDoAcervo: nomesDoAcervo)
                }
            case .eventos:
                EventsView(model: model)
            case .radios:
                TelaRadios()
            case .buscar:
                TelaBusca(model: model, acoes: acoes)
            case .ajustes:
                TelaAjustes(model: model)
            case .favoritos, .extras, nil:
                telaDaGrade
            }
        }
    }

    // MARK: - Fonte

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
                            // A escolhida na frente; as do mesmo idioma atrás,
                            // para o player descer sozinho se ela falhar.
                            let reservas = selecao.opcoes
                                .filter { $0.versao == opcao.versao && $0.url != opcao.url }
                                .map(\.url)
                            tocar(selecao.nome, [opcao.url] + reservas,
                                  detalhe: detalheDaFonte(selecao.detalhe, opcao),
                                  chave: selecao.chave)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text("\(rotulo(opcao.versao)) · Fonte \(opcao.numero) de \(opcao.total)")
                                            .font(.system(size: 14, weight: .medium))
                                        if let selo = opcao.selo {
                                            Text(selo)
                                                .font(.system(size: 10, weight: .bold))
                                                .padding(.horizontal, 5).padding(.vertical, 1)
                                                .background(Tema.acento.opacity(0.85),
                                                            in: Capsule())
                                        }
                                    }
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

    private var gavetasVisiveis: [Vod.Gaveta] {
        estado.gavetas.filter { gaveta in
            switch estado.secao {
            case .extras: return gaveta.reservados > 0
            case .series: return gaveta.series > 0
            case .animes, .doramas: return false
            default: return gaveta.filmes > 0
            }
        }
    }

    private func quantos(_ gaveta: Vod.Gaveta) -> Int {
        switch estado.secao {
        case .extras: return gaveta.reservados
        case .series: return gaveta.series
        case .animes, .doramas: return 0
        default: return gaveta.filmes
        }
    }

    /// Um título do acervo como cartão — é o que a filmografia de um ator abre.
    private func cartaoDe(_ achado: Vod.Achado) -> Cartao {
        Cartao(titulo: achado.titulo,
               ano: achado.ano,
               serie: achado.serie,
               detalhe: achado.serie ? "Série" : "Filme",
               progresso: achado.serie ? nil : Progresso.fracao(Progresso.chaveFilme(achado.titulo)),
               letra: achado.letra,
               reservado: false) {
            Task { await abrirAchado(achado, reservado: false) }
        }
    }

    private func cartaoDeDestaque(_ item: Destaques.Item) -> Cartao {
        // O ano do filme mora dentro do próprio nome no catálogo; o da série,
        // num campo à parte. Somar os dois sem olhar dava "Obsessao (2026)
        // (2026)" na tela.
        let anoNoNome = item.titulo.hasSuffix("(\(item.ano))")
        return Cartao(titulo: item.titulo,
               ano: anoNoNome ? "" : item.ano,
               serie: item.serie,
               detalhe: item.serie ? "Série" : "Filme",
               progresso: item.serie ? nil : Progresso.fracao(Progresso.chaveFilme(item.titulo)),
               letra: item.letra,
               reservado: false) {
            Task { await abrirDestaque(item) }
        }
    }

    /// Abre um destaque.
    ///
    /// Filme e série passam pelo caminho da busca. Anime e dorama moram nas
    /// coleções, que já vêm com os episódios dentro: achando o título ali, dá
    /// para ir direto aos episódios.
    private func abrirDestaque(_ item: Destaques.Item) async {
        if item.daColecao {
            await carregarColecao(item.colecao)
            if let serie = estado.titulosSerie.first(where: {
                $0.titulo.compare(item.titulo, options: .caseInsensitive) == .orderedSame
            }) {
                abrirSerie(serie, letra: "")
                return
            }
            estado.secao = item.colecao
            return
        }
        await abrirAchado(
            Vod.Achado(titulo: item.titulo, serie: item.serie, letra: item.letra, ano: item.ano),
            reservado: false)
    }

    /// O que está pela metade, do mais recente para o mais antigo.
    ///
    /// Só o que existe no acervo comum. O índice de busca deixa os extras de
    /// fora de propósito — "o que não aparece sem o código também não pode
    /// aparecer numa busca geral" —, e a mesma regra vale aqui: a tela inicial
    /// abre sem código nenhum, e não pode ser por onde um título reservado
    /// aparece. Enquanto o índice não chegou, a fileira fica vazia: mostrar de
    /// menos é o erro certo a cometer.
    private var itensEmAndamento: [Cartao] {
        Progresso.emAndamento()
            .filter { nomesDoAcervo.contains($0.titulo) }
            .prefix(20).map { andamento in
            Cartao(titulo: andamento.rotulo,
                   ano: "",
                   serie: andamento.serie,
                   detalhe: andamento.serie ? "Série" : "Filme",
                   progresso: andamento.fracao,
                   letra: "",
                   reservado: false,
                   direto: true) {
                Task { await abrirPorNome(andamento.titulo, serie: andamento.serie) }
            }
        }
    }

    /// O progresso guarda o nome, não a letra; a busca devolve a letra, que é
    /// o que o acervo precisa para achar o título.
    private func abrirPorNome(_ titulo: String, serie: Bool) async {
        let achados = await Vod.todos()
        let alvo = achados.first {
            $0.titulo.compare(titulo, options: .caseInsensitive) == .orderedSame
                && $0.serie == serie
        } ?? achados.first
        guard let alvo else { return }
        await abrirAchado(alvo, reservado: false)
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
        /// "4K" quando alguma fonte do título anuncia essa resolução.
        var selo: String? = nil
        /// Toca sem passar pela ficha: é o caso do "Continue assistindo", em
        /// que a pessoa já sabe o que quer e só quer voltar ao ponto.
        var direto = false
        let abrir: () -> Void
        var nomeCompleto: String { ano.isEmpty ? titulo : "\(titulo) (\(ano))" }
        var id: String { (serie ? "s:" : "f:") + nomeCompleto }
    }

    // MARK: - Grade

    /// Um tipo inteiro em capas, como a grade da TV: as letras numa coluna à
    /// esquerda para pular direto (vinte mil filmes não se descem rolando), e
    /// no alto o nome, quantos são, o gênero, a ordem e a busca.
    private var telaDaGrade: some View {
        let itens = itensDaGrade
        let visiveis = filtrados(itens)
        return VStack(alignment: .leading, spacing: 14) {
            cabecalhoDaGrade(total: visiveis.count)
                .padding(.horizontal, Tema.margem)
            HStack(alignment: .top, spacing: 0) {
                if !gavetasVisiveis.isEmpty, estado.secao != .favoritos {
                    colunaDeLetras
                }
                grade(visiveis)
            }
        }
        .padding(.top, Tema.alturaDaBarra + 14)
    }

    private var itensDaGrade: [Cartao] {
        switch estado.secao {
        case .favoritos: return itensFavoritos
        case .series, .animes, .doramas: return estado.tudo && estado.secao == .series ? itensDeTudo : itensSeries
        default: return estado.tudo ? itensDeTudo : itensFilmes
        }
    }

    private var tituloDaGrade: String {
        guard let secao = estado.secao else { return "Acervo" }
        return secao.ehCategoria ? "\(secao.titulo) de A a Z" : secao.titulo
    }

    private func cabecalhoDaGrade(total: Int) -> some View {
        HStack(alignment: .center, spacing: 12) {
            if estado.secao?.ehCategoria == true {
                botaoVoltar(estado.secao?.titulo ?? "Voltar") {
                    estado.genero = ""
                    estado.explorando = false
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(tituloDaGrade)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                Text(carregando ? "Carregando…" : "\(total.formatted()) títulos"
                     + (estado.genero.isEmpty ? "" : " · \(estado.genero)"))
                    .font(.system(size: 14))
                    .foregroundStyle(Tema.acento)
            }
            Spacer(minLength: 12)
            GrupoDeVidro(espacamento: 8) {
                HStack(spacing: 8) {
                    if !Generos.todos.isEmpty {
                        Menu {
                            Button { estado.genero = "" } label: {
                                Text(estado.genero.isEmpty ? "✓  Todos" : "    Todos")
                            }
                            Divider()
                            ForEach(Generos.todos, id: \.self) { nome in
                                Button { estado.genero = nome } label: {
                                    Text(estado.genero == nome ? "✓  \(nome)" : "    \(nome)")
                                }
                            }
                        } label: {
                            Label(estado.genero.isEmpty ? "Gênero" : estado.genero,
                                  systemImage: "line.3.horizontal.decrease")
                        }
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .botaoDeVidro()
                    }
                    Menu {
                        Button { estado.novosPrimeiro = false } label: {
                            Text(estado.novosPrimeiro ? "    De A a Z" : "✓  De A a Z")
                        }
                        Button { estado.novosPrimeiro = true } label: {
                            Text(estado.novosPrimeiro ? "✓  Mais novos primeiro" : "    Mais novos primeiro")
                        }
                    } label: {
                        Label(estado.novosPrimeiro ? "Mais novos" : "A a Z", systemImage: "arrow.up.arrow.down")
                    }
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .botaoDeVidro()

                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.6))
                        TextField(estado.tudo ? "Buscar nesta lista" : "Buscar na letra", text: $estado.busca)
                            .textFieldStyle(.plain)
                            .frame(width: 180)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .vidroCapsula()
                }
            }
            if carregando { ProgressView().controlSize(.small) }
        }
    }

    /// A lista já sem o que o gênero escolhido deixa de fora, filtrada pela
    /// busca e na ordem escolhida.
    private func filtrados(_ todos: [Cartao]) -> [Cartao] {
        var itens = porGenero(todos)
        if !estado.busca.isEmpty {
            itens = itens.filter { $0.nomeCompleto.localizedCaseInsensitiveContains(estado.busca) }
        }
        if estado.novosPrimeiro {
            itens = itens.enumerated().sorted { a, b in
                let x = CartoesDoAcervo.ano(a.element.titulo, a.element.ano)
                let y = CartoesDoAcervo.ano(b.element.titulo, b.element.ano)
                return x != y ? x > y : a.offset < b.offset
            }.map(\.element)
        }
        return itens
    }

    private func porGenero(_ itens: [Cartao]) -> [Cartao] {
        guard !estado.genero.isEmpty else { return itens }
        return itens.filter { Generos.tem($0.titulo, serie: $0.serie, genero: estado.genero) }
    }

    /// As letras numa coluna, como na TV: "Tudo" põe a seção inteira sob a
    /// mesma busca; cada letra carrega só os títulos dela.
    private var colunaDeLetras: some View {
        ScrollView {
            VStack(spacing: 3) {
                letra("Tudo", ativa: estado.tudo, ajuda: "Todo o acervo desta seção, para buscar de uma vez") {
                    estado.tudo = true
                    estado.serieAberta = nil
                    estado.ancora = nil
                    if estado.achadosDe != estado.secao { estado.achados = [] }
                    Task { await carregarTudo() }
                }
                ForEach(gavetasVisiveis) { gaveta in
                    letra(gaveta.letra, ativa: !estado.tudo && gaveta.letra == estado.letra,
                          ajuda: "\(quantos(gaveta)) títulos") {
                        estado.letra = gaveta.letra
                        estado.tudo = false
                        estado.serieAberta = nil
                        estado.busca = ""
                        estado.ancora = nil
                        Task { await carregar() }
                    }
                }
            }
            .padding(6)
        }
        .scrollIndicators(.hidden)
        .frame(width: 64)
        .vidroPainel(raio: 20)
        .padding(.leading, 18)
        .padding(.bottom, 18)
    }

    private func letra(_ texto: String, ativa: Bool, ajuda: String, acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            Text(texto)
                .font(.system(size: texto.count > 1 ? 12 : 15, weight: ativa ? .bold : .medium))
                .foregroundStyle(ativa ? Color.black : Color.white)
                .frame(width: 48, height: 30)
                .background(Capsule().fill(ativa ? Color.white : Color.clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(ajuda)
    }

    private func grade(_ visiveis: [Cartao]) -> some View {
        if !carregando {
            let vazio = visiveis.isEmpty
            Telemetria.shared.buscou(.vod, estado.busca) { !vazio }
        }
        return Group {
            if visiveis.isEmpty {
                aviso(carregando ? "Carregando…"
                      : estado.secao == .favoritos
                        ? "Nenhum favorito ainda. Clique com o botão direito num título para favoritar."
                        : "Nada aqui")
            } else {
                ScrollViewReader { rolagem in
                    ScrollView {
                        LazyVGrid(columns: colunas, spacing: 26) {
                            ForEach(visiveis) { cartao in
                                celula(cartao).id(cartao.id)
                            }
                        }
                        .padding(.horizontal, 22)
                        .padding(.top, 6)
                        .padding(.bottom, 30)
                    }
                    .scrollIndicators(.hidden)
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
        let item = VodFavoritos.Item(titulo: cartao.titulo, serie: cartao.serie,
                                     letra: cartao.letra, reservado: cartao.reservado,
                                     ano: cartao.ano)
        let marcado = favoritos.contem(cartao.titulo, serie: cartao.serie, ano: cartao.ano)
        // O cartaz abre a ficha, como no celular e na TV Box: saber do que
        // o filme trata antes de gastar dois minutos abrindo a fonte.
        return Button { escolher(cartao) } label: {
            CelulaDaGrade(titulo: cartao.nomeCompleto, serie: cartao.serie, progresso: cartao.progresso,
                          selo: cartao.selo, favorito: marcado, detalhe: cartao.detalhe,
                          procurarAno: cartao.ano.isEmpty
                            && cartao.titulo.range(of: #"\((19|20)\d{2}\)\s*$"#, options: .regularExpression) == nil)
        }
        .buttonStyle(CartaoEmFoco(raio: 10))
        .contextMenu {
            Button(marcado ? "Remover dos favoritos" : "Favoritar") { favoritos.alternar(item) }
            if !cartao.serie, !cartao.direto {
                Button("Assistir sem abrir a ficha") { cartao.abrir() }
            }
        }
        .accessibilityLabel(cartao.nomeCompleto)
        .help(cartao.nomeCompleto)
    }

    /// Série vai direto à tela dela, que já traz a ficha junto dos episódios,
    /// como na TV Box; filme passa pela ficha.
    private func escolher(_ cartao: Cartao) {
        if cartao.direto || cartao.serie { cartao.abrir() } else { fichaAberta = cartao }
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
                   reservado: estado.reservado,
                   selo: seloDoFilme(filme)) {
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
                estado.letraDaSerie = estado.letra
                if let prontos = estado.episodiosColecao[serie.id] {
                    estado.episodios = prontos
                    estado.serieAberta = serie
                } else {
                    abrirSerie(serie, letra: estado.letra)
                }
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

    /// A melhor resolução anunciada entre as fontes do filme, para a capa.
    /// Mostrar também FHD/HD/SD evita que a ausência do selo 4K pareça
    /// qualidade desconhecida.
    private func seloDoFilme(_ filme: Filme) -> String? {
        let melhor = filme.fontes.values.flatMap { $0 }
            .compactMap(Vod.qualidade(de:))
            .min { Vod.posicao(daQualidade: $0) < Vod.posicao(daQualidade: $1) }
        return melhor?.uppercased()
    }

    private func detalheFilme(_ filme: Filme) -> String {
        let versoes = filme.fontes.keys.sorted().map(rotulo).joined(separator: " · ")
        let fontes = filme.fontes.values.reduce(0) { $0 + $1.count }
        return fontes > 1 ? "\(versoes) · \(fontes) fontes" : versoes
    }

    // MARK: - Episódios

    /// A série aberta, com a ficha e os episódios na mesma tela (`SerieTela`).
    private func episodiosDe(_ serie: Serie) -> some View {
        SerieTela(model: model, serie: serie, episodios: estado.episodios,
                  letra: estado.letraDaSerie,
                  voltar: { estado.serieAberta = nil },
                  tocar: { tocarEpisodio(serie, $0) },
                  abrirTitulo: abrirDaFilmografia)
            // Uma tela nova para cada série: a temporada e a fileira de uma
            // não podem vazar para a seguinte.
            .id(serie.id)
            // O conteúdo começa abaixo da barra de vidro; a imagem larga
            // continua passando por baixo dela.
            .contentMargins(.top, Tema.alturaDaBarra, for: .scrollContent)
    }

    private func tocarEpisodio(_ serie: Serie, _ episodio: Episodio) {
        // O episódio que já está no ar só devolve ao vídeo: abrir de novo
        // recomeçaria do zero o que estava tocando.
        if let noAr = model.episodioNoAr, noAr.serie == serie.nomeCompleto,
           noAr.temporada == episodio.temporada, noAr.numero == episodio.numero,
           noAr.versao == episodio.versao {
            estado.secao = nil
            return
        }
        let chave = Progresso.chaveEpisodio(
            serie.nomeCompleto, episodio.temporada, episodio.numero)
        model.episodioPendente = EpisodioNoAr(
            serie: serie.nomeCompleto, temporada: episodio.temporada,
            numero: episodio.numero, versao: episodio.versao, lista: estado.episodios)
        let detalhe = "Temporada \(episodio.temporada), episódio \(episodio.numero)"
        // Série que já vem tocando: a fonte de sempre vai no topo da lista,
        // e um clique (ou Enter) a mantém. A pessoa ainda escolhe outra.
        let preferidas = model.fontesPreferidas(serie: serie.nomeCompleto, urls: episodio.urls)
        escolherFonte(nome: serie.nomeCompleto,
                      fontes: [episodio.versao: preferidas],
                      detalhe: detalhe,
                      chave: chave,
                      manterOrdem: model.fonteLembrada(serie.nomeCompleto))
    }

    /// Um título vindo da filmografia de um ator: filme abre a ficha, série
    /// abre a tela dela, que já é ficha e episódios ao mesmo tempo.
    private func abrirDaFilmografia(_ achado: Vod.Achado) {
        if achado.serie {
            fichaAberta = nil
            Task { await abrirAchado(achado, reservado: false) }
        } else {
            fichaAberta = cartaoDe(achado)
        }
    }

    // MARK: - Ações

    private func abrir() async {
        guard let secao = estado.secao else { return }
        await Generos.carregar()
        if estado.gavetas.isEmpty { estado.gavetas = await Vod.indice() }
        estado.filmes = secao.pedeFilmes
        estado.reservado = secao == .extras
        let emFileiras = secao == .inicio || secao == .ondemand || (secao.ehCategoria && !estado.explorando)
        if emFileiras {
            if filasDeDestaque.isEmpty {
                carregando = true
                filasDeDestaque = await Destaques.filas()
                carregando = false
            }
            if nomesDoAcervo.isEmpty {
                nomesDoAcervo = Set(await Vod.todos().map(\.titulo))
            }
            await Generos.carregar()
            return
        }
        // Telas que cuidam do que mostram.
        guard ![.eventos, .radios, .buscar, .ajustes, .favoritos].contains(secao) else { return }
        if secao == .animes || secao == .doramas {
            await carregarColecao(secao)
            return
        }
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

    private func carregarColecao(_ secao: VodSecao) async {
        carregando = true
        defer { carregando = false }
        let tipo = secao == .animes ? "animes" : "doramas"
        let itens = await Vod.colecao(tipo)
        estado.titulosSerie = itens.map(\.0).sorted {
            $0.titulo.localizedCaseInsensitiveCompare($1.titulo) == .orderedAscending
        }
        estado.episodiosColecao = Dictionary(uniqueKeysWithValues: itens.map { ($0.0.id, $0.1) })
        estado.titulosFilme = []
        estado.tudo = false
    }

    private func abrirSerie(_ serie: Serie, letra: String) {
        Task {
            carregando = true
            estado.episodios = await Vod.episodios(letra: letra, serie: serie)
            carregando = false
            estado.letraDaSerie = letra
            estado.serieAberta = serie
        }
    }

    private func tocarFilme(_ filme: Filme) {
        model.episodioPendente = nil
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
            estado.letraDaSerie = item.letra
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
                               detalhe: String, chave: String,
                               manterOrdem: Bool = false) {
        let ordenadas = fontes.keys.sorted {
            let esquerda = ($0 == "leg" ? 1 : 0, $0)
            let direita = ($1 == "leg" ? 1 : 0, $1)
            return esquerda < direita
        }
        let pares = ordenadas.flatMap { versao -> [(String, String)] in
            // Dentro de um idioma, a de maior resolução primeiro: é ela que
            // toca quando ninguém escolhe nada.
            let original = fontes[versao] ?? []
            let lista = manterOrdem ? original : original.sorted {
                Vod.posicao(daQualidade: Vod.qualidade(de: $0))
                    < Vod.posicao(daQualidade: Vod.qualidade(de: $1))
            }
            return lista.map { (versao, $0) }
        }
        let opcoes = pares.enumerated().map { indice, par in
            OpcaoFonte(versao: par.0, url: par.1, numero: indice + 1,
                       total: pares.count, qualidade: Vod.qualidade(de: par.1))
        }
        guard let unica = opcoes.first else { return }
        // Uma fonte abre direto. Duas ou mais aparecem sempre, mesmo quando
        // todas são dubladas: servidor e resolução podem ser diferentes e a
        // pessoa precisa escolher antes de abrir o episódio.
        if opcoes.count == 1 {
            tocar(nome, [unica.url],
                  detalhe: detalheDaFonte(detalhe, unica), chave: chave)
        } else {
            selecaoFonte = SelecaoFonte(nome: nome, detalhe: detalhe,
                                        chave: chave, opcoes: opcoes)
        }
    }

    private func detalheDaFonte(_ base: String, _ opcao: OpcaoFonte) -> String {
        let selo = opcao.selo.map { " · \($0)" } ?? ""
        return "\(base) · \(rotulo(opcao.versao))\(selo) · Fonte \(opcao.numero) de \(opcao.total)"
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

/// Uma capa da grade: o pôster, a barra do quanto foi visto, o selo de
/// resolução, a estrela do favorito e, embaixo, o nome e o detalhe.
///
/// Mais da metade do acervo chega sem ano no título; o ano vem do mesmo TMDB
/// que já é consultado para a capa, e só aparece quando a resposta chega.
private struct CelulaDaGrade: View {
    let titulo: String
    let serie: Bool
    let progresso: Double?
    let selo: String?
    let favorito: Bool
    let detalhe: String
    let procurarAno: Bool
    @ObservedObject private var capas = Capas.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Tema.cartao)
                ImagemRemota(endereco: Generos.capa(titulo, serie: serie)) {
                    if let imagem = capas.imagem(para: titulo, serie: serie) {
                        Image(nsImage: imagem).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: serie ? "tv" : "film")
                            .font(.system(size: 26))
                            .foregroundStyle(.white.opacity(0.25))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                if let progresso, progresso > 0 {
                    BarraDeProgresso(fracao: progresso)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                }
            }
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .topLeading) {
                if let selo {
                    Text(selo)
                        .font(.system(size: 10, weight: .heavy))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.black.opacity(0.65), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(6)
                }
            }
            .overlay(alignment: .topTrailing) {
                if favorito {
                    Image(systemName: "star.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.yellow)
                        .padding(5)
                        .background(.black.opacity(0.5), in: Circle())
                        .padding(6)
                }
            }
            .shadow(color: .black.opacity(0.35), radius: 8, y: 4)

            Text(titulo)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(2, reservesSpace: true)
                .foregroundStyle(.white)
            Text(detalheComAno)
                .font(.system(size: 11))
                .foregroundStyle(Tema.textoSecundario)
                .lineLimit(1)
        }
    }

    private var detalheComAno: String {
        guard procurarAno, let ano = capas.ano(para: titulo, serie: serie) else { return detalhe }
        return "\(ano) · \(detalhe)"
    }
}
