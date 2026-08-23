import SwiftUI

/// Filmes e séries em três colunas: seção, letra e títulos.
///
/// Dezenove mil filmes e nove mil séries não cabem numa tela nem na cabeça de
/// ninguém. Três colunas resolvem sem esconder nada: o caminho inteiro fica à
/// vista, e cada clique estreita a busca em vez de trocar de tela.
struct VodView: View {
    @ObservedObject var model: PlayerModel
    @ObservedObject private var capas = Capas.shared
    @ObservedObject private var favoritos = VodFavoritos.shared
    @Environment(\.dismiss) private var dismiss

    @State private var gavetas: [Vod.Gaveta] = []
    @State private var filmes = true
    @State private var reservado = false
    @State private var letra = ""
    @State private var titulosFilme: [Filme] = []
    @State private var titulosSerie: [Serie] = []
    @State private var serieAberta: Serie?
    @State private var episodios: [Episodio] = []
    @State private var busca = ""
    @State private var carregando = false
    @State private var mostrandoFavoritos = false

    var body: some View {
        VStack(spacing: 0) {
            cabecalho
            Divider()
            HStack(spacing: 0) {
                secoes
                Divider()
                letras
                Divider()
                conteudo
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        .task { if gavetas.isEmpty { gavetas = await Vod.indice() } }
    }

    private var cabecalho: some View {
        HStack {
            Text("Filmes e Séries").font(.system(size: 17, weight: .semibold))
            if carregando { ProgressView().controlSize(.small).padding(.leading, 4) }
            Spacer()
            TextField("Buscar nesta letra", text: $busca)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
            Button("Fechar") { dismiss() }
        }
        .padding(12)
    }

    private var secoes: some View {
        List {
            // Favoritos em primeiro: quem marcou um título marcou para voltar
            // nele. A seção só existe quando há o que abrir.
            if !favoritos.itens.isEmpty {
                Button {
                    mostrandoFavoritos = true
                    serieAberta = nil
                } label: {
                    HStack {
                        Label("Favoritos", systemImage: "star.fill")
                        Spacer()
                        Text("\(favoritos.itens.count)")
                            .foregroundStyle(.secondary).font(.caption)
                    }
                }
                .buttonStyle(.plain)
                .fontWeight(mostrandoFavoritos ? .semibold : .regular)
            }
            botaoSecao(titulo: "Filmes", total: gavetas.reduce(0) { $0 + $1.filmes },
                       filmes: true, extras: false)
            botaoSecao(titulo: "Séries", total: gavetas.reduce(0) { $0 + $1.series },
                       filmes: false, extras: false)
            // Só existe depois do código, e como uma linha igual às outras.
            if model.restrictedUnlocked {
                let total = gavetas.reduce(0) { $0 + $1.reservados }
                if total > 0 {
                    botaoSecao(titulo: "Extras", total: total, filmes: true, extras: true)
                }
            }
        }
        .listStyle(.sidebar)
        .frame(width: 190)
    }

    private func botaoSecao(titulo: String, total: Int,
                            filmes alvo: Bool, extras: Bool) -> some View {
        let ativo = filmes == alvo && reservado == extras
        return Button {
            filmes = alvo
            reservado = extras
            serieAberta = nil
            mostrandoFavoritos = false
            if !letra.isEmpty { Task { await carregar() } }
        } label: {
            HStack {
                Text(titulo)
                Spacer()
                Text("\(total)").foregroundStyle(.secondary).font(.caption)
            }
        }
        .buttonStyle(.plain)
        .fontWeight(ativo ? .semibold : .regular)
    }

    private var letras: some View {
        List(gavetas.filter {
            reservado ? $0.reservados > 0 : (filmes ? $0.filmes > 0 : $0.series > 0)
        }) { gaveta in
            Button {
                letra = gaveta.letra
                serieAberta = nil
                mostrandoFavoritos = false
                busca = ""
                Task { await carregar() }
            } label: {
                HStack {
                    Text(gaveta.letra).fontWeight(letra == gaveta.letra ? .bold : .regular)
                    Spacer()
                    Text("\(reservado ? gaveta.reservados : (filmes ? gaveta.filmes : gaveta.series))")
                        .foregroundStyle(.secondary).font(.caption)
                }
            }
            .buttonStyle(.plain)
        }
        .frame(width: 110)
    }

    @ViewBuilder
    private var conteudo: some View {
        if mostrandoFavoritos, serieAberta == nil {
            listaFavoritos
        } else if letra.isEmpty {
            aviso("Escolha uma letra")
        } else if let serie = serieAberta {
            episodiosDe(serie)
        } else if filmes {
            listaFilmes
        } else {
            listaSeries
        }
    }

    private var listaFilmes: some View {
        let visiveis = titulosFilme.filter {
            busca.isEmpty || $0.titulo.localizedCaseInsensitiveContains(busca)
        }
        return Group {
            if visiveis.isEmpty { aviso("Nada aqui") } else {
                List(visiveis) { filme in
                    HStack {
                        capa(filme.titulo, serie: false)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(filme.titulo)
                            if let visto = Progresso.fracao(Progresso.chaveFilme(filme.titulo)) {
                                ProgressView(value: visto)
                                    .progressViewStyle(.linear)
                                    .frame(width: 160)
                                    .controlSize(.mini)
                            }
                        }
                        Spacer()
                        estrela(VodFavoritos.Item(titulo: filme.titulo, serie: false,
                                                  letra: letra, reservado: reservado))
                        ForEach(filme.fontes.keys.sorted(), id: \.self) { versao in
                            let urls = filme.fontes[versao] ?? []
                            Button(botao(versao, urls.count)) {
                                tocar(filme.titulo, urls, detalhe: "Filme · \(rotulo(versao))",
                                      chave: Progresso.chaveFilme(filme.titulo))
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
    }

    private var listaSeries: some View {
        let visiveis = titulosSerie.filter {
            busca.isEmpty || $0.titulo.localizedCaseInsensitiveContains(busca)
        }
        return Group {
            if visiveis.isEmpty { aviso("Nada aqui") } else {
                List(visiveis) { serie in
                    HStack {
                        Button {
                            serieAberta = serie
                            Task {
                                carregando = true
                                episodios = await Vod.episodios(letra: letra, serie: serie)
                                carregando = false
                            }
                        } label: {
                            HStack {
                                capa(serie.titulo, serie: true)
                                Text(serie.titulo)
                                if !serie.ano.isEmpty {
                                    Text(serie.ano).foregroundStyle(.secondary).font(.caption)
                                }
                                Spacer()
                                Text("\(serie.episodios) episódios")
                                    .foregroundStyle(.secondary).font(.caption)
                            }
                            // Sem isto o clique só pega no texto, e não na linha.
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        estrela(VodFavoritos.Item(titulo: serie.titulo, serie: true,
                                                  letra: letra, reservado: false))
                    }
                }
            }
        }
    }

    private func episodiosDe(_ serie: Serie) -> some View {
        let temporadas = Set(episodios.map(\.temporada)).sorted()
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button {
                    serieAberta = nil
                } label: {
                    Label("Voltar", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                Text(serie.titulo).font(.headline)
                Spacer()
            }
            .padding(10)
            Divider()
            List {
                ForEach(temporadas, id: \.self) { temporada in
                    Section("Temporada \(temporada)") {
                        ForEach(daTemporada(temporada)) { episodio in
                            linhaEpisodio(serie, episodio)
                        }
                    }
                }
            }
        }
    }

    private func daTemporada(_ temporada: Int) -> [Episodio] {
        episodios.filter { $0.temporada == temporada }
            .sorted { ($0.numero, $0.versao) < ($1.numero, $1.versao) }
    }

    private func linhaEpisodio(_ serie: Serie, _ episodio: Episodio) -> some View {
        let detalhe = "Temporada \(episodio.temporada), episódio \(episodio.numero)"
            + " · \(rotulo(episodio.versao))"
        let chave = Progresso.chaveEpisodio(serie.titulo, episodio.temporada, episodio.numero)
        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Episódio \(episodio.numero)")
                    Text(botao(episodio.versao, episodio.urls.count))
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                if let visto = Progresso.fracao(chave) {
                    ProgressView(value: visto)
                        .progressViewStyle(.linear)
                        .frame(width: 170)
                        .controlSize(.mini)
                }
            }
            Spacer()
            Button("Assistir") {
                tocar(serie.titulo, episodio.urls, detalhe: detalhe, chave: chave)
            }
            .controlSize(.small)
        }
    }

    /// A estrela fica na própria linha: marcar é um clique, e o estado se vê
    /// sem abrir nada.
    private func estrela(_ item: VodFavoritos.Item) -> some View {
        let marcado = favoritos.contem(item.titulo, serie: item.serie)
        return Button {
            favoritos.alternar(item)
        } label: {
            Image(systemName: marcado ? "star.fill" : "star")
                .foregroundStyle(marcado ? .yellow : .secondary)
        }
        .buttonStyle(.plain)
        .help(marcado ? "Remover dos favoritos" : "Favoritar")
    }

    private var listaFavoritos: some View {
        let visiveis = favoritos.itens.filter {
            busca.isEmpty || $0.titulo.localizedCaseInsensitiveContains(busca)
        }
        return Group {
            if visiveis.isEmpty { aviso("Nada aqui") } else {
                List(visiveis) { item in
                    HStack {
                        capa(item.titulo, serie: item.serie)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.titulo)
                            Text(item.serie ? "Série" : "Filme")
                                .foregroundStyle(.secondary).font(.caption)
                            if !item.serie,
                               let visto = Progresso.fracao(Progresso.chaveFilme(item.titulo)) {
                                ProgressView(value: visto)
                                    .progressViewStyle(.linear)
                                    .frame(width: 160)
                                    .controlSize(.mini)
                            }
                        }
                        Spacer()
                        estrela(item)
                        Button(item.serie ? "Abrir" : "Assistir") {
                            Task { await abrirFavorito(item) }
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    /// O favorito guarda nome e letra; as fontes moram no pedaço do catálogo
    /// daquela letra, que é baixado só agora.
    private func abrirFavorito(_ item: VodFavoritos.Item) async {
        carregando = true
        defer { carregando = false }
        letra = item.letra
        reservado = item.reservado
        filmes = !item.serie
        if item.serie {
            let achada = await Vod.series(letra: item.letra)
                .first { $0.titulo == item.titulo }
            guard let achada else { return }
            titulosSerie = [achada]
            episodios = await Vod.episodios(letra: item.letra, serie: achada)
            serieAberta = achada
        } else {
            let achado = await Vod.filmes(letra: item.letra, reservados: item.reservado)
                .first { $0.titulo == item.titulo }
            guard let achado, let versao = achado.fontes.keys.sorted().first,
                  let urls = achado.fontes[versao] else { return }
            tocar(achado.titulo, urls, detalhe: "Filme · \(rotulo(versao))",
                  chave: Progresso.chaveFilme(achado.titulo))
        }
    }

    /// A capa chega da rede quando a linha aparece; até lá, a moldura vazia
    /// segura o lugar para a lista não pular de altura.
    @ViewBuilder
    private func capa(_ titulo: String, serie: Bool) -> some View {
        let imagem = capas.imagem(para: titulo, serie: serie)
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.primary.opacity(0.08))
            if let imagem {
                Image(nsImage: imagem)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
        }
        .frame(width: 54, height: 80)
    }

    private func aviso(_ texto: String) -> some View {
        VStack {
            Spacer()
            Text(texto).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func carregar() async {
        carregando = true
        if filmes {
            titulosFilme = await Vod.filmes(letra: letra, reservados: reservado)
            titulosSerie = []
        } else {
            titulosSerie = await Vod.series(letra: letra)
            titulosFilme = []
        }
        carregando = false
    }

    private func rotulo(_ versao: String) -> String {
        versao == "leg" ? "Legendado" : "Dublado"
    }

    /// Duas fontes não viram dois botões: viram um botão e uma reserva.
    private func botao(_ versao: String, _ fontes: Int) -> String {
        fontes > 1 ? "\(rotulo(versao)) (\(fontes))" : rotulo(versao)
    }

    private func tocar(_ nome: String, _ urls: [String], detalhe: String = "",
                       chave: String = "") {
        let destinos = urls.compactMap(URL.init(string:))
        guard !destinos.isEmpty else { return }
        model.playFile(destinos, nome: nome, detalhe: detalhe, chave: chave)
        dismiss()
    }
}
