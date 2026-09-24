import SwiftUI

/// A ficha de um título, como uma folha sobre a grade.
///
/// Antes um cartaz na grade era só isso: um cartaz. Para saber do que o filme
/// tratava, quanto durava, ou quem estava nele, só abrindo — dois minutos de
/// fonte, player e espera para descobrir que não era aquilo.
///
/// Aqui estão os mesmos campos que o celular mostra, com os mesmos nomes, e o
/// elenco leva a sério o clique: tocar num ator abre o que ele fez **e que
/// existe neste acervo**, que é a única lista que vale de dentro do aplicativo.
struct FichaView: View {
    let titulo: String
    let serie: Bool
    let ano: String
    /// Abre um título do acervo — usado pela filmografia do ator.
    let abrir: (Vod.Achado) -> Void

    @State private var ficha: Ficha?
    @State private var carregando = true
    @State private var ator: Ficha.Pessoa?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            cabecalho
            Divider().opacity(0.2)
            if let ator {
                FilmografiaView(ator: ator, abrir: { achado in
                    dismiss()
                    abrir(achado)
                }, voltar: { self.ator = nil })
            } else {
                conteudo
            }
        }
        .frame(width: 720, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .task { await carregar() }
    }

    private var cabecalho: some View {
        HStack(spacing: 10) {
            if ator != nil {
                Button { ator = nil } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain)
            }
            Text(ator?.nome ?? nomeCompleto)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
            Spacer()
            Button { dismiss() } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain)
        }
        .padding(14)
    }

    private var nomeCompleto: String {
        ano.isEmpty ? titulo : "\(titulo) (\(ano))"
    }

    @ViewBuilder
    private var conteudo: some View {
        if carregando {
            Spacer()
            ProgressView().controlSize(.small)
            Spacer()
        } else if let ficha, !ficha.vazia {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    topo(ficha)
                    if !ficha.sinopse.isEmpty {
                        secao("Sinopse") {
                            Text(ficha.sinopse)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    creditos(ficha)
                    if !ficha.elenco.isEmpty {
                        secao("Elenco") { elenco(ficha) }
                    }
                }
                .padding(18)
            }
        } else {
            Spacer()
            Text("Sem ficha para este título.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func topo(_ ficha: Ficha) -> some View {
        HStack(alignment: .top, spacing: 14) {
            AsyncImage(url: ficha.capa.flatMap(URL.init(string:))) { imagem in
                imagem.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.07))
            }
            .frame(width: 120, height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                if !ficha.frase.isEmpty {
                    Text(ficha.frase)
                        .font(.system(size: 12, weight: .medium))
                        .italic()
                        .foregroundStyle(.secondary)
                }
                selos(ficha)
                if !ficha.generos.isEmpty {
                    Text(ficha.generos.joined(separator: " · "))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func selos(_ ficha: Ficha) -> some View {
        HStack(spacing: 6) {
            if !ficha.ano.isEmpty { selo(ficha.ano) }
            if let minutos = ficha.duracao, minutos > 0 {
                selo(serie ? "\(minutos) min/ep" : "\(minutos) min")
            }
            if let classificacao = ficha.classificacao, !classificacao.isEmpty {
                selo(classificacao)
            }
            if ficha.nota > 0 {
                selo(String(format: "★ %.1f", ficha.nota))
            }
        }
    }

    private func selo(_ texto: String) -> some View {
        Text(texto)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .overlay(Capsule().stroke(.secondary.opacity(0.4)))
    }

    @ViewBuilder
    private func creditos(_ ficha: Ficha) -> some View {
        let linhas: [(String, String)] = [
            (serie ? "Criação" : "Direção", ficha.assinatura),
            ("Roteiro", ficha.roteiro),
            ("Produção", ficha.produtora),
        ].filter { !$0.1.isEmpty }
        if !linhas.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(linhas, id: \.0) { rotulo, valor in
                    Text("\(rotulo): ").font(.system(size: 11, weight: .semibold))
                        + Text(valor).font(.system(size: 11)).foregroundColor(.secondary)
                }
            }
        }
    }

    private func elenco(_ ficha: Ficha) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(ficha.elenco) { pessoa in
                    Button { ator = pessoa } label: {
                        VStack(spacing: 5) {
                            AsyncImage(url: pessoa.foto.flatMap(URL.init(string:))) { imagem in
                                imagem.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                ZStack {
                                    Circle().fill(Color.white.opacity(0.07))
                                    Image(systemName: "person.fill")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 64, height: 64)
                            .clipShape(Circle())
                            Text(pessoa.nome)
                                .font(.system(size: 10, weight: .medium))
                                .lineLimit(1)
                            Text(pessoa.papel)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(width: 84)
                    }
                    .buttonStyle(.plain)
                    .help("Ver o que \(pessoa.nome) tem no acervo")
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func secao<Conteudo: View>(
        _ titulo: String, @ViewBuilder _ corpo: () -> Conteudo
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(titulo).font(.system(size: 12, weight: .semibold))
            corpo()
        }
    }

    private func carregar() async {
        ficha = await Fichas.de(titulo, serie: serie)
        carregando = false
    }
}

/// O que um ator fez **e que existe neste acervo**.
///
/// A filmografia inteira do TMDB não serve de dentro do aplicativo: listar
/// oitenta títulos dos quais setenta não dá para abrir é uma lista que
/// frustra. O cruzamento é pelo id do TMDB, que o arquivo de fichas já traz
/// para cada título do acervo — nome igual não engana, e refilmagem não vira
/// o original.
struct FilmografiaView: View {
    let ator: Ficha.Pessoa
    let abrir: (Vod.Achado) -> Void
    let voltar: () -> Void

    @State private var titulos: [Vod.Achado] = []
    @State private var carregando = true

    var body: some View {
        Group {
            if carregando {
                VStack { Spacer(); ProgressView().controlSize(.small); Spacer() }
            } else if titulos.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    Text("Nada de \(ator.nome) no acervo.")
                        .font(.system(size: 12))
                    Text("A filmografia mostra só o que dá para abrir daqui.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)],
                              spacing: 14) {
                        ForEach(titulos) { achado in
                            Button { abrir(achado) } label: { cartao(achado) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(18)
                }
            }
        }
        .task { await carregar() }
    }

    private func cartao(_ achado: Vod.Achado) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: Generos.capa(achado.nomeCompleto, serie: achado.serie)
                .flatMap(URL.init(string:))) { imagem in
                imagem.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.07))
                    Image(systemName: achado.serie ? "tv" : "film")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 210)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(achado.nomeCompleto)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(2, reservesSpace: true)
            Text(achado.serie ? "Série" : "Filme")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private func carregar() async {
        titulos = await Fichas.acervoDe(ator: ator.id)
        carregando = false
    }
}
