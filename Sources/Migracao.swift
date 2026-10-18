import Foundation

/// Limpeza dos dados de lista guardados em disco.
///
/// - Na primeira execução da versão "sem listas", apaga tudo o que as versões
///   anteriores baixaram (canais, rádios, guia, filmes, fichas, destaques): o
///   app começa vazio. Favoritos, progresso, ajustes e histórico ficam.
/// - Ao apagar ou trocar um endereço, apaga os dados daquela lista.
enum Migracao {
    private static let marca = "migracao.semListas.v1"

    enum Lista { case canais, filmes }

    /// Roda uma vez, antes de qualquer outra coisa ler esses arquivos.
    static func executarSeNecessario() {
        let padrao = UserDefaults.standard
        guard !padrao.bool(forKey: marca) else { return }
        apagarDados(.canais)
        apagarDados(.filmes)
        padrao.set(true, forKey: marca)
    }

    private static var caches: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    static func apagarDados(_ lista: Lista) {
        let gerente = FileManager.default
        let saimo = caches.appendingPathComponent("SaimoTV", isDirectory: true)
        let alvos: [URL]
        switch lista {
        case .canais:
            alvos = ["catalogo.txt", "canais.txt", "restritos.txt", "guia.txt"]
                .map { saimo.appendingPathComponent($0) }
                + [caches.appendingPathComponent("vod/radios.txt"),
                   caches.appendingPathComponent("dev.saimo.player/epg.json.z")]
        case .filmes:
            alvos = [saimo.appendingPathComponent("vod", isDirectory: true),
                     saimo.appendingPathComponent("fichas.txt"),
                     saimo.appendingPathComponent("destaques.txt")]
        }
        for alvo in alvos { try? gerente.removeItem(at: alvo) }
    }
}

extension Links {
    /// Aplica o plano ao armazenamento e avisa o resto do app. Campo vazio
    /// apaga o endereço e os dados daquela lista.
    static func aplicar(_ plano: Plano) {
        func valor(_ r: Resultado) -> String? { if case .valido(let b) = r { return b } else { return nil } }
        let antesCanais = Enderecos.canais, antesFilmes = Enderecos.filmes
        let novoCanais = valor(plano.canais), novoFilmes = valor(plano.filmes)
        Enderecos.canais = novoCanais
        Enderecos.filmes = novoFilmes
        if antesCanais != novoCanais { Migracao.apagarDados(.canais) }
        if antesFilmes != novoFilmes { Migracao.apagarDados(.filmes) }
        if antesCanais != novoCanais || antesFilmes != novoFilmes {
            NotificationCenter.default.post(name: Enderecos.mudou, object: nil)
        }
    }
}
