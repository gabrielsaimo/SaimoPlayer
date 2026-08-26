import SwiftUI

/// O convite para atualizar: o que mudou, e três saídas claras.
///
/// Atualizar é a pessoa quem decide — o app não troca nada sozinho. "Depois"
/// volta a perguntar na próxima abertura; "Pular" cala esta versão para sempre.
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

            if atualizacao.baixando {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView().progressViewStyle(.linear)
                    Text("Baixando… o app fecha e abre sozinho quando terminar.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            if let erro = atualizacao.erro {
                Text(erro).font(.system(size: 11)).foregroundStyle(.red)
            }

            HStack {
                Button("Pular esta versão") {
                    atualizacao.pular(versao)
                    dismiss()
                }
                .disabled(atualizacao.baixando)
                Spacer()
                Button("Depois") { dismiss() }
                    .disabled(atualizacao.baixando)
                Button("Atualizar") { atualizacao.instalar(versao) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(atualizacao.baixando)
            }
        }
        .padding(18)
        .frame(width: 460)
    }
}
