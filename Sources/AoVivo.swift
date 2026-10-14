import SwiftUI
import AppKit

/// O que a tela do vídeo mostra além dele, como na TV Box.
@MainActor
final class Interface: ObservableObject {
    static let shared = Interface()
    /// A lista de canais de vidro, à esquerda do vídeo.
    @Published var painelCanais = false
    private init() {}
}

/// A lista de canais por cima do vídeo, à esquerda, como na TV Box: o título
/// "Canais" com quantos são, as categorias em pílulas (clicar leva à seção),
/// e cada canal com o número, o logo, o nome, o programa no ar e o quanto
/// dele já passou. O canal no ar fica marcado.
///
/// Na multi tela mostra e troca o canal da tela ativa, como a lista antiga.
struct PainelDeCanais: View {
    @ObservedObject var model: PlayerModel
    @ObservedObject private var epg = EPGService.shared
    @ObservedObject private var interface = Interface.shared
    @State private var categoria: Categoria?
    @FocusState private var buscando: Bool

    var body: some View {
        let grupos = model.gruposDeCanais
        let numeros = Dictionary(uniqueKeysWithValues:
            grupos.flatMap(\.canais).enumerated().map { ($0.element.id, $0.offset + 1) })
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Canais")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                if let atual = model.selecaoDaLista, let n = numeros[atual] {
                    Text("\(n)").font(.system(size: 17, weight: .semibold)).foregroundStyle(Tema.acento)
                }
                Text("\(numeros.count)")
                    .font(.system(size: 17))
                    .foregroundStyle(Tema.textoSecundario)
                Button { interface.painelCanais = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 26, height: 26)
                        .vidro(Circle(), interativo: true)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .help("Fechar a lista (Esc)")
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.6))
                TextField("Buscar canal", text: $model.search)
                    .textFieldStyle(.plain)
                    .foregroundStyle(.white)
                    .focused($buscando)
                if !model.search.isEmpty {
                    Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.white.opacity(0.08), in: Capsule())

            ScrollViewReader { rolagem in
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(grupos, id: \.categoria) { grupo in
                            let ativa = categoria == grupo.categoria
                            Button {
                                categoria = grupo.categoria
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    rolagemDaLista?.scrollTo("cat:" + grupo.categoria.rawValue, anchor: .top)
                                }
                            } label: {
                                Text(grupo.categoria.rawValue)
                                    .font(.system(size: 13, weight: .medium))
                                    .lineLimit(1)
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .foregroundStyle(ativa ? Color.black : Color.white)
                                    .background(Capsule().fill(ativa ? Color.white : Color.white.opacity(0.1)))
                                    .overlay(Capsule().strokeBorder(ativa ? Tema.acento : .clear, lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                            .id(grupo.categoria.rawValue)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .onChange(of: categoria) { _, nova in
                    if let nova { withAnimation { rolagem.scrollTo(nova.rawValue, anchor: .center) } }
                }
            }

            ScrollViewReader { rolagem in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4, pinnedViews: []) {
                        ForEach(grupos, id: \.categoria) { grupo in
                            Text(grupo.categoria.rawValue.uppercased())
                                .font(.system(size: 11, weight: .bold))
                                .tracking(1.2)
                                .foregroundStyle(Tema.textoApagado)
                                .padding(.top, 10)
                                .padding(.leading, 6)
                                .id("cat:" + grupo.categoria.rawValue)
                                .onAppear { if categoria == nil { categoria = grupo.categoria } }
                            ForEach(grupo.canais) { canal in
                                LinhaDeCanal(model: model, canal: canal, numero: numeros[canal.id] ?? 0,
                                             noAr: canal.id == model.selecaoDaLista)
                                    .id(canal.id)
                            }
                        }
                    }
                    .padding(.bottom, 10)
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    rolagemDaLista = rolagem
                    if let atual = model.selecaoDaLista {
                        DispatchQueue.main.async { rolagem.scrollTo(atual, anchor: .center) }
                    }
                }
            }

            Text("Clique assiste · botão direito: fontes e favoritos · ⌘↑ ⌘↓ trocam de canal")
                .font(.system(size: 11))
                .foregroundStyle(Tema.textoApagado)
        }
        .padding(18)
        .frame(width: 400)
        .frame(maxHeight: .infinity)
        .vidroPainel(raio: 26)
        .environment(\.colorScheme, .dark)
        .onExitCommand { interface.painelCanais = false }
    }

    /// O leitor da rolagem da lista, guardado para as pílulas usarem.
    @State private var rolagemDaLista: ScrollViewProxy?
}

private struct LinhaDeCanal: View {
    @ObservedObject var model: PlayerModel
    let canal: Channel
    let numero: Int
    let noAr: Bool
    @ObservedObject private var epg = EPGService.shared
    @State private var sobre = false

    var body: some View {
        let programa = epg.nowNext(for: canal, at: epg.clock)
        Button { model.escolherNaLista(canal.id) } label: {
            HStack(spacing: 12) {
                Text("\(numero)")
                    .font(.system(size: 14, weight: .medium).monospacedDigit())
                    .foregroundStyle(noAr ? Tema.acento : Tema.textoApagado)
                    .frame(width: 30, alignment: .trailing)
                ChannelIcon(channel: canal, size: 46)
                    .environment(\.colorScheme, .dark)
                VStack(alignment: .leading, spacing: 3) {
                    Text(canal.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let programa {
                        Text(programa.current.title)
                            .font(.system(size: 12))
                            .foregroundStyle(Tema.textoSecundario)
                            .lineLimit(1)
                        BarraDeProgresso(fracao: programa.progress, altura: 3)
                            .frame(maxWidth: 200)
                    }
                }
                Spacer(minLength: 4)
                if model.isFavorite(canal) || sobre {
                    Button { model.toggleFavorite(canal) } label: {
                        Image(systemName: model.isFavorite(canal) ? "star.fill" : "star")
                            .foregroundStyle(model.isFavorite(canal) ? .yellow : .white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .help(model.isFavorite(canal) ? "Remover dos favoritos" : "Favoritar")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(noAr ? 0.12 : sobre ? 0.07 : 0))
            }
            .overlay {
                if noAr {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Tema.acento, lineWidth: 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { sobre = $0 }
        .contextMenu {
            if canal.variants.count > 1 {
                Menu("Escolher Fonte") {
                    ForEach(Array(canal.variants.enumerated()), id: \.offset) { index, variant in
                        // Como no TV Box: o nome da fonte (a temporada, nos
                        // canais 24h) ou o número, a qualidade e o servidor.
                        let qualidade = variant.label == "Qualidade não informada" ? nil : variant.label
                        Button(([variant.nome ?? "Fonte \(index + 1)"]
                                + [qualidade, variant.url.host?.replacingOccurrences(of: "www.", with: "")].compactMap { $0 })
                            .joined(separator: " · ")) {
                            model.playVariant(canal, index: index)
                        }
                    }
                }
                Divider()
            }
            Button(model.isFavorite(canal) ? "Remover dos favoritos" : "Favoritar") {
                model.toggleFavorite(canal)
            }
            if model.multiTela {
                Button("Abrir na outra tela") {
                    model.ativarTela(model.segundaAtiva ? .principal : .segunda)
                    model.escolherNaLista(canal.id)
                }
            }
            Divider()
            Button("Remover canal", role: .destructive) { model.removeChannel(canal) }
        }
    }
}

/// O cartão do programa no ar, no canto de baixo à direita, como na TV:
/// número e nome do canal em ciano, o programa, o horário com quanto falta e
/// o que vem a seguir. Um filme ou episódio mostra o que se sabe dele.
struct CartaoNoAr: View {
    @ObservedObject var model: PlayerModel
    @ObservedObject private var epg = EPGService.shared
    @ObservedObject private var capas = Capas.shared

    var body: some View {
        if model.playingFile != nil {
            arquivo
        } else if let canal = model.canalAtivo {
            canalNoAr(canal)
        }
    }

    private func canalNoAr(_ canal: Channel) -> some View {
        let numero = (model.visibleChannels.firstIndex { $0.id == canal.id }).map { $0 + 1 }
        let programa = epg.nowNext(for: canal, at: epg.clock)
        return HStack(alignment: .top, spacing: 14) {
            ChannelIcon(channel: canal, size: 54)
                .environment(\.colorScheme, .dark)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if let numero { Text("\(numero)").foregroundStyle(Tema.acento) }
                    Text(canal.name).foregroundStyle(Tema.acento)
                }
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                if let programa {
                    Text(programa.current.title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("\(hora(programa.current.start)) – \(hora(programa.current.stop)) · faltam \(programa.remainingMinutes) min")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.85))
                    if let seguinte = programa.next {
                        Text("A seguir: \(seguinte.title)")
                            .font(.system(size: 13))
                            .foregroundStyle(Tema.textoSecundario)
                            .lineLimit(1)
                    }
                    BarraDeProgresso(fracao: programa.progress, altura: 3)
                        .padding(.top, 4)
                } else {
                    Text("Sem programação para este canal")
                        .font(.system(size: 13))
                        .foregroundStyle(Tema.textoSecundario)
                }
            }
            .frame(maxWidth: 380, alignment: .leading)
        }
        .padding(16)
        .vidroPainel(raio: 22)
    }

    private var arquivo: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.1))
                if let capa = capas.imagem(para: model.playingFileName,
                                           serie: model.playingFileDetail.hasPrefix("Temporada")) {
                    Image(nsImage: capa).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "film").font(.system(size: 20)).foregroundStyle(.white.opacity(0.8))
                }
            }
            .frame(width: 52, height: 76)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(model.playingFileName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if !model.playingFileDetail.isEmpty {
                    Text(model.playingFileDetail)
                        .font(.system(size: 12))
                        .foregroundStyle(Tema.acento)
                        .lineLimit(1)
                }
                if model.duration > 0 {
                    let falta = Int(max(0, model.duration - model.position) / 60)
                    Text(falta > 0 ? "faltam \(falta) min de \(Int(model.duration / 60))" : "terminando")
                        .font(.system(size: 12))
                        .foregroundStyle(Tema.textoSecundario)
                }
            }
            .frame(maxWidth: 380, alignment: .leading)
        }
        .padding(16)
        .vidroPainel(raio: 22)
    }

    private func hora(_ data: Date) -> String {
        data.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }
}
