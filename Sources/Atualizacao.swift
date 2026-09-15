import Foundation
import AppKit

/// Procura versão nova no GitHub e pergunta se quer baixar.
///
/// O app não vem da App Store nem é assinado por um desenvolvedor registrado,
/// então não existe atualização automática de fábrica: sem isto, uma correção
/// só chega a quem lembra de voltar no repositório e baixar o DMG à mão.
///
/// Quem aceita recebe o DMG pelo navegador, e a instalação é a de sempre
/// (arrastar para Aplicativos). O app não baixa nem troca nada por dentro.
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
        var id: String { tag }
    }

    @Published var disponivel: Versao?
    /// Resposta ao "procurar atualização" do menu: sem isto, checar à mão e já
    /// estar atualizado não dá sinal nenhum na tela.
    @Published var aviso: String?

    private let repo = "gabrielsaimo/SaimoPlayer"
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
                if manual { self.aviso = "Não foi possível falar com o GitHub." }
                return
            }
            guard Self.maisNova(lancamento.numero, que: self.atual) else {
                if manual { self.aviso = "Você já está na versão mais recente (\(self.atual))." }
                return
            }
            if !manual {
                if self.defaults.string(forKey: self.chavePulada) == lancamento.tag { return }
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

    /// Abre o DMG no navegador, que baixa pela pasta de Downloads de sempre.
    func baixar(_ versao: Versao) {
        adiada = versao.tag
        disponivel = nil
        NSWorkspace.shared.open(versao.dmg)
    }

    // MARK: - GitHub

    private func buscar() async -> Versao? {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")
        else { return nil }
        var pedido = URLRequest(url: url)
        pedido.timeoutInterval = 20
        pedido.cachePolicy = .reloadIgnoringLocalCacheData
        pedido.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        pedido.setValue(Upstream.userAgent, forHTTPHeaderField: "User-Agent")

        guard let (dados, resposta) = try? await URLSession.shared.data(for: pedido),
              let http = resposta as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let raiz = try? JSONSerialization.jsonObject(with: dados) as? [String: Any],
              let tag = raiz["tag_name"] as? String,
              let ativos = raiz["assets"] as? [[String: Any]]
        else { return await buscarPeloSite() }

        // O nome do arquivo é o contrato com o release: o DMG é a atualização
        // do Mac, e o APK do mesmo release é a do Android.
        guard let dmg = ativos.first(where: {
            ($0["name"] as? String)?.lowercased().hasSuffix(".dmg") == true
        })?["browser_download_url"] as? String, let endereco = URL(string: dmg)
        else { return nil }

        // A tag precisa ter cara de versão ("v1.2" ou "1.2.3"). Um "beta-v2"
        // não diz o que é mais novo que o quê, e comparar o número solto dele
        // com 1.0.0 ofereceria uma atualização para trás.
        guard let numero = Self.numeroDaTag(tag) else { return nil }

        return Versao(tag: tag,
                      numero: numero,
                      notas: (raiz["body"] as? String) ?? "",
                      dmg: endereco)
    }

    /// Reserva para quando a API não responde. Sem conta, ela aceita 60
    /// consultas por hora por IP, e numa rede com muitos aparelhos atrás do
    /// mesmo IP isso acaba. A página /releases/latest não tem esse limite e
    /// redireciona para a tag da versão; o DMG mora num endereço fixo dela.
    private func buscarPeloSite() async -> Versao? {
        guard let url = URL(string: "https://github.com/\(repo)/releases/latest") else { return nil }
        var pedido = URLRequest(url: url)
        pedido.httpMethod = "HEAD"
        pedido.timeoutInterval = 20
        pedido.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (_, resposta) = try? await URLSession.shared.data(for: pedido),
              let final = resposta.url, final.path.contains("/releases/tag/")
        else { return nil }
        let tag = final.lastPathComponent
        guard let numero = Self.numeroDaTag(tag),
              let dmg = URL(string: "https://github.com/\(repo)/releases/download/\(tag)/SaimoTV.dmg")
        else { return nil }
        return Versao(tag: tag, numero: numero, notas: "", dmg: dmg)
    }

    /// "v1.2.3" e "1.2" viram "1.2.3" e "1.2"; qualquer outra coisa, nulo.
    static func numeroDaTag(_ tag: String) -> String? {
        guard let faixa = tag.range(of: "^[vV]?\\d+\\.\\d+(\\.\\d+)?$",
                                    options: .regularExpression) else { return nil }
        return String(tag[faixa]).trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    }

    /// Compara 1.10.0 com 1.9.3 pelo número de cada parte, não pelo texto —
    /// como texto, "1.10" viria antes de "1.9".
    static func maisNova(_ candidata: String, que atual: String) -> Bool {
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
