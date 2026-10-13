import Foundation

extension PlayerModel {
    /// Abre o canal de um jogo da tela de Eventos, do mesmo jeito que a lista
    /// de canais: escolhe o canal, e o ao vivo entra quando o acervo fecha.
    func abrirCanalDoJogo(_ canal: Channel) {
        guard let match = channels.first(where: { $0.id == canal.id })
                ?? channels.first(where: { $0.name == canal.name }) else { return }
        // O mesmo canal já escolhido não dispararia a seleção; com o
        // acervo aberto ele ficaria parado.
        if self.selection == match.id { self.play() } else { self.selection = match.id }
        VodEstado.shared.secao = nil
    }
}
