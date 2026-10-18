import Foundation
import Combine

/// O estado do formulário "Endereço das listas", sem tela: normaliza, testa
/// cada endereço preenchido na rede e decide o que a interface oferece.
/// Os testes de rede e a gravação entram por parâmetro para o fluxo poder ser
/// testado sem rede (`scripts/testar_links.sh`).
@MainActor
final class FormularioListas: ObservableObject {
    enum Fase: Equatable {
        case editando
        case testando
        /// Endereço mal escrito: nada é testado nem salvo.
        case invalido(String)
        /// O endereço não respondeu: dá para tentar de novo ou salvar assim mesmo.
        case falhou(String)
        case concluido
    }

    @Published var canais: String
    @Published var filmes: String
    @Published private(set) var fase: Fase = .editando

    private let testar: (String, Links.Tipo) async -> Bool
    private let gravar: (Links.Plano) -> Void
    private var plano: Links.Plano?

    init(canais: String? = nil, filmes: String? = nil,
         testar: @escaping (String, Links.Tipo) async -> Bool = { await Links.testar(base: $0, tipo: $1) },
         gravar: @escaping (Links.Plano) -> Void = { Links.aplicar($0) }) {
        self.canais = canais ?? ""
        self.filmes = filmes ?? ""
        self.testar = testar
        self.gravar = gravar
    }

    /// Botão Salvar.
    func salvar() async {
        let plano = Links.planejar(canais: canais, filmes: filmes)
        guard !plano.temInvalido else {
            fase = .invalido(Links.erroDeFormato)
            return
        }
        self.plano = plano
        await testarEGravar(plano)
    }

    /// Botão "Tentar de novo": testa outra vez o mesmo que foi digitado.
    func tentarDeNovo() async { await salvar() }

    /// Botão "Salvar mesmo assim": grava sem o teste passar.
    func salvarMesmoAssim() {
        let plano = self.plano ?? Links.planejar(canais: canais, filmes: filmes)
        guard !plano.temInvalido else { return }
        gravar(plano)
        fase = .concluido
    }

    /// Voltou a digitar: a mensagem de erro some.
    func editou() {
        if case .concluido = fase { return }
        if fase != .testando { fase = .editando }
    }

    private func testarEGravar(_ plano: Links.Plano) async {
        let itens = plano.aTestar
        guard !itens.isEmpty else {
            // Tudo em branco: grava (apaga o que havia) sem pedido nenhum.
            gravar(plano)
            fase = .concluido
            return
        }
        fase = .testando
        var todosOk = true
        for (tipo, base) in itens {
            if await !testar(base, tipo) { todosOk = false }
        }
        if todosOk {
            gravar(plano)
            fase = .concluido
        } else {
            fase = .falhou(Links.erroDeEndereco)
        }
    }
}
