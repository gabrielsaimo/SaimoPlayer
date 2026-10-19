import SwiftUI

/// A busca, como na TV Box: filmes, séries e canais de uma vez, com os
/// resultados aparecendo enquanto se digita. Erro de acento e de maiúscula não
/// atrapalha. No Mac o teclado é de verdade, então o campo fica no alto, de
/// vidro, e as fileiras de resultado embaixo.
struct TelaBusca: View {
    @ObservedObject var model: PlayerModel
    let acoes: AcoesDoAcervo

    @State private var destaque = DestaqueEstado()
    @State private var texto = ""
    @State private var acervo: [Vod.Achado] = []
    @State private var colecoes: [(Serie, [Episodio])] = []
    @State private var filas: [Fila] = []
    @State private var recentes: [String] = UserDefaults.standard.stringArray(forKey: "busca.recentes") ?? []
    @FocusState private var focado: Bool
    @ObservedObject private var listas = ListasEstado.shared

    var body: some View {
        TelaEmFileiras(destaque: destaque, filas: filas, vazio: vazio) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                    TextField("Buscar filmes, séries, canais…", text: $texto)
                        .textFieldStyle(.plain)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.white)
                        .focused($focado)
                        .onSubmit { guardarRecente() }
                    if !texto.isEmpty {
                        Button { texto = "" } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 18))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white.opacity(0.6))
                        .help("Limpar")
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
                .frame(maxWidth: 760)
                .vidroCapsula()

                if texto.isEmpty, !recentes.isEmpty {
                    HStack(spacing: 8) {
                        Text("Buscas recentes").font(.system(size: 13)).foregroundStyle(Tema.textoSecundario)
                        ForEach(recentes.prefix(6), id: \.self) { termo in
                            Button(termo) { texto = termo }
                                .buttonStyle(.plain)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12).padding(.vertical, 5)
                                .vidroCapsula(interativo: true)
                        }
                    }
                } else {
                    Text("Erros de digitação e falta de acento não atrapalham. Enter guarda a busca nas recentes.")
                        .font(.system(size: 13))
                        .foregroundStyle(Tema.textoSecundario)
                }
            }
        }
        .task {
            focado = true
            // Para conferir a tela sem digitar: `--args -buscaInicial nome`.
            if texto.isEmpty, let inicial = UserDefaults.standard.string(forKey: "buscaInicial") { texto = inicial }
            await Generos.carregar()
            acervo = await Vod.todos()
            colecoes = await Vod.colecao("animes") + Vod.colecao("doramas")
            buscar()
        }
        .task(id: texto) {
            // Um instante de folga entre as teclas: buscar a cada letra no
            // acervo inteiro travaria a digitação.
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            buscar()
        }
    }

    private var vazio: String {
        if listas.canais == nil && listas.filmes == nil {
            return "Nada para buscar. Ative as listas em Ajustes > Listas."
        }
        return texto.trimmingCharacters(in: .whitespaces).isEmpty
            ? "Digite o nome — os resultados aparecem enquanto você digita."
            : "Nada encontrado para \"\(texto)\". Tente outro nome ou menos letras."
    }

    private static func chave(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
            .lowercased()
    }

    private func buscar() {
        let termo = Self.chave(texto.trimmingCharacters(in: .whitespaces))
        guard termo.count >= 2 else {
            filas = []
            destaque.padrao("Buscar", "Filmes, séries, animes, doramas e canais")
            return
        }
        // Começar pelo termo vale mais que conter o termo no meio.
        func ordem(_ nome: String) -> Int { Self.chave(nome).hasPrefix(termo) ? 0 : 1 }
        let achados = acervo.filter { Self.chave($0.titulo).contains(termo) }
            .sorted { (ordem($0.titulo), $0.titulo) < (ordem($1.titulo), $1.titulo) }
        let filmes = achados.filter { !$0.serie }.prefix(40)
        let series = achados.filter(\.serie).prefix(40)
        let canais = model.channels
            .filter { Categoria.de($0) != .adulto && Self.chave($0.name).contains(termo) }
            .prefix(30)
        let daColecao = colecoes.filter { Self.chave($0.0.titulo).contains(termo) }.prefix(30)

        var out: [Fila] = []
        if !canais.isEmpty {
            out.append(Fila(titulo: "Canais", tipo: .largo,
                            cartoes: canais.map { CartoesDoAcervo.canal($0, model: model) }))
        }
        if !filmes.isEmpty {
            out.append(Fila(titulo: "Filmes", cartoes: filmes.map { CartoesDoAcervo.achado($0, acoes: acoes) }))
        }
        if !series.isEmpty {
            out.append(Fila(titulo: "Séries", cartoes: series.map { CartoesDoAcervo.achado($0, acoes: acoes) }))
        }
        if !daColecao.isEmpty {
            out.append(Fila(titulo: "Animes e doramas",
                            cartoes: daColecao.map { CartoesDoAcervo.colecao($0.0, $0.1, acoes: acoes) }))
        }
        filas = out
        let total = canais.count + filmes.count + series.count + daColecao.count
        destaque.padrao("Buscar", total == 0 ? "" : "\(total) resultados para \"\(texto)\"")
        let achou = total > 0
        Telemetria.shared.buscou(.vod, texto) { achou }
    }

    private func guardarRecente() {
        let termo = texto.trimmingCharacters(in: .whitespaces)
        guard termo.count >= 2 else { return }
        recentes = Array(([termo] + recentes.filter { $0.caseInsensitiveCompare(termo) != .orderedSame }).prefix(8))
        UserDefaults.standard.set(recentes, forKey: "busca.recentes")
    }
}
