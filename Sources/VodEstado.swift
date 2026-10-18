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
    case inicio, filmes, series, animes, doramas, extras, favoritos, eventos
    /// As telas da barra do topo que não são uma parte do acervo, mas moram
    /// no mesmo lugar dele: com uma delas aberta o ao vivo para, como em
    /// qualquer outra seção.
    case ondemand, radios, buscar, ajustes
    var id: String { rawValue }
    var titulo: String {
        switch self {
        case .inicio: return "Início"
        case .ondemand: return "On Demand"
        case .radios: return "Rádios"
        case .buscar: return "Buscar"
        case .ajustes: return "Ajustes"
        case .filmes: return "Filmes"
        case .series: return "Séries"
        case .animes: return "Animes"
        case .doramas: return "Doramas"
        case .extras: return "Extras"
        case .favoritos: return "Favoritos"
        case .eventos: return "Eventos"
        }
    }
    var icone: String {
        switch self {
        case .inicio: return "house"
        case .filmes: return "film"
        case .series: return "tv"
        case .animes: return "sparkles.tv"
        case .doramas: return "heart.rectangle"
        case .extras: return "plus.rectangle.on.rectangle"
        case .favoritos: return "star.fill"
        case .eventos: return "sportscourt"
        case .ondemand: return "film.stack"
        case .radios: return "radio"
        case .buscar: return "magnifyingglass"
        case .ajustes: return "gearshape"
        }
    }
    /// Extras são filmes noutro arquivo do catálogo, não outra natureza.
    var pedeFilmes: Bool {
        ![.series, .animes, .doramas, .inicio, .eventos, .ondemand, .radios, .buscar, .ajustes].contains(self)
    }
    /// As quatro categorias do On Demand: cada uma tem a página dela, em
    /// fileiras, e o acervo inteiro de A a Z por trás.
    var ehCategoria: Bool { [.filmes, .series, .animes, .doramas].contains(self) }
}

@MainActor
final class VodEstado: ObservableObject {
    static let shared = VodEstado()

    @Published var gavetas: [Vod.Gaveta] = []
    @Published var filmes = true
    @Published var reservado = false
    @Published var mostrandoFavoritos = false
    /// Nula quando o vídeo está no lugar dele.
    ///
    /// Abrir o acervo para o ao vivo de vez — player e fluxo, nas duas telas
    /// da multi tela —, e fechá-lo volta ao último canal. Ao vivo tocando
    /// escondido atrás da grade era som e rede gastos com nada à vista.
    @Published var secao: VodSecao? {
        didSet {
            guard (oldValue == nil) != (secao == nil) else { return }
            // O ao vivo vai voltar: a rádio não toca junto com ele.
            if secao == nil { Radios.shared.parar() }
            if secao == nil { PlayerModel.shared.retomarAoVivo() } else { PlayerModel.shared.suspenderAoVivo() }
        }
    }
    @Published var letra = ""
    /// Acervo inteiro numa lista só, em vez de uma letra por vez.
    @Published var tudo = true
    @Published var achados: [Vod.Achado] = []
    /// De que seção veio a lista acima: trocar de seção obriga a refazê-la.
    @Published var achadosDe: VodSecao?
    @Published var busca = ""
    @Published var titulosFilme: [Filme] = []
    @Published var titulosSerie: [Serie] = []
    @Published var serieAberta: Serie?
    /// A letra de onde a série aberta veio: é o que o favorito dela guarda
    /// para achá-la de novo.
    var letraDaSerie = ""
    @Published var episodios: [Episodio] = []
    /// Episódios das coleções compactas, já publicados no mesmo arquivo.
    @Published var episodiosColecao: [String: [Episodio]] = [:]
    /// Numa categoria do On Demand: a grade de A a Z no lugar da página em
    /// fileiras. Trocar de seção volta à página.
    @Published var explorando = false
    /// O gênero escolhido na grade, ou vazio para todos. Fica aqui fora para
    /// o "Ver mais" de uma fileira de gênero abrir a grade já filtrada.
    @Published var genero = ""
    /// Ordem da grade: os mais novos primeiro (como na TV) ou de A a Z.
    @Published var novosPrimeiro = false
    /// Último título aberto: é para ele que a lista rola ao reabrir, senão a
    /// rolagem voltaria ao topo mesmo com a letra certa escolhida.
    @Published var ancora: String?

    private init() {}

    /// O endereço dos filmes mudou ou foi apagado: nada do que estava carregado vale mais.
    func reiniciarAcervo() {
        gavetas = []
        achados = []
        achadosDe = nil
        titulosFilme = []
        titulosSerie = []
        serieAberta = nil
        episodios = []
        episodiosColecao = [:]
        letra = ""
        genero = ""
        busca = ""
    }

    /// Os títulos já carregados servem para a letra e a seção em que foram
    /// carregados; trocar qualquer uma delas obriga a buscar de novo.
    var precisaCarregar: Bool {
        !letra.isEmpty && (filmes ? titulosFilme.isEmpty : titulosSerie.isEmpty)
    }
}
