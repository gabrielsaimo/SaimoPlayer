import Foundation

/// Onde cada filme e episódio parou.
///
/// A chave é o título e, na série, a temporada e o episódio — não a URL: o mesmo
/// episódio vem de fontes diferentes e, se a primeira falhar, a segunda tem de
/// retomar no mesmo ponto.
///
/// Isto fica gravado de propósito, ao contrário das capas: voltar ao ponto em
/// que se parou não é enfeite, é a diferença entre continuar um filme e
/// recomeçá-lo.
enum Progresso {

    private static let chaveBase = "progresso."
    /// Menos de um minuto não é "onde parou", é ter aberto e desistido.
    private static let minimo: Double = 60
    /// A dois minutos do fim o episódio está visto: retomar ali só irrita.
    private static let sobra: Double = 120

    static func chaveFilme(_ titulo: String) -> String { "f|\(titulo)" }

    static func chaveEpisodio(_ serie: String, _ temporada: Int, _ numero: Int) -> String {
        "s|\(serie)|\(temporada)|\(numero)"
    }

    static func salvar(_ chave: String, posicao: Double, duracao: Double) {
        guard !chave.isEmpty, duracao > 0, posicao.isFinite else { return }
        let defaults = UserDefaults.standard
        guard posicao >= minimo, posicao <= duracao - sobra else {
            // Acabou de começar ou já terminou: nada a retomar.
            defaults.removeObject(forKey: chaveBase + chave)
            defaults.removeObject(forKey: chaveBase + chave + "|d")
            return
        }
        defaults.set(posicao, forKey: chaveBase + chave)
        defaults.set(duracao, forKey: chaveBase + chave + "|d")
        // Gravar em disco na hora: o app pode ser fechado à força, e o valor
        // que interessa é justamente o do instante em que isso acontecer.
        defaults.synchronize()
    }

    /// Posição guardada, ou zero.
    static func posicao(_ chave: String) -> Double {
        UserDefaults.standard.double(forKey: chaveBase + chave)
    }

    /// Quanto do título já foi visto, de 0 a 1, ou nil se nunca foi aberto.
    static func fracao(_ chave: String) -> Double? {
        let posicao = UserDefaults.standard.double(forKey: chaveBase + chave)
        let duracao = UserDefaults.standard.double(forKey: chaveBase + chave + "|d")
        guard posicao > 0, duracao > 0 else { return nil }
        return min(max(posicao / duracao, 0), 1)
    }
}
