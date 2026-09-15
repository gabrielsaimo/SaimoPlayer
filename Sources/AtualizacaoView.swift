import SwiftUI

/// O convite para atualizar: o que mudou, e três saídas claras.
///
/// Atualizar é a pessoa quem decide, e por fora: "Baixar" abre o DMG no
/// navegador. "Depois" volta a perguntar na próxima abertura; "Pular" cala esta
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

            Text("O download abre no navegador. Depois é só abrir o DMG e arrastar o Saimo TV para Aplicativos, substituindo o antigo.")
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
                Button("Baixar") {
                    atualizacao.baixar(versao)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 460)
    }
}
