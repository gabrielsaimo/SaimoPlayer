import SwiftUI

/// As rádios, no formato da tela inicial, como na TV Box: o destaque em cima
/// mostra a rádio sob o ponteiro (ou a que está tocando, com as barras do
/// equalizador), e embaixo as fileiras — as ouvidas por último, uma por estilo
/// e todas de A a Z, uma fileira por letra.
struct TelaRadios: View {
    @ObservedObject private var radios = Radios.shared
    @State private var destaque = DestaqueEstado()

    var body: some View {
        TelaEmFileiras(destaque: destaque, filas: filas, carregando: radios.lista.isEmpty,
                       vazio: "Sem rádios por enquanto. Confira a internet e abra de novo.") {
            if let radio = radios.tocando {
                RadioTocando(radio: radio)
            } else {
                DestaqueTopo(estado: destaque)
            }
        }
        .task {
            destaque.padrao("Rádios", "Carregando…")
            await radios.carregar()
            destaque.padrao("Rádios", "\(radios.lista.count) rádios ao vivo",
                            "Clique para ouvir; o vídeo fica parado enquanto a rádio toca.")
            // Para conferir a rádio tocando sem clicar: `--args -radioInicial nome`.
            if radios.tocando == nil, let nome = UserDefaults.standard.string(forKey: "radioInicial"),
               let radio = radios.lista.first(where: { $0.nome == nome }) {
                radios.tocar(radio)
            }
        }
    }

    private var filas: [Fila] {
        let lista = radios.lista
        guard !lista.isEmpty else { return [] }
        var out: [Fila] = []
        let recentes = radios.recentes
        if !recentes.isEmpty {
            out.append(Fila(titulo: "Ouvidas por último", tipo: .largo, cartoes: recentes.map(cartao)))
        }
        let porEstilo = Dictionary(grouping: lista) { Radios.estilo(de: $0)?.titulo ?? "" }
        for estilo in Radios.estilos {
            let doEstilo = porEstilo[estilo.titulo] ?? []
            if doEstilo.count >= 4 {
                out.append(Fila(titulo: estilo.titulo, tipo: .largo, cartoes: doEstilo.map(cartao)))
            }
        }
        let porLetra = Dictionary(grouping: lista, by: Radios.letra(de:))
        for letra in porLetra.keys.sorted() {
            out.append(Fila(titulo: letra == "#" ? "0 a 9" : letra, tipo: .largo,
                            cartoes: (porLetra[letra] ?? []).map(cartao)))
        }
        return out
    }

    private func cartao(_ radio: Radios.Radio) -> CartaoFila {
        let estilo = Radios.estilo(de: radio)?.titulo
        let tocando = radios.tocando?.id == radio.id
        return CartaoFila(
            id: "radio:" + radio.id,
            titulo: radio.nome,
            subtitulo: tocando ? "tocando agora" : estilo,
            capa: radio.logo,
            selo: tocando ? "TOCANDO" : nil,
            seloAoVivo: tocando,
            meta: (["Rádio ao vivo", estilo].compactMap { $0 }).joined(separator: "  ·  "),
            sinopse: "Clique para ouvir."
        ) {
            radios.tocar(radio)
        }
    }
}

/// A rádio tocando, no lugar do destaque: o logo, o nome, o estilo, as
/// barras que dançam enquanto sai som e os botões de vidro.
private struct RadioTocando: View {
    let radio: Radios.Radio
    @ObservedObject private var radios = Radios.shared

    var body: some View {
        HStack(alignment: .center, spacing: 26) {
            ImagemRemota(endereco: radio.logo, modo: .fit) {
                Text(String(radio.nome.first { $0.isLetter || $0.isNumber } ?? "R").uppercased())
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(width: 120, height: 120)
            .padding(14)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: Tema.acento.opacity(0.25), radius: 24)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Circle().fill(radios.falhou ? Color.gray : Tema.aoVivo).frame(width: 9, height: 9)
                        .opacity(radios.noAr ? 1 : 0.5)
                    Text(radios.falhou ? "FORA DO AR" : radios.noAr ? "NO AR" : "CONECTANDO")
                        .font(.system(size: 12, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(Tema.acento)
                }
                Text(radio.nome)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let estilo = Radios.estilo(de: radio)?.titulo {
                    Text(estilo).font(.system(size: 14)).foregroundStyle(Tema.textoSecundario)
                }
                Equalizador(tocando: radios.noAr)
                    .frame(width: 260, height: 34)
                GrupoDeVidro {
                    HStack(spacing: 10) {
                        Button { radios.alternar() } label: {
                            Label(radios.pausada ? "Ouvir" : "Pausar",
                                  systemImage: radios.pausada ? "play.fill" : "pause.fill")
                        }
                        .botaoDeVidro(proeminente: true)
                        Button { radios.parar() } label: { Label("Parar", systemImage: "stop.fill") }
                            .botaoDeVidro()
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Barras de equalizador. Não é o som de verdade: é um movimento que segue
/// enquanto a rádio toca e desce até parar quando ela carrega ou trava — o
/// que já diz se está no ar.
struct Equalizador: View {
    let tocando: Bool
    private let barras = 28

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !tocando)) { contexto in
            let t = contexto.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let passo = geo.size.width / CGFloat(barras)
                HStack(alignment: .bottom, spacing: passo * 0.45) {
                    ForEach(0..<barras, id: \.self) { i in
                        let alvo = tocando
                            ? 0.25 + 0.75 * abs(sin(t * (2.1 + Double(i % 5) * 0.37) + Double(i) * 0.9) * sin(t * 0.9 + Double(i) * 0.31))
                            : 0.08
                        Capsule()
                            .fill(LinearGradient(colors: [Tema.acento, Color(red: 0.6, green: 0.48, blue: 1)],
                                                 startPoint: .bottom, endPoint: .top))
                            .frame(width: passo * 0.55, height: max(3, geo.size.height * alvo))
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .animation(.easeOut(duration: 0.12), value: tocando)
            }
        }
    }
}
