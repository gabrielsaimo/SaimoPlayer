import Foundation
import Combine

/// O diário do app: vai para o console e para a tela de diagnóstico.
///
/// É escrito de qualquer thread — o proxy, o guia, o player — e lido pela tela
/// na principal. As linhas moram no ator principal; quem escreve de fora só
/// formata a hora (com um formatador que pode ser usado de qualquer thread,
/// ao contrário do DateFormatter que estava aqui) e entrega a linha a ele.
@MainActor
final class Log: ObservableObject {
    /// Acessível de qualquer thread: um objeto do ator principal é seguro de
    /// passar adiante, e é só pelo `write` que os outros falam com ele.
    nonisolated static let shared = Log()

    nonisolated private init() {}

    @Published private(set) var lines: [String] = []

    nonisolated private static let hora = Date.FormatStyle()
        .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits)

    nonisolated func write(_ msg: String) {
        let line = "[\(Date().formatted(Self.hora))] \(msg)"
        NSLog("%@", line)
        Task { @MainActor in
            self.lines.append(line)
            if self.lines.count > 400 { self.lines.removeFirst(self.lines.count - 400) }
        }
    }

    nonisolated func clear() {
        Task { @MainActor in self.lines.removeAll() }
    }
}
