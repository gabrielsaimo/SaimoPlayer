import Foundation

/// Quem entra na amostra da telemetria.
///
/// O monitor é cobrado por pedido, e milhares de aparelhos batendo a cada
/// poucos minutos custavam caro sem dizer nada que uma parte deles não diga.
/// Só uma fatia estável dos aparelhos (5% hoje) fala com o monitor; o painel
/// multiplica. A conta é a mesma do servidor (`amostrado` no worker.js):
/// FNV-1a de 32 bits sobre o id do aparelho em minúsculas, e entra quem tem
/// `hash % 10000 < amostraPct * 100`. O mesmo aparelho fica sempre do mesmo
/// lado, e o servidor nem grava quem ficou de fora.
///
/// (Padrão 100 e chaves novas, para a versão que passou a ter percentual próprio não herdar o 5 antigo.)
/// O percentual vem de `telemetria.json`, arquivo estático do monitor (servido
/// sem rodar o Worker, de graça), lido no máximo uma vez por dia. O Mac tem poucos
/// aparelhos e fica com o percentual próprio de `porPlataforma.mac` (100%), senão o
/// painel quase nunca mostraria ninguém dele.
enum Amostra {
    static let padraoPct: Double = 100

    private static let endereco = URL(
        string: "https://saimo-monitor.gabrielsaimo68.workers.dev/telemetria.json")!
    private static let validade: TimeInterval = 24 * 3600
    private static let chavePct = "telemetria.amostraPctMac"
    private static let chaveLidoEm = "telemetria.amostraLidaEmMac"

    /// FNV-1a de 32 bits, sem sinal, sobre os bytes UTF-8.
    static func fnv1a(_ texto: String) -> UInt32 {
        var h: UInt32 = 0x811c9dc5
        for b in texto.utf8 {
            h ^= UInt32(b)
            h = h &* 0x01000193
        }
        return h
    }

    static func amostrado(_ id: String, pct: Double) -> Bool {
        Double(fnv1a(id.lowercased()) % 10000) < pct * 100
    }

    /// Percentual válido (0 a 100) ou nulo.
    static func valido(_ valor: Any?) -> Double? {
        guard let n = (valor as? NSNumber)?.doubleValue, n.isFinite, n >= 0, n <= 100 else { return nil }
        return n
    }

    /// O último percentual guardado; 5 se nunca veio.
    static var pct: Double {
        valido(UserDefaults.standard.object(forKey: chavePct)) ?? padraoPct
    }

    static func guardar(_ pct: Double) {
        UserDefaults.standard.set(pct, forKey: chavePct)
    }

    /// Relê `telemetria.json` se a última leitura tem mais de um dia. Devolve
    /// o percentual novo quando leu, nulo quando não precisou ou não deu.
    static func atualizar() async -> Double? {
        let lidoEm = UserDefaults.standard.double(forKey: chaveLidoEm)
        if Date().timeIntervalSince1970 - lidoEm < validade { return nil }
        var pedido = URLRequest(url: endereco, timeoutInterval: 10)
        pedido.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (dados, resposta) = try? await URLSession.shared.data(for: pedido),
              let http = resposta as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let corpo = try? JSONSerialization.jsonObject(with: dados) as? [String: Any],
              let novo = valido((corpo["porPlataforma"] as? [String: Any])?["mac"]) ?? valido(corpo["amostraPct"])
        else { return nil }
        guardar(novo)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: chaveLidoEm)
        return novo
    }
}
