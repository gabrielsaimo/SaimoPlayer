import SwiftUI

/// Os episódios da série no ar, num painel por cima do vídeo.
///
/// Trocar de episódio era voltar ao acervo: a grade cobria o vídeo, a lista
/// abria na primeira temporada e nada dizia qual episódio estava tocando.
/// Aqui o vídeo segue por trás, o painel abre na temporada em que se está,
/// com o episódio no ar marcado e à vista, e um clique troca de episódio pelo
/// mesmo caminho do "próximo episódio".
struct PainelEpisodios: View {
    @ObservedObject var model: PlayerModel
    let episodio: EpisodioNoAr

    @State private var temporada: Int
    /// Nome, imagem e duração vindos do TMDB, quando a série tem id.
    @State private var detalhes: [Int: Fichas.EpisodioTMDB] = [:]
    @ObservedObject private var logos = LogoLoader.shared

    init(model: PlayerModel, episodio: EpisodioNoAr) {
        self.model = model
        self.episodio = episodio
        _temporada = State(initialValue: episodio.temporada)
    }

    private func marca(_ t: Int, _ n: Int) -> String { "\(t)-\(n)" }

    var body: some View {
        ZStack(alignment: .trailing) {
            // Clicar fora fecha; o vídeo continua visível, só um pouco mais escuro.
            Color.black.opacity(0.25)
                .contentShape(Rectangle())
                .onTapGesture { fechar() }

            VStack(alignment: .leading, spacing: 12) {
                cabecalho
                if episodio.temporadas.count > 1 {
                    Picker("Temporada", selection: $temporada) {
                        ForEach(episodio.temporadas, id: \.self) { t in
                            Text("Temporada \(t)").tag(t)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 200)
                }
                lista
            }
            .padding(.top, 16)
            .padding(.horizontal, 14)
            .frame(width: 400)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Color.black.opacity(0.88))
            .overlay(alignment: .leading) {
                Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1)
            }
        }
        .task(id: temporada) {
            detalhes = [:]
            detalhes = await Fichas.temporada(episodio.serie, temporada)
        }
    }

    private var cabecalho: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Episódios")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                Text(episodio.serie)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer()
            Button(action: fechar) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 26, height: 26)
                    .background(Color.white.opacity(0.1), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Fechar (Esc)")
        }
    }

    private var lista: some View {
        ScrollViewReader { rolagem in
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(episodio.episodios(da: temporada)) { ep in
                        linha(ep).id(marca(ep.temporada, ep.numero))
                    }
                }
                .padding(.bottom, 16)
            }
            .onAppear { mostrarNoAr(rolagem, animado: false) }
            .onChange(of: temporada) { _, _ in mostrarNoAr(rolagem, animado: true) }
        }
    }

    /// Na temporada do episódio no ar, rola até ele; nas outras, para o topo.
    private func mostrarNoAr(_ rolagem: ScrollViewProxy, animado: Bool) {
        let alvo = temporada == episodio.temporada
            ? marca(episodio.temporada, episodio.numero)
            : episodio.episodios(da: temporada).first.map { marca($0.temporada, $0.numero) }
        guard let alvo else { return }
        // Um ciclo depois: a lista preguiçosa ainda não montou as linhas.
        DispatchQueue.main.async {
            if animado {
                withAnimation { rolagem.scrollTo(alvo, anchor: .top) }
            } else {
                rolagem.scrollTo(alvo, anchor: .center)
            }
        }
    }

    private func linha(_ ep: Episodio) -> some View {
        let noAr = ep.temporada == episodio.temporada && ep.numero == episodio.numero
        let chave = Progresso.chaveEpisodio(episodio.serie, ep.temporada, ep.numero)
        let info = detalhes[ep.numero]
        let nome = info.map(\.nome).flatMap { $0.isEmpty ? nil : $0 } ?? "Episódio \(ep.numero)"
        let fracao: Double? = noAr
            ? (model.duration > 0 ? min(max(model.position / model.duration, 0), 1) : nil)
            : Progresso.fracao(chave)
        let visto = !noAr && Progresso.visto(chave)

        return Button {
            if noAr { fechar() } else { model.tocarEpisodio(ep); fechar() }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                imagem(info?.imagem, numero: ep.numero, noAr: noAr)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(ep.numero). \(nome)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        if noAr {
                            Label("Assistindo", systemImage: "play.fill")
                                .foregroundStyle(Tema.acento)
                        } else if visto {
                            Label("Assistido", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                        if let minutos = info?.duracao, minutos > 0 {
                            Text("\(minutos) min")
                        }
                        if ep.versao != episodio.versao {
                            Text(ep.versao == "leg" ? "Legendado" : "Dublado")
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .labelStyle(.titleAndIcon)
                    if let fracao, fracao > 0 {
                        ProgressView(value: fracao)
                            .progressViewStyle(.linear)
                            .controlSize(.mini)
                            .tint(noAr ? Tema.acento : .white.opacity(0.7))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(noAr ? Tema.acento.opacity(0.22) : Color.white.opacity(0.05)))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(noAr ? Tema.acento.opacity(0.7) : .clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(noAr ? "No ar agora" : "Assistir o episódio \(ep.numero)")
    }

    private func imagem(_ endereco: String?, numero: Int, noAr: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.08))
            if let endereco, let url = URL(string: endereco), let img = logos.image(for: url) {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                Text("\(numero)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            }
            if noAr {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white)
                    .shadow(radius: 3)
            }
        }
        .frame(width: 112, height: 63)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func fechar() { model.painelEpisodios = false }
}
