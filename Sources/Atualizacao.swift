import Foundation
import AppKit

/// Procura versão nova no GitHub e troca o app pela nova, com o aval de quem usa.
///
/// O app não vem da App Store nem é assinado por um desenvolvedor registrado,
/// então não existe atualização automática de fábrica: sem isto, uma correção
/// só chega a quem lembra de voltar no repositório e baixar o DMG à mão.
///
/// A checagem é barata (um JSON de alguns KB) e acontece na abertura, mas com
/// duas travas para não virar incômodo: uma espera de seis horas entre
/// consultas e a versão que a pessoa mandou pular, que não pergunta de novo.
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
    @Published var baixando = false
    @Published var progresso: Double = 0
    @Published var erro: String?
    /// Resposta ao "procurar atualização" do menu: sem isto, checar à mão e já
    /// estar atualizado não dá sinal nenhum na tela.
    @Published var aviso: String?

    private let repo = "gabrielsaimo/SaimoPlayer"
    private let defaults = UserDefaults.standard
    private let chavePulada = "atualizacaoPulada"
    private let chaveVisto = "atualizacaoVistoEm"
    private let espera: TimeInterval = 6 * 60 * 60

    var atual: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// `manual` vem do menu: aí não há espera nem versão pulada que valha, e o
    /// silêncio de "já está atualizado" precisa virar resposta na tela.
    func procurar(manual: Bool = false) {
        if !manual, let visto = defaults.object(forKey: chaveVisto) as? Date,
           Date().timeIntervalSince(visto) < espera { return }
        defaults.set(Date(), forKey: chaveVisto)

        Task { [weak self] in
            guard let self else { return }
            guard let lancamento = await self.buscar() else {
                if manual { self.aviso = "Não foi possível falar com o GitHub." }
                return
            }
            if !manual, self.defaults.string(forKey: self.chavePulada) == lancamento.tag { return }
            guard Self.maisNova(lancamento.numero, que: self.atual) else {
                if manual { self.aviso = "Você já está na versão mais recente (\(self.atual))." }
                return
            }
            self.disponivel = lancamento
        }
    }

    func pular(_ versao: Versao) {
        defaults.set(versao.tag, forKey: chavePulada)
        disponivel = nil
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
        else { return nil }

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

    // MARK: - Instalação

    /// Baixa o DMG e deixa um script trocando o app depois que ele fechar.
    ///
    /// Um app não consegue se substituir enquanto está aberto, então quem faz a
    /// troca é um script solto: ele espera este processo morrer, copia o novo
    /// por cima e abre de volta. Se qualquer passo falhar, o app antigo continua
    /// lá — a troca é uma cópia só, não uma remoção seguida de outra coisa.
    func instalar(_ versao: Versao) {
        guard !baixando else { return }
        baixando = true
        progresso = 0
        erro = nil

        Task { [weak self] in
            guard let self else { return }
            do {
                let arquivo = try await self.baixar(versao.dmg)
                try self.trocar(usando: arquivo)
            } catch {
                self.baixando = false
                self.erro = "Falha ao atualizar: \(error.localizedDescription)"
            }
        }
    }

    private func baixar(_ de: URL) async throws -> URL {
        let (bytes, resposta) = try await URLSession.shared.bytes(from: de)
        guard let http = resposta as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw NSError(domain: "Atualizacao", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "download recusado"])
        }
        
        let destino = FileManager.default.temporaryDirectory
            .appendingPathComponent("SaimoTV-\(UUID().uuidString).dmg")
        FileManager.default.createFile(atPath: destino.path, contents: nil, attributes: nil)
        let fileHandle = try FileHandle(forWritingTo: destino)
        defer { try? fileHandle.close() }
        
        let total = Double(http.expectedContentLength)
        var count = 0.0
        var buffer = Data()
        buffer.reserveCapacity(65536)
        
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 65536 {
                fileHandle.write(buffer)
                count += Double(buffer.count)
                let currentProgress = total > 0 ? count / total : 0
                Task { @MainActor in self.progresso = currentProgress }
                buffer.removeAll(keepingCapacity: true)
            }
        }
        if !buffer.isEmpty {
            fileHandle.write(buffer)
            count += Double(buffer.count)
        }
        
        Task { @MainActor in self.progresso = 1 }
        return destino
    }

    private func trocar(usando dmg: URL) throws {
        let destino = Bundle.main.bundleURL
        let ponto = FileManager.default.temporaryDirectory
            .appendingPathComponent("SaimoTV-\(UUID().uuidString)")
        let script = FileManager.default.temporaryDirectory
            .appendingPathComponent("saimo-atualizar-\(UUID().uuidString).sh")

        let texto = """
        #!/bin/bash
        set -e
        pid=\(ProcessInfo.processInfo.processIdentifier)
        # Espera o app fechar: copiar por cima de um bundle em uso deixa o
        # aplicativo pela metade.
        for _ in $(seq 1 60); do
          kill -0 "$pid" 2>/dev/null || break
          sleep 0.5
        done
        mkdir -p "\(ponto.path)"
        hdiutil attach -nobrowse -noautoopen -quiet "\(dmg.path)" -mountpoint "\(ponto.path)"
        novo=$(find "\(ponto.path)" -maxdepth 1 -name "*.app" | head -1)
        if [ -n "$novo" ]; then
          rsync -a --delete "$novo/" "\(destino.path)/"
          xattr -dr com.apple.quarantine "\(destino.path)" 2>/dev/null || true
        fi
        hdiutil detach "\(ponto.path)" -quiet || true
        rm -f "\(dmg.path)"
        open "\(destino.path)"
        rm -f "$0"
        """
        try texto.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                              ofItemAtPath: script.path)

        let processo = Process()
        processo.executableURL = URL(fileURLWithPath: "/bin/bash")
        processo.arguments = [script.path]
        try processo.run()

        NSApp.terminate(nil)
    }
}
