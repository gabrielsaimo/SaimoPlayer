import Foundation
import AppKit

/// Procura versão nova (`versao.json`, no endereço fixo `enderecoDoAnuncio`) e pergunta se quer baixar.
///
/// O app não vem da App Store nem é assinado por um desenvolvedor registrado,
/// então não existe atualização automática de fábrica: sem isto, uma correção
/// só chega a quem lembra de voltar no repositório e baixar o DMG à mão.
///
/// O DMG da versão nova começa a baixar por trás assim que ela aparece
/// (`BaixadorDeAtualizacao`), e o convite mostra o andamento. Pronto, "Atualizar
/// agora" abre o DMG — o Finder mostra o Saimo TV ao lado do atalho para
/// Aplicativos — e fecha o app, para o novo poder substituir o antigo. O app
/// não troca nada por dentro: arrastar continua sendo da pessoa. Se o download
/// não vingar, o botão abre a página da versão no navegador.
///
/// Checa na abertura e de hora em hora com o app aberto: um Mac que fica dias
/// com o app ligado também fica sabendo. "Depois" cala a versão até a próxima
/// abertura; "Pular" cala para sempre.
@MainActor
final class Atualizacao: ObservableObject {

    static let shared = Atualizacao()

    struct Versao: Identifiable {
        let tag: String
        let numero: String
        let notas: String
        let dmg: URL
        /// Bytes do DMG segundo o anúncio; nulo quando não veio.
        let tamanho: Int64?
        /// SHA-256 do DMG segundo o anúncio, em hexadecimal.
        let sha256: String?
        var id: String { tag }
        /// A página da versão, para quando o download aqui dentro falha;
        /// derivada do endereço do instalador, sem dono fixo no código.
        var pagina: URL {
            VersaoPublicada(tag: tag, numero: numero, notas: notas, dmg: dmg,
                            tamanho: tamanho, sha256: sha256).pagina ?? dmg
        }
    }

    /// Onde o DMG da versão nova está.
    enum Download: Equatable {
        case baixando(Double)
        case pronto(URL)
        case falhou
    }

    @Published var disponivel: Versao?
    /// Resposta ao "procurar atualização" do menu: sem isto, checar à mão e já
    /// estar atualizado não dá sinal nenhum na tela.
    @Published var aviso: String?
    /// O download da versão em `baixandoTag`, nulo antes de começar.
    @Published private(set) var download: Download?
    private var baixandoTag: String?
    private var baixador: BaixadorDeAtualizacao?

    private let defaults = UserDefaults.standard
    private let chavePulada = "atualizacaoPulada"
    private let intervalo: UInt64 = 60 * 60
    /// Versão a que a pessoa respondeu "Depois": não pergunta de novo até o
    /// app ser aberto outra vez.
    private var adiada: String?
    private var vigiando = false

    var atual: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Primeira checagem na abertura e as seguintes de hora em hora.
    func vigiar() {
        guard !vigiando else { return }
        vigiando = true
        Task { [weak self] in
            while let self {
                self.procurar()
                try? await Task.sleep(nanoseconds: self.intervalo * 1_000_000_000)
            }
        }
    }

    /// `manual` vem do menu: aí não há versão pulada ou adiada que valha, e o
    /// silêncio de "já está atualizado" precisa virar resposta na tela.
    func procurar(manual: Bool = false) {
        Task { [weak self] in
            guard let self else { return }
            guard let lancamento = await self.buscar() else {
                if manual { self.aviso = "Não foi possível verificar atualizações agora." }
                return
            }
            guard Self.maisNova(lancamento.numero, que: self.atual) else {
                if manual { self.aviso = "Você já está na versão mais recente (\(self.atual))." }
                return
            }
            let pulada = self.defaults.string(forKey: self.chavePulada) == lancamento.tag
            // Baixa já, mesmo que a pessoa diga "Depois": quando ela aceitar,
            // o instalador está pronto.
            if manual || !pulada { self.preparar(lancamento) }
            if !manual {
                if pulada { return }
                if self.adiada == lancamento.tag { return }
                if self.disponivel?.tag == lancamento.tag { return }
            }
            self.disponivel = lancamento
        }
    }

    func pular(_ versao: Versao) {
        defaults.set(versao.tag, forKey: chavePulada)
        disponivel = nil
    }

    func depois(_ versao: Versao) {
        adiada = versao.tag
        disponivel = nil
    }

    /// Abre o DMG baixado (ou, se o download falhou, a página da versão) e
    /// fecha o app: com ele aberto, arrastar o novo para Aplicativos esbarra
    /// no "o item está em uso" na hora de substituir o antigo.
    func atualizar(_ versao: Versao) {
        let alvo: URL
        switch download {
        case .pronto(let arquivo) where baixandoTag == versao.tag: alvo = arquivo
        case .falhou, nil: alvo = versao.pagina
        default: return
        }
        adiada = versao.tag
        disponivel = nil
        NSWorkspace.shared.open(alvo)
        // O pedido sai primeiro; fechar só depois dá tempo de o Finder (ou o
        // navegador) recebê-lo antes de o app sumir.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            NSApp.terminate(nil)
        }
    }

    // MARK: - Download

    /// A pasta dos instaladores, no cache do app: o sistema pode limpá-la, e
    /// não há nada ali que não se baixe de novo.
    private var pasta: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "dev.saimo.player")
            .appendingPathComponent("Atualizacao", isDirectory: true)
    }

    /// Começa (ou retoma) o download do DMG desta versão. Uma vez por versão.
    func preparar(_ versao: Versao) {
        if baixandoTag == versao.tag, download != .falhou { return }
        baixador?.cancelar()
        baixandoTag = versao.tag
        let gerente = FileManager.default
        try? gerente.createDirectory(at: pasta, withIntermediateDirectories: true)
        let destino = pasta.appendingPathComponent("SaimoTV-\(versao.numero).dmg")

        // O que sobrou de versões anteriores sai; o .part desta fica, para retomar.
        for item in (try? gerente.contentsOfDirectory(at: pasta, includingPropertiesForKeys: nil)) ?? []
        where !item.lastPathComponent.hasPrefix(destino.lastPathComponent) {
            try? gerente.removeItem(at: item)
        }

        if BaixadorDeAtualizacao.pronto(destino, tamanho: versao.tamanho, sha256: versao.sha256) {
            download = .pronto(destino)
            return
        }
        try? gerente.removeItem(at: destino)
        download = .baixando(0)
        let tag = versao.tag
        let baixador = BaixadorDeAtualizacao(
            origem: versao.dmg, destino: destino, tamanho: versao.tamanho, sha256: versao.sha256,
            aoAvancar: { [weak self] fracao in
                Task { @MainActor in
                    guard let self, self.baixandoTag == tag, case .baixando = self.download else { return }
                    self.download = .baixando(fracao)
                }
            },
            aoTerminar: { [weak self] arquivo in
                Task { @MainActor in
                    guard let self, self.baixandoTag == tag else { return }
                    self.download = arquivo.map { .pronto($0) } ?? .falhou
                    self.baixador = nil
                }
            })
        self.baixador = baixador
        baixador.comecar()
    }

    // MARK: - Anúncio

    /// Lê `versao.json`. Qualquer falha (rede, JSON, endereço fora da lista)
    /// vira "sem atualização": nunca trava nem derruba o app.
    /// O anúncio da versão: um endereço só, fixo. Infraestrutura do app, não lista.
    nonisolated static let enderecoDoAnuncio =
        "https://github.com/saimo-tv/saimo-downloads/releases/latest/download/versao.json"

    private func buscar() async -> Versao? {
        guard let url = URL(string: Self.enderecoDoAnuncio) else { return nil }
        var pedido = URLRequest(url: url)
        pedido.timeoutInterval = 20
        pedido.cachePolicy = .reloadIgnoringLocalCacheData
        pedido.setValue(Upstream.userAgent, forHTTPHeaderField: "User-Agent")

        guard let (dados, resposta) = try? await URLSession.shared.data(for: pedido),
              let http = resposta as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let v = VersaoPublicada.ler(dados)
        else { return nil }
        return Versao(tag: v.tag, numero: v.numero, notas: v.notas, dmg: v.dmg,
                      tamanho: v.tamanho, sha256: v.sha256)
    }

    /// "v1.2.3" e "1.2" viram "1.2.3" e "1.2"; qualquer outra coisa, nulo.
    nonisolated static func numeroDaTag(_ tag: String) -> String? {
        guard let faixa = tag.range(of: "^[vV]?\\d+\\.\\d+(\\.\\d+)?$",
                                    options: .regularExpression) else { return nil }
        return String(tag[faixa]).trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    }

    /// Compara 1.10.0 com 1.9.3 pelo número de cada parte, não pelo texto —
    /// como texto, "1.10" viria antes de "1.9".
    nonisolated static func maisNova(_ candidata: String, que atual: String) -> Bool {
        let a = candidata.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        let b = atual.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
