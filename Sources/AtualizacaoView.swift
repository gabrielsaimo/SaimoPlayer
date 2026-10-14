import SwiftUI

/// O convite para atualizar: o que mudou, e três saídas claras.
///
/// O DMG já vem baixando por trás, com o andamento aqui. "Atualizar agora"
/// abre o instalador e fecha o app, para o novo poder substituir o antigo.
/// "Depois" volta a perguntar na próxima abertura; "Pular" cala esta
/// versão para sempre.
struct AtualizacaoView: View {
    @ObservedObject var atualizacao: Atualizacao
    let versao: Atualizacao.Versao
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Versão \(versao.numero) disponível")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Você está na \(atualizacao.atual)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            if !versao.notas.isEmpty {
                ScrollView {
                    Text(versao.notas)
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 160)
            }

            andamento

            Text(explicacao)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Pular esta versão") {
                    atualizacao.pular(versao)
                    dismiss()
                }
                Spacer()
                Button("Depois") {
                    atualizacao.depois(versao)
                    dismiss()
                }
                Button(atualizacao.download == .falhou ? "Abrir no navegador" : "Atualizar agora") {
                    atualizacao.atualizar(versao)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(baixando)
            }
        }
        .padding(18)
        .frame(width: 460)
        // Aberto antes de a checagem disparar o download (ou depois de uma
        // falha), o convite pede de novo; para a mesma versão é nada.
        .onAppear { atualizacao.preparar(versao) }
    }

    private var baixando: Bool {
        if case .baixando = atualizacao.download { return true }
        return false
    }

    @ViewBuilder
    private var andamento: some View {
        switch atualizacao.download {
        case .baixando(let fracao):
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: fracao)
                    .progressViewStyle(.linear)
                Text("Baixando a versão nova… \(Int(fracao * 100))%")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        case .pronto:
            Label("Pronta para instalar", systemImage: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.green)
        case .falhou:
            Label("Não deu para baixar aqui dentro.", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.orange)
        case nil:
            EmptyView()
        }
    }

    private var explicacao: String {
        if atualizacao.download == .falhou {
            return "O botão abre a página da versão no navegador e fecha o Saimo TV. Baixe o DMG, abra e arraste o Saimo TV para Aplicativos, substituindo o antigo."
        }
        return "Ao atualizar, o Saimo TV se fecha e abre o instalador: é só arrastar o Saimo TV para Aplicativos, substituindo o antigo."
    }
}
