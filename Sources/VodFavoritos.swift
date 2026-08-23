import Foundation
import Combine

/// Filmes e séries marcados como favoritos.
///
/// Guarda o tipo e a letra junto com o nome porque é assim que o acervo é
/// fatiado: com a letra na mão, abrir um favorito custa o mesmo pedaço de
/// catálogo que abrir o título pela navegação normal, sem varrer o acervo
/// inteiro atrás dele.
///
/// A ordem importa — o que foi marcado por último aparece em cima —, então isto
/// é uma lista gravada como texto, e não um conjunto.
final class VodFavoritos: ObservableObject {

    struct Item: Identifiable, Hashable {
        let titulo: String
        let serie: Bool
        let letra: String
        /// Um extra vive na mesma letra, mas noutro arquivo.
        let reservado: Bool
        var id: String { "\(serie ? "s" : "f")|\(reservado ? "r" : "n")|\(titulo)" }
    }

    static let shared = VodFavoritos()

    @Published private(set) var itens: [Item] = []

    private let chave = "vodFavoritos"

    private init() {
        itens = (UserDefaults.standard.stringArray(forKey: chave) ?? []).compactMap { linha in
            let campos = linha.components(separatedBy: "\t")
            guard campos.count >= 3, !campos[2].isEmpty else { return nil }
            return Item(titulo: campos[2], serie: campos[0] == "s", letra: campos[1],
                        reservado: campos.count > 3 && campos[3] == "r")
        }
    }

    func contem(_ titulo: String, serie: Bool) -> Bool {
        itens.contains { $0.titulo == titulo && $0.serie == serie }
    }

    /// Marca ou desmarca. O que entra fica em primeiro.
    func alternar(_ item: Item) {
        if contem(item.titulo, serie: item.serie) {
            itens.removeAll { $0.titulo == item.titulo && $0.serie == item.serie }
        } else {
            itens.insert(item, at: 0)
        }
        gravar()
    }

    private func gravar() {
        let linhas = itens.map {
            [$0.serie ? "s" : "f", $0.letra, $0.titulo, $0.reservado ? "r" : "n"]
                .joined(separator: "\t")
        }
        UserDefaults.standard.set(linhas, forKey: chave)
        UserDefaults.standard.synchronize()
    }
}
