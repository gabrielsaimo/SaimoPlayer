import SwiftUI
import Combine

/// O que a interface sabe dos endereços: o que está salvo e se o diálogo da
/// primeira abertura deve aparecer. Quando os endereços mudam, também manda
/// cada parte do app esquecer e recarregar os dados da lista.
@MainActor
final class ListasEstado: ObservableObject {
    static let shared = ListasEstado()

    @Published private(set) var canais: String? = Enderecos.canais
    @Published private(set) var filmes: String? = Enderecos.filmes
    /// O diálogo "Endereço das listas": a cada abertura, enquanto os dois estiverem vazios.
    @Published var pedirEndereco = Links.deveMostrarPrimeiraAbertura(
        canais: Enderecos.canais, filmes: Enderecos.filmes)
    /// Sobe a cada mudança de endereço; telas que guardam dados da lista usam como `.id`.
    @Published private(set) var geracao = 0
    /// O formulário aberto a partir dos Ajustes.
    @Published var editando = false

    private var ouvinte: AnyCancellable?

    private init() {
        ouvinte = NotificationCenter.default.publisher(for: Enderecos.mudou)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.mudou() }
    }

    private func mudou() {
        let antesCanais = canais, antesFilmes = filmes
        canais = Enderecos.canais
        filmes = Enderecos.filmes
        geracao += 1
        if antesCanais != canais {
            Radios.shared.esquecer()
            PlayerModel.shared.recarregarListas()
        }
        if antesFilmes != filmes {
            Vod.esquecer()
            Destaques.esquecer()
            Generos.esquecer()
            VodEstado.shared.reiniciarAcervo()
        }
    }

    func vazioDe(_ secao: Links.Secao) -> String {
        Links.mensagemVazia(secao, canais: canais, filmes: filmes)
    }
}

/// O estado vazio de uma seção sem dados, com atalho para Ajustes.
struct SemListaView: View {
    let secao: Links.Secao
    var compacto = false
    /// O que o botão faz além de ir aos Ajustes (ex.: fechar a folha em que está).
    var antes: (() -> Void)?
    @ObservedObject private var listas = ListasEstado.shared

    var body: some View {
        VStack(spacing: compacto ? 8 : 14) {
            Image(systemName: secao == .filmes ? "film.stack" : secao == .radios ? "radio" : "tv")
                .font(.system(size: compacto ? 22 : 34, weight: .light))
                .foregroundStyle(.white.opacity(0.4))
            Text(listas.vazioDe(secao))
                .font(.system(size: compacto ? 12 : 15))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button {
                antes?()
                Aba.ajustes.abrir()
            } label: {
                Label("Abrir Ajustes", systemImage: "gearshape")
            }
            .buttonStyle(.bordered)
            .controlSize(compacto ? .small : .regular)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A janela "Endereço das listas": primeira abertura e edição nos Ajustes.
struct FormularioListasView: View {
    /// Na primeira abertura o botão de sair é "Agora não"; nos Ajustes, "Cancelar".
    let primeiraAbertura: Bool
    let fechar: () -> Void
    @StateObject private var form: FormularioListas

    init(primeiraAbertura: Bool, fechar: @escaping () -> Void) {
        self.primeiraAbertura = primeiraAbertura
        self.fechar = fechar
        _form = StateObject(wrappedValue: FormularioListas(
            canais: Enderecos.canais, filmes: Enderecos.filmes))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Endereço das listas", systemImage: "link")
                .font(.title2.weight(.semibold))
            Text(Links.textoDoDialogo)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            campo("Canais", texto: $form.canais, tipo: .canais)
            campo("Filmes e séries", texto: $form.filmes, tipo: .filmes)

            mensagem

            HStack {
                Button(primeiraAbertura ? "Agora não" : "Cancelar", action: fechar)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                botoes
            }
        }
        .padding(24)
        .frame(width: 520)
        .onChange(of: form.fase) { _, fase in
            if fase == .concluido { fechar() }
        }
        .onChange(of: form.canais) { _, _ in form.editou() }
        .onChange(of: form.filmes) { _, _ in form.editou() }
    }

    private func campo(_ titulo: String, texto: Binding<String>, tipo: Links.Tipo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titulo).font(.subheadline.weight(.medium))
            TextField("https://…", text: texto)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .disabled(form.fase == .testando)
                .onSubmit { Task { await form.salvar() } }
        }
    }

    @ViewBuilder
    private var mensagem: some View {
        switch form.fase {
        case .invalido(let texto), .falhou(let texto):
            Label(texto, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.orange)
        case .testando:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Testando o endereço…").font(.callout).foregroundStyle(.secondary)
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var botoes: some View {
        switch form.fase {
        case .falhou:
            Button("Salvar mesmo assim") { form.salvarMesmoAssim() }
            Button("Tentar de novo") { Task { await form.tentarDeNovo() } }
                .keyboardShortcut(.defaultAction)
        case .testando:
            Button("Salvar") {}.disabled(true)
        default:
            Button("Salvar") { Task { await form.salvar() } }
                .keyboardShortcut(.defaultAction)
        }
    }
}
