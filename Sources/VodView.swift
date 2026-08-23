import SwiftUI

/// Filmes e séries em três colunas: seção, letra e títulos.
///
/// Dezenove mil filmes e nove mil séries não cabem numa tela nem na cabeça de
/// ninguém. Três colunas resolvem sem esconder nada: o caminho inteiro fica à
/// vista, e cada clique estreita a busca em vez de trocar de tela.
struct VodView: View {
    @ObservedObject var model: PlayerModel
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
        if letra.isEmpty {
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
                        Text(filme.titulo)
                        Spacer()
                        ForEach(filme.fontes.keys.sorted(), id: \.self) { versao in
                            let urls = filme.fontes[versao] ?? []
                            Button(botao(versao, urls.count)) {
                                tocar(filme.titulo, urls, detalhe: "Filme · \(rotulo(versao))")
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
                    Button {
                        serieAberta = serie
                        Task {
                            carregando = true
                            episodios = await Vod.episodios(letra: letra, serie: serie)
                            carregando = false
                        }
                    } label: {
                        HStack {
                            Text(serie.titulo)
                            if !serie.ano.isEmpty {
                                Text(serie.ano).foregroundStyle(.secondary).font(.caption)
                            }
                            Spacer()
                            Text("\(serie.episodios) episódios")
                                .foregroundStyle(.secondary).font(.caption)
                        }
                    }
                    .buttonStyle(.plain)
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
        return HStack {
            Text("Episódio \(episodio.numero)")
            Text(botao(episodio.versao, episodio.urls.count))
                .foregroundStyle(.secondary)
                .font(.caption)
            Spacer()
            Button("Assistir") {
                tocar(serie.titulo, episodio.urls, detalhe: detalhe)
            }
            .controlSize(.small)
        }
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

    private func tocar(_ nome: String, _ urls: [String], detalhe: String = "") {
        let destinos = urls.compactMap(URL.init(string:))
        guard !destinos.isEmpty else { return }
        model.playFile(destinos, nome: nome, detalhe: detalhe)
        dismiss()
    }
}
