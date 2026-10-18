import Foundation

/// Os dois endereços estáveis de onde o app lê catálogos e anúncio de versão.
/// Ficam aqui, num lugar só: mudar de hospedagem é trocar estas duas linhas.
enum Enderecos {
    /// Canais (`catalogo.txt`, `canais.txt`, `restritos.txt`, `radios.txt`) e
    /// `versao.json`, o anúncio da versão mais nova.
    static let canais = "https://saimo-canais.pages.dev/"
    /// Espelho da pasta `vod/`: índice, filmes, destaques, fichas, gêneros, imdb…
    static let filmes = "https://saimo-filmes.pages.dev/"
}
