import Foundation

/// Os dois endereços das listas.
///
/// Vêm de fábrica (só estas duas constantes) e já ativos: o usuário não precisa
/// digitar nada. Em Ajustes > Listas ele pode trocar cada um, ou deixar em
/// branco para desligar aquela lista (fica guardado um valor vazio explícito:
/// estado vazio, sem pedido de rede). "Restaurar padrão" volta aos de fábrica.
/// Chave ausente no `UserDefaults` = padrão.
enum Enderecos {
    static let padraoCanais = "https://canais-saimo.pages.dev/"
    static let padraoFilmes = "https://filmes-saimo.pages.dev/"

    static let chaveCanais = "linkCanais"
    static let chaveFilmes = "linkFilmes"

    /// Muda quando qualquer um dos dois endereços é salvo, apagado ou restaurado.
    static let mudou = Notification.Name("SaimoEnderecosMudaram")

    /// O que vale dado o que está guardado: chave ausente = padrão; vazio
    /// explícito = lista desligada (nulo); senão o valor guardado.
    static func resolver(guardado: String?, padrao: String) -> String? {
        guard let guardado else { return padrao }
        let texto = guardado.trimmingCharacters(in: .whitespacesAndNewlines)
        return texto.isEmpty ? nil : texto
    }

    /// Endereço-base da lista de canais (`catalogo.txt`, `restritos.txt`,
    /// `radios.txt`, `guia.txt`…); nulo quando a lista está desligada.
    static var canais: String? {
        get { resolver(guardado: UserDefaults.standard.string(forKey: chaveCanais), padrao: padraoCanais) }
        set { gravar(chaveCanais, newValue) }
    }

    /// Endereço-base da pasta `vod/` (filmes e séries); nulo quando desligada.
    static var filmes: String? {
        get { resolver(guardado: UserDefaults.standard.string(forKey: chaveFilmes), padrao: padraoFilmes) }
        set { gravar(chaveFilmes, newValue) }
    }

    /// O arquivo `nome` da lista de canais, ou nulo com a lista desligada.
    static func canais(_ nome: String) -> URL? { canais.flatMap { URL(string: $0 + nome) } }

    /// O arquivo `nome` da lista de filmes e séries, ou nulo com a lista desligada.
    static func filmes(_ nome: String) -> URL? { filmes.flatMap { URL(string: $0 + nome) } }

    /// Volta os dois aos de fábrica.
    static func restaurarPadroes() {
        UserDefaults.standard.removeObject(forKey: chaveCanais)
        UserDefaults.standard.removeObject(forKey: chaveFilmes)
    }

    /// Nulo desliga a lista (valor vazio explícito).
    private static func gravar(_ chave: String, _ valor: String?) {
        UserDefaults.standard.set(valor ?? "", forKey: chave)
    }
}
