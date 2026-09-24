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
    /// As fileiras publicadas, baixadas uma vez por abertura da janela.
    @State private var filasDeDestaque: [Destaques.Fila] = []
    /// Os nomes do acervo comum. Serve de peneira para "continue assistindo":
    /// os extras ficam de fora do índice de busca de propósito, e é justamente
    /// esse "de fora" que não pode reaparecer numa fileira da tela inicial.
    @State private var nomesDoAcervo: Set<String> = []
    /// O gênero escolhido na régua, ou vazio para todos.
    @State private var genero = ""
    @State private var selecaoFonte: SelecaoFonte?
    /// O título cuja ficha está aberta, ou nulo.
    @State private var fichaAberta: Cartao?

    private let colunas = [GridItem(.adaptive(minimum: 168, maximum: 220), spacing: 18)]

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
        VStack(spacing: 0) {
            cabecalho
            Divider()
            // A régua só onde ela filtra alguma coisa: na tela inicial as
            // fileiras são curadoria, e peneirá-las deixa faixas com um cartão
            // ou nenhum.
            if !Generos.todos.isEmpty, estado.secao != .inicio { reguaDeGeneros; Divider() }

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
        .sheet(item: $fichaAberta) { cartao in
            FichaView(titulo: cartao.titulo, serie: cartao.serie, ano: cartao.ano) { achado in
                Task { await abrirAchado(achado, reservado: false) }
            }
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
                                                .background(Color.accentColor.opacity(0.85),
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
            secoesNoTopo
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

    /// As seções ao lado da busca.
    ///
    /// Elas existiam só na lateral dos canais, que fica atrás do acervo: com o
    /// acervo aberto, trocar de Filmes para Séries obrigava a fechar tudo e
    /// voltar. Aqui em cima, ao lado da busca, ficam as duas coisas que alguém
    /// quer enquanto procura — e é onde o site e a TV Box já as põem.
    ///
    /// Extras só aparece com o código digitado, como em todo lugar.
    private var secoesNoTopo: some View {
        HStack(spacing: 6) {
            ForEach(secoesVisiveis) { secao in
                Button {
                    if estado.secao != secao {
                        estado.serieAberta = nil
                        estado.secao = secao
                    }
                } label: {
                    Text(secao.titulo)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(estado.secao == secao
                                           ? Color.accentColor.opacity(0.85)
                                           : Color.white.opacity(0.10)))
                        .foregroundStyle(estado.secao == secao ? .white : .primary)
                }
                .buttonStyle(.plain)
                .help(secao.titulo)
            }
        }
    }

    private var secoesVisiveis: [VodSecao] {
        var out: [VodSecao] = [.inicio, .filmes, .series, .animes, .doramas]
        if !favoritos.itens.isEmpty { out.append(.favoritos) }
        if model.restrictedUnlocked { out.append(.extras) }
        return out
    }

    /// Os gêneros, numa régua como a das letras.
    ///
    /// O catálogo não tem gênero; ele vem de um arquivo publicado à parte. Por
    /// isso a régua só existe quando esse arquivo chegou — oferecer um filtro
    /// que devolve vazio é pior que não oferecer.
    private var reguaDeGeneros: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                pilulaDeGenero("Todos", valor: "")
                ForEach(Generos.todos, id: \.self) { nome in
                    pilulaDeGenero(nome, valor: nome)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 7)
        }
    }

    private func pilulaDeGenero(_ texto: String, valor: String) -> some View {
        Button {
            genero = (genero == valor) ? "" : valor
        } label: {
            Text(texto)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(genero == valor
                                           ? Color.accentColor.opacity(0.85)
                                           : Color.white.opacity(0.10)))
                .foregroundStyle(genero == valor ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    /// A lista já sem o que o gênero escolhido deixa de fora.
    private func porGenero(_ itens: [Cartao]) -> [Cartao] {
        guard !genero.isEmpty else { return itens }
        return itens.filter { Generos.tem($0.titulo, serie: $0.serie, genero: genero) }
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

    // MARK: - Início

    /// A primeira tela do acervo: fileiras de capa que correm para o lado.
    ///
    /// Uma grade alfabética serve para achar o que já se sabe que existe; não
    /// serve para descobrir. As fileiras mostram o que há — o que estava sendo
    /// assistido, o que foi marcado, o que está em alta — e a busca continua no
    /// mesmo lugar, filtrando dentro delas.
    ///
    /// As capas dos destaques chegam prontas do repositório, então abrir esta
    /// tela não pergunta nada ao TMDB. Só "continue" e favoritos procuram capa,
    /// e são poucas.
    @ViewBuilder
    private var fileiras: some View {
        let visiveis = filasVisiveis
        if visiveis.isEmpty {
            aviso(carregando ? "Carregando…" : "Nada aqui")
        } else {
            ScrollView {
                // O espaço entre fileiras é maior que o de dentro delas de
                // propósito: é ele que faz o olho ler "outra fileira" em vez
                // de uma grade contínua. Com pouco, o nome da fileira parece
                // pertencer aos cartões de cima.
                LazyVStack(alignment: .leading, spacing: 38) {
                    ForEach(visiveis) { fila in
                        VStack(alignment: .leading, spacing: 14) {
                            Text(fila.titulo)
                                .font(.title3.weight(.semibold))
                                .padding(.horizontal, 22)
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(alignment: .top, spacing: 18) {
                                    ForEach(fila.cartoes) { cartao in
                                        celula(cartao).frame(width: 150)
                                    }
                                }
                                .padding(.horizontal, 22)
                                // A estrela e a moldura do foco passam da
                                // borda do cartão; sem esta folga elas saem
                                // cortadas pela rolagem.
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
                .padding(.vertical, 22)
            }
        }
    }

    private struct FilaNaTela: Identifiable {
        let titulo: String
        let cartoes: [Cartao]
        var id: String { titulo }
    }

    /// As fileiras já filtradas pela busca: digitar procura dentro do que está
    /// à vista, e a fileira que ficou sem nada sai da tela.
    private var filasVisiveis: [FilaNaTela] {
        var out: [FilaNaTela] = []
        if !itensEmAndamento.isEmpty {
            out.append(FilaNaTela(titulo: "Continue assistindo", cartoes: itensEmAndamento))
        }
        if !itensFavoritos.isEmpty {
            out.append(FilaNaTela(titulo: "Favoritos", cartoes: itensFavoritos))
        }
        for fila in filasDeDestaque {
            let cartoes = fila.itens.map { cartaoDeDestaque($0) }
            if !cartoes.isEmpty { out.append(FilaNaTela(titulo: fila.titulo, cartoes: cartoes)) }
        }
        guard !estado.busca.isEmpty else { return out }
        return out.compactMap { fila in
            let filtrados = fila.cartoes.filter {
                $0.nomeCompleto.localizedCaseInsensitiveContains(estado.busca)
            }
            return filtrados.isEmpty ? nil : FilaNaTela(titulo: fila.titulo, cartoes: filtrados)
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
                   reservado: false) {
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

    // MARK: - Grade

    @ViewBuilder
    private var conteudo: some View {
        if let serie = estado.serieAberta {
            episodiosDe(serie)
        } else if estado.secao == .inicio {
            fileiras
        } else if estado.secao == .favoritos {
            grade(itensFavoritos)
        } else if estado.tudo {
            grade(itensDeTudo)
        } else if [.series, .animes, .doramas].contains(estado.secao) {
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
        /// "4K" quando alguma fonte do título anuncia essa resolução.
        var selo: String? = nil
        let abrir: () -> Void
        var nomeCompleto: String { ano.isEmpty ? titulo : "\(titulo) (\(ano))" }
        var id: String { (serie ? "s:" : "f:") + nomeCompleto }
    }

    private func grade(_ todos: [Cartao]) -> some View {
        let itens = porGenero(todos)
        let visiveis = estado.busca.isEmpty ? itens : itens.filter {
            $0.nomeCompleto.localizedCaseInsensitiveContains(estado.busca)
        }
        if !carregando {
            let vazio = visiveis.isEmpty
            Telemetria.shared.buscou(.vod, estado.busca) { !vazio }
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
            .overlay(alignment: .bottomTrailing) { botaoFicha(cartao) }
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
            .contentShape(Rectangle())
            .onTapGesture { cartao.abrir() }

            Text(cartao.nomeCompleto)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(2, reservesSpace: true)
                .foregroundStyle(.white)
            Text(detalheComAno(cartao))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
        }
        .help(cartao.nomeCompleto)
    }

    /// O detalhe do cartão, com o ano na frente quando o nome não traz nenhum.
    ///
    /// Mais da metade do acervo chega sem ano no título, e sem ele não dá para
    /// saber se o cartão é o filme de 1987 ou a refilmagem. O ano vem do mesmo
    /// TMDB que já é consultado para a capa, então não custa pedido nenhum a
    /// mais — só aparece quando a resposta chega.
    private func detalheComAno(_ cartao: Cartao) -> String {
        guard cartao.ano.isEmpty,
              cartao.titulo.range(of: #"\((19|20)\d{2}\)\s*$"#,
                                  options: .regularExpression) == nil,
              let ano = capas.ano(para: cartao.nomeCompleto, serie: cartao.serie)
        else { return cartao.detalhe }
        return "\(ano) · \(cartao.detalhe)"
    }

    /// Abre a ficha sem abrir o filme: sinopse, duração, gêneros e elenco.
    private func botaoFicha(_ cartao: Cartao) -> some View {
        Button {
            fichaAberta = cartao
        } label: {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .padding(5)
                .background(.black.opacity(0.45), in: Circle())
                .foregroundStyle(.white.opacity(0.85))
        }
        .buttonStyle(.plain)
        .padding(6)
        .help("Ver a ficha de \(cartao.nomeCompleto)")
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
        await Generos.carregar()
        if estado.gavetas.isEmpty { estado.gavetas = await Vod.indice() }
        estado.filmes = secao.pedeFilmes
        estado.reservado = secao == .extras
        if secao == .inicio {
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
        guard secao != .favoritos else { return }
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
        let pares = ordenadas.flatMap { versao -> [(String, String)] in
            // Dentro de um idioma, a de maior resolução primeiro: é ela que
            // toca quando ninguém escolhe nada.
            let lista = (fontes[versao] ?? []).sorted {
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
