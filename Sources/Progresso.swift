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
            defaults.removeObject(forKey: chaveBase + chave + "|t")
            return
        }
        defaults.set(posicao, forKey: chaveBase + chave)
        defaults.set(duracao, forKey: chaveBase + chave + "|d")
        defaults.set(Date().timeIntervalSince1970, forKey: chaveBase + chave + "|t")
        // Gravar em disco na hora: o app pode ser fechado à força, e o valor
        // que interessa é justamente o do instante em que isso acontecer.
        defaults.synchronize()
    }

    /// Posição guardada, ou zero.
    static func posicao(_ chave: String) -> Double {
        UserDefaults.standard.double(forKey: chaveBase + chave)
    }

    /// O que está pela metade, do visto mais recentemente para o mais antigo.
    ///
    /// É o que alimenta a fileira "Continue assistindo". O horário passou a ser
    /// gravado junto por causa dela: sem ele não dá para dizer qual título foi
    /// o último, e uma fileira em ordem alfabética não continua coisa nenhuma.
    /// Quem gravou antes disso não tem horário e fica no fim, uma vez só.
    static func emAndamento() -> [Andamento] {
        let tudo = UserDefaults.standard.dictionaryRepresentation()
        var out: [Andamento] = []
        for (chaveCompleta, valor) in tudo {
            guard chaveCompleta.hasPrefix(chaveBase) else { continue }
            let chave = String(chaveCompleta.dropFirst(chaveBase.count))
            if chave.hasSuffix("|d") || chave.hasSuffix("|t") { continue }
            guard let posicao = valor as? Double, posicao > 0 else { continue }
            guard let duracao = tudo[chaveBase + chave + "|d"] as? Double, duracao > 0 else {
                continue
            }
            let quando = tudo[chaveBase + chave + "|t"] as? Double ?? 0
            let campos = chave.split(separator: "|", omittingEmptySubsequences: false)
                .map(String.init)
            let serie = campos.first == "s"
            guard campos.count > 1 else { continue }
            let titulo = campos[1]
            let rotulo = serie && campos.count >= 4
                ? "\(titulo) · T\(campos[2]) E\(campos[3])"
                : titulo
            out.append(Andamento(chave: chave, titulo: titulo, rotulo: rotulo,
                                 serie: serie,
                                 fracao: min(max(posicao / duracao, 0), 1),
                                 quando: quando))
        }
        return out.sorted { $0.quando > $1.quando }
    }

    struct Andamento: Identifiable {
        let chave: String
        /// O nome do título, que é por onde se acha ele no acervo.
        let titulo: String
        /// O que aparece na capa: na série, com temporada e episódio.
        let rotulo: String
        let serie: Bool
        let fracao: Double
        let quando: Double
        var id: String { chave }
    }

    /// Quanto do título já foi visto, de 0 a 1, ou nil se nunca foi aberto.
    static func fracao(_ chave: String) -> Double? {
        let posicao = UserDefaults.standard.double(forKey: chaveBase + chave)
        let duracao = UserDefaults.standard.double(forKey: chaveBase + chave + "|d")
        guard posicao > 0, duracao > 0 else { return nil }
        return min(max(posicao / duracao, 0), 1)
    }
}
