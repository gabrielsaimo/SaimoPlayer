import Foundation

/// Os dois endereços das listas, digitados pelo usuário (Ajustes > Listas).
///
/// O app não traz endereço nenhum de fábrica: sem eles, nenhum pedido de rede
/// para listas é feito. Ficam no `UserDefaults`, já normalizados (ver
/// `Links.normalizar`), sempre com `/` no fim.
enum Enderecos {
    static let chaveCanais = "linkCanais"
    static let chaveFilmes = "linkFilmes"

    /// Muda quando qualquer um dos dois endereços é salvo ou apagado.
    static let mudou = Notification.Name("SaimoEnderecosMudaram")

    /// Endereço-base da lista de canais (`catalogo.txt`, `restritos.txt`,
    /// `radios.txt`, `guia.txt`…); nulo quando não foi informado.
    static var canais: String? {
        get { ler(chaveCanais) }
        set { gravar(chaveCanais, newValue) }
    }

    /// Endereço-base da pasta `vod/` (filmes e séries); nulo quando não foi informado.
    static var filmes: String? {
        get { ler(chaveFilmes) }
        set { gravar(chaveFilmes, newValue) }
    }

    /// O arquivo `nome` da lista de canais, ou nulo sem endereço.
    static func canais(_ nome: String) -> URL? { canais.flatMap { URL(string: $0 + nome) } }

    /// O arquivo `nome` da lista de filmes e séries, ou nulo sem endereço.
    static func filmes(_ nome: String) -> URL? { filmes.flatMap { URL(string: $0 + nome) } }

    private static func ler(_ chave: String) -> String? {
        let texto = UserDefaults.standard.string(forKey: chave)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (texto?.isEmpty ?? true) ? nil : texto
    }

    private static func gravar(_ chave: String, _ valor: String?) {
        if let valor, !valor.isEmpty {
            UserDefaults.standard.set(valor, forKey: chave)
        } else {
            UserDefaults.standard.removeObject(forKey: chave)
        }
    }
}
