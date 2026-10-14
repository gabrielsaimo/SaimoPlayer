import Foundation
import SwiftUI

/// Os jogos de hoje e dos próximos dias que passam em algum canal da lista,
/// com a mesma lógica da tela de Eventos do TV Box e do celular.
///
/// Três fontes: a agenda da embedtv diz em que canal cada jogo passa; a do
/// monitor traz os jogos dos canais de streaming (CazéTV, Disney+, Prime,
/// Paramount+, GOAT, ge tv, N Sports, SportyNet) que a embedtv não tem, no
/// mesmo formato e com placar; os placares da ESPN dizem se já começou, o
/// placar e o tempo de jogo, e trazem escudos melhores. Só entra jogo que tem canal (sem canal não há o que
/// assistir), e jogo encerrado sai.
struct Jogo: Identifiable, Sendable {
    var casa: String
    var fora: String
    var casaLogo: String
    var foraLogo: String
    var liga: String
    var ligaLogo: String
    var inicio: Date
    var fim: Date
    var canal: Channel
    /// "pre", "in" ou "post", quando a ESPN conhece o jogo.
    var estado = ""
    var placar = ""
    var tempo = ""

    var titulo: String { "\(casa) x \(fora)" }
    var id: String { "\(titulo)|\(inicio.timeIntervalSince1970)" }

    func aoVivo(_ agora: Date) -> Bool {
        estado == "in" || (estado != "post" && agora >= inicio && agora <= fim)
    }
    func acabou(_ agora: Date) -> Bool { estado == "post" || agora > fim }
}

enum Eventos {
    static let agenda = URL(string: "https://embedtv.cc/api/events")!
    static let streaming = URL(string: "https://saimo-monitor.gabrielsaimo68.workers.dev/v1/eventos")!
    static let ligas = [
        "soccer/bra.1", "soccer/bra.2", "soccer/bra.copa_do_brazil", "soccer/conmebol.libertadores",
        "soccer/conmebol.sudamericana", "soccer/uefa.champions", "soccer/uefa.europa", "soccer/eng.1",
        "soccer/esp.1", "soccer/ita.1", "soccer/ger.1", "soccer/fra.1", "soccer/por.1", "soccer/ned.1",
        "soccer/arg.1", "soccer/ksa.1", "soccer/fifa.world", "soccer/fifa.worldq.conmebol",
        "basketball/nba", "football/nfl", "baseball/mlb", "hockey/nhl", "mma/ufc",
    ]
    static let siglas: Set<String> = ["fc", "ec", "sc", "ac", "afc", "cf", "cd", "club", "clube",
        "esporte", "sport", "futebol", "de", "do", "da", "sp", "rj", "mg", "rs", "pr", "ba", "pe",
        "ce", "go", "sad"]
    static let hora: TimeInterval = 3600

    /// O placar de um jogo na ESPN.
    struct Placar: Sendable {
        var casa, fora, casaLogo, foraLogo, ligaLogo: String
        var inicio: Date
        var estado, golsCasa, golsFora, tempo: String
    }

    private static func baixar(_ url: URL) async -> Data? {
        var pedido = URLRequest(url: url, timeoutInterval: 15)
        pedido.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        guard let (dados, resposta) = try? await URLSession.shared.data(for: pedido),
              let http = resposta as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
        return dados
    }

    /// "2026-10-13T21:30:00-03:00" na agenda, "2026-10-16T23:00Z" na ESPN.
    private static func data(_ texto: String?) -> Date? {
        guard let texto, !texto.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: texto) { return d }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: texto) { return d }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd'T'HH:mmXXXXX"
        return df.date(from: texto)
    }

    /// O canal pelo fim do endereço do player ("…/premiere-fc" é o Premiere FC).
    static func canalDo(_ url: String, _ canais: [Channel]) -> Channel? {
        let fim = url.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? ""
        let slug = fim.lowercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: "")
        guard !slug.isEmpty else { return nil }
        func chave(_ c: Channel) -> String { c.name.lowercased().replacingOccurrences(of: " ", with: "") }
        return canais.first { chave($0) == slug } ?? canais.first { chave($0).contains(slug) }
    }

    /// A agenda (da embedtv ou do monitor): só jogos cujo canal existe na nossa lista.
    private static func lerAgenda(_ dados: Data, _ canais: [Channel]) -> [Jogo] {
        guard let lista = (try? JSONSerialization.jsonObject(with: dados)) as? [[String: Any]] else { return [] }
        var vistos = Set<String>()
        var jogos: [Jogo] = []
        for o in lista {
            // Jogo com dados faltando fica de fora.
            guard let player = (o["players"] as? [String])?.first,
                  let canal = canalDo(player, canais),
                  let times = o["teams"] as? [String: Any],
                  let casa = times["home"] as? [String: Any], let fora = times["away"] as? [String: Any],
                  let nomeCasa = casa["name"] as? String, let nomeFora = fora["name"] as? String,
                  let inicio = data(o["time_start"] as? String) else { continue }
            let liga = o["league"] as? [String: Any]
            let jogo = Jogo(
                casa: nomeCasa, fora: nomeFora,
                casaLogo: (casa["image"] as? String ?? "").emAltaResolucao,
                foraLogo: (fora["image"] as? String ?? "").emAltaResolucao,
                liga: liga?["name"] as? String ?? "",
                ligaLogo: (liga?["image"] as? String ?? "").emAltaResolucao,
                inicio: inicio, fim: data(o["time_end"] as? String) ?? inicio.addingTimeInterval(2 * hora),
                canal: canal,
                // Só a agenda do monitor manda o placar; a ESPN, quando acha o jogo, vale mais.
                estado: o["estado"] as? String ?? "", placar: o["placar"] as? String ?? "",
                tempo: o["tempo"] as? String ?? "")
            guard vistos.insert(jogo.id).inserted else { continue }
            jogos.append(jogo)
        }
        return jogos
    }

    private static func lerEspn(_ dados: Data) -> [Placar] {
        guard let raiz = (try? JSONSerialization.jsonObject(with: dados)) as? [String: Any] else { return [] }
        let ligaLogo = (((raiz["leagues"] as? [[String: Any]])?.first?["logos"] as? [[String: Any]])?
            .first?["href"] as? String) ?? ""
        var saida: [Placar] = []
        for ev in raiz["events"] as? [[String: Any]] ?? [] {
            let comps = ((ev["competitions"] as? [[String: Any]])?.first?["competitors"] as? [[String: Any]]) ?? []
            guard let casa = comps.first(where: { $0["homeAway"] as? String == "home" }),
                  let fora = comps.first(where: { $0["homeAway"] as? String != "home" }) else { continue }
            let tipo = (ev["status"] as? [String: Any])?["type"] as? [String: Any]
            let estado = tipo?["state"] as? String ?? ""
            let timeCasa = casa["team"] as? [String: Any]
            let timeFora = fora["team"] as? [String: Any]
            saida.append(Placar(
                casa: timeCasa?["name"] as? String ?? "", fora: timeFora?["name"] as? String ?? "",
                casaLogo: timeCasa?["logo"] as? String ?? "", foraLogo: timeFora?["logo"] as? String ?? "",
                ligaLogo: ligaLogo,
                inicio: data(ev["date"] as? String) ?? Date(timeIntervalSince1970: 0),
                estado: estado,
                golsCasa: casa["score"] as? String ?? "", golsFora: fora["score"] as? String ?? "",
                tempo: estado == "in" ? tipo?["shortDetail"] as? String ?? "" : ""))
        }
        return saida
    }

    /// Só palavras inteiras de sigla saem: "Palmeiras" e "SE Palmeiras" casam.
    static func chaveTime(_ nome: String) -> String {
        let limpo = nome.folding(options: .diacriticInsensitive, locale: nil).lowercased()
        return limpo.split { !(("a"..."z").contains($0) || ("0"..."9").contains($0)) }
            .map(String.init).filter { !siglas.contains($0) }.joined()
    }

    static func mesmoTime(_ a: String, _ b: String) -> Bool {
        let x = chaveTime(a), y = chaveTime(b)
        guard !x.isEmpty, !y.isEmpty else { return false }
        return x == y || (x.count >= 4 && y.contains(x)) || (y.count >= 4 && x.contains(y))
    }

    /// Nulo quando a agenda não veio.
    static func buscarJogos(_ canais: [Channel]) async -> [Jogo]? {
        async let corpo = baixar(agenda)
        async let doMonitor = baixar(streaming)
        let espn = await withTaskGroup(of: [Placar].self) { grupo in
            for liga in ligas {
                guard let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/\(liga)/scoreboard") else { continue }
                grupo.addTask { await baixar(url).map(lerEspn) ?? [] }
            }
            var todos: [Placar] = []
            for await lidos in grupo { todos += lidos }
            return todos
        }
        guard let dados = await corpo else { return nil }
        let daEmbed = lerAgenda(dados, canais)
        // Jogo do monitor que a embedtv já tem (mesmos times, começo a menos de
        // meia hora) não entra de novo.
        let extras = (await doMonitor).map { lerAgenda($0, canais) }?.filter { x in
            !daEmbed.contains { e in
                abs(e.inicio.timeIntervalSince(x.inicio)) < hora / 2 &&
                    ((mesmoTime(e.casa, x.casa) && mesmoTime(e.fora, x.fora)) ||
                        (mesmoTime(e.casa, x.fora) && mesmoTime(e.fora, x.casa)))
            }
        } ?? []
        return (daEmbed + extras).map { jogo in
            // O mesmo jogo na ESPN: mesmos times (em qualquer ordem) e começo
            // a menos de quatro horas um do outro.
            guard let par = espn.first(where: { e in
                abs(e.inicio.timeIntervalSince(jogo.inicio)) < 4 * hora &&
                    ((mesmoTime(e.casa, jogo.casa) && mesmoTime(e.fora, jogo.fora)) ||
                        (mesmoTime(e.casa, jogo.fora) && mesmoTime(e.fora, jogo.casa)))
            }) else { return jogo }
            // A ESPN pode listar os times na ordem inversa da agenda: aí o
            // escudo e os gols dela vão para o outro lado, senão o time
            // mostrado ganha o escudo do adversário e o placar sai invertido.
            let invertido = !(mesmoTime(par.casa, jogo.casa) && mesmoTime(par.fora, jogo.fora))
            let (logoCasa, logoFora) = invertido ? (par.foraLogo, par.casaLogo) : (par.casaLogo, par.foraLogo)
            let (golsCasa, golsFora) = invertido ? (par.golsFora, par.golsCasa) : (par.golsCasa, par.golsFora)
            var novo = jogo
            if !logoCasa.isEmpty { novo.casaLogo = logoCasa }
            if !logoFora.isEmpty { novo.foraLogo = logoFora }
            if novo.ligaLogo.isEmpty { novo.ligaLogo = par.ligaLogo }
            novo.estado = par.estado
            novo.placar = par.estado == "pre" ? "" : "\(golsCasa) x \(golsFora)"
            novo.tempo = par.tempo
            return novo
        }
    }

    // MARK: - Datas

    private static func diaDe(_ data: Date) -> Date { Calendar.current.startOfDay(for: data) }

    /// Quantos dias do calendário separam a data de hoje.
    static func dias(_ inicio: Date, _ agora: Date) -> Int {
        Calendar.current.dateComponents([.day], from: diaDe(agora), to: diaDe(inicio)).day ?? 0
    }

    private static func formato(_ padrao: String) -> DateFormatter {
        let df = DateFormatter()
        df.locale = Locale(identifier: "pt_BR")
        df.dateFormat = padrao
        return df
    }

    /// "21:30", "amanhã 16:00" ou "sáb 16:00".
    static func quando(_ inicio: Date, _ agora: Date) -> String {
        let h = formato("HH:mm").string(from: inicio)
        let d = dias(inicio, agora)
        if d <= 0 { return h }
        if d == 1 { return "amanhã \(h)" }
        let semana = formato("EEE").string(from: inicio).replacingOccurrences(of: ".", with: "")
        return "\(semana) \(h)"
    }

    static let grupos = ["Ao vivo agora", "Começa em breve", "Hoje mais tarde", "Amanhã", "Próximos dias"]

    static func grupoDe(_ j: Jogo, _ agora: Date) -> Int {
        if j.aoVivo(agora) { return 0 }
        if j.inicio.timeIntervalSince(agora) <= 2 * hora { return 1 }
        let d = dias(j.inicio, agora)
        if d <= 0 { return 2 }
        return d == 1 ? 3 : 4
    }
}

@MainActor
final class EventsService: ObservableObject {
    static let shared = EventsService()

    /// Nulo enquanto a primeira busca não voltou.
    @Published private(set) var jogos: [Jogo]?
    @Published private(set) var erro = false
    @Published private(set) var agora = Date()
    private var buscando = false

    private init() {}

    func carregar(_ canais: [Channel]) async {
        guard !buscando, !canais.isEmpty else { return }
        buscando = true
        defer { buscando = false }
        let lidos = await Eventos.buscarJogos(canais)
        agora = Date()
        if let lidos {
            jogos = lidos
            erro = false
        } else {
            erro = true
        }
    }
}

/// A tela de Eventos, como na TV Box: o jogo sob o ponteiro em destaque no
/// alto (liga, placar e tempo, o canal) e os jogos em fileiras por horário —
/// ao vivo agora, começa em breve, hoje mais tarde, amanhã, próximos dias.
/// Clicar num cartão abre o canal do jogo.
struct EventsView: View {
    @ObservedObject var model: PlayerModel
    @ObservedObject private var service = EventsService.shared
    @StateObject private var destaque = DestaqueEstado()

    /// O placar anda: com a tela aberta, busca de novo a cada minuto.
    private static let intervalo: Duration = .seconds(60)

    /// Canal adulto não entra na agenda.
    private var canais: [Channel] {
        model.channels.filter { Categoria.de($0) != .adulto }
    }

    private var grupos: [(titulo: String, jogos: [Jogo])] {
        let agora = service.agora
        let restantes = (service.jogos ?? []).filter { !$0.acabou(agora) }.sorted { $0.inicio < $1.inicio }
        var listas = Array(repeating: [Jogo](), count: Eventos.grupos.count)
        for j in restantes { listas[Eventos.grupoDe(j, agora)].append(j) }
        return zip(Eventos.grupos, listas).filter { !$0.1.isEmpty }.map { (titulo: $0.0, jogos: $0.1) }
    }

    var body: some View {
        let grupos = self.grupos
        TelaEmFileiras(
            destaque: destaque,
            filas: grupos.map { grupo in
                Fila(titulo: grupo.titulo, tipo: .evento, cartoes: grupo.jogos.map(cartao))
            },
            carregando: service.jogos == nil && !service.erro,
            vazio: service.erro
                ? "Não deu para carregar a agenda agora. Tentando de novo em um minuto."
                : "Nenhum jogo nos canais da lista agora. A agenda se atualiza sozinha.")
        .onAppear { padrao(grupos) }
        .onChange(of: service.jogos?.count) { _, _ in padrao(self.grupos) }
        // Enquanto a tela está aberta; sai dela, a busca para.
        .task(id: model.channels.isEmpty) {
            while !Task.isCancelled {
                await service.carregar(canais)
                try? await Task.sleep(for: Self.intervalo)
            }
        }
    }

    /// Sem jogo sob o ponteiro, o destaque mostra o primeiro jogo ao vivo
    /// (ou o próximo), como a TV mostra o cartão focado ao abrir.
    private func padrao(_ grupos: [(titulo: String, jogos: [Jogo])]) {
        if let primeiro = grupos.first?.jogos.first {
            let c = cartao(primeiro)
            destaque.padrao(c.titulo, c.meta ?? "", c.sinopse ?? "")
        } else {
            destaque.padrao("Eventos", resumo(grupos))
        }
    }

    private func cartao(_ jogo: Jogo) -> CartaoFila {
        let agora = service.agora
        let vivo = jogo.aoVivo(agora)
        let selo = vivo
            ? (["AO VIVO", jogo.placar.replacingOccurrences(of: "-", with: "x")].filter { !$0.isEmpty }.joined(separator: "  "))
            : Eventos.quando(jogo.inicio, agora)
        var meta = [jogo.liga]
        if vivo {
            meta.append((["AO VIVO", jogo.placar, jogo.tempo].filter { !$0.isEmpty }).joined(separator: " "))
        } else {
            meta.append(Eventos.quando(jogo.inicio, agora))
        }
        return CartaoFila(
            id: jogo.id,
            titulo: jogo.titulo,
            subtitulo: [jogo.canal.name, jogo.liga].filter { !$0.isEmpty }.joined(separator: " · "),
            selo: selo,
            seloAoVivo: vivo,
            meta: meta.filter { !$0.isEmpty }.joined(separator: "  ·  "),
            sinopse: "No canal \(jogo.canal.name) · clique para assistir",
            escudos: (jogo.casaLogo, jogo.foraLogo, jogo.casa, jogo.fora),
            logoLiga: jogo.ligaLogo
        ) {
            model.abrirCanalDoJogo(jogo.canal)
        }
    }

    private func resumo(_ grupos: [(titulo: String, jogos: [Jogo])]) -> String {
        let total = grupos.reduce(0) { $0 + $1.jogos.count }
        let vivos = grupos.first { $0.titulo == Eventos.grupos[0] }?.jogos.count ?? 0
        return "\(total) \(total == 1 ? "jogo" : "jogos") nos canais da lista · \(vivos) ao vivo"
    }
}

extension String {
    /// Escudos da agenda vêm do CDN do 365scores pedidos em 34 px (`w_34,h_34`)
    /// e em qualidade econômica: borrados. O CDN monta a imagem pelo endereço,
    /// então pedir 256 px e qualidade máxima traz o original (350 a 415 px);
    /// `c_limit` nunca amplia além dele.
    var emAltaResolucao: String {
        let marca = "imagecache.365scores.com/image/upload/"
        guard let faixa = range(of: marca) else { return self }
        let resto = self[faixa.upperBound...]
        let fim = resto.firstIndex(of: "/") ?? endIndex
        let ajustes = self[faixa.upperBound..<fim].split(separator: ",").map { p -> String in
            if p.hasPrefix("w_") { return "w_256" }
            if p.hasPrefix("h_") { return "h_256" }
            if p == "q_auto:eco" { return "q_auto:best" }
            return String(p)
        }
        return String(self[..<faixa.upperBound]) + ajustes.joined(separator: ",") + String(self[fim...])
    }
}
