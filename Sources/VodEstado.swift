import Foundation
import Combine

/// Onde a navegação de filmes e séries parou.
///
/// A janela é uma folha: escolher um filme fecha ela, e o que estava na tela
/// morria junto. Voltar caía sempre na primeira coluna, sem letra, sem rolagem
/// e sem busca — quem estava percorrendo a letra M perdia o lugar a cada filme.
/// Guardando aqui fora, reabrir cai exatamente onde parou.
/// Qual parte do acervo está aberta no lugar do vídeo.
enum VodSecao: String, Identifiable, CaseIterable {
    case filmes, series, extras, favoritos
    var id: String { rawValue }
    var titulo: String {
        switch self {
        case .filmes: return "Filmes"
        case .series: return "Séries"
        case .extras: return "Extras"
        case .favoritos: return "Favoritos"
        }
    }
    var icone: String {
        switch self {
        case .filmes: return "film"
        case .series: return "tv"
        case .extras: return "plus.rectangle.on.rectangle"
        case .favoritos: return "star.fill"
        }
    }
    /// Extras são filmes noutro arquivo do catálogo, não outra natureza.
    var pedeFilmes: Bool { self != .series }
}

@MainActor
final class VodEstado: ObservableObject {
    static let shared = VodEstado()

    @Published var gavetas: [Vod.Gaveta] = []
    @Published var filmes = true
    @Published var reservado = false
    @Published var mostrandoFavoritos = false
    /// Nula quando o vídeo está no lugar dele.
    @Published var secao: VodSecao?
    @Published var letra = ""
    @Published var busca = ""
    @Published var titulosFilme: [Filme] = []
    @Published var titulosSerie: [Serie] = []
    @Published var serieAberta: Serie?
    @Published var episodios: [Episodio] = []
    /// Último título aberto: é para ele que a lista rola ao reabrir, senão a
    /// rolagem voltaria ao topo mesmo com a letra certa escolhida.
    @Published var ancora: String?

    private init() {}

    /// Os títulos já carregados servem para a letra e a seção em que foram
    /// carregados; trocar qualquer uma delas obriga a buscar de novo.
    var precisaCarregar: Bool {
        !letra.isEmpty && (filmes ? titulosFilme.isEmpty : titulosSerie.isEmpty)
    }
}
