import Foundation
import AVFoundation
import AppKit

/// As rádios: `vod/radios.txt` deste repositório, uma por linha,
/// `nome|endereço|logo` (o logo é opcional) — a mesma lista da TV Box.
///
/// Nunca fica vazia: a tela mostra na hora a última lista guardada em disco e
/// busca a do repositório por trás. Toca num player só dela, sem passar pelo
/// proxy nem pelo player do vídeo: rádio é áudio, e o ao vivo fica parado
/// enquanto ela toca (a aba de rádios é uma seção como as outras).
@MainActor
final class Radios: ObservableObject {
    static let shared = Radios()

    struct Radio: Identifiable, Hashable {
        let nome: String
        let url: String
        let logo: String?
        var id: String { nome }
    }

    /// Um estilo de rádio, achado pelo nome dela.
    struct Estilo: Identifiable, Hashable {
        let titulo: String
        let palavras: [String]
        var id: String { titulo }
    }

    /// A ordem conta: rádio que cabe em dois estilos fica no primeiro.
    static let estilos: [Estilo] = [
        Estilo(titulo: "Rock", palavras: ["rock", "metal", "kiss", "punk"]),
        Estilo(titulo: "Notícias e esporte", palavras: ["news", "noticia", "cbn", "gaucha", "itatiaia", "tupi",
                                                        "esporte", "jornal", "bandnews", "radio globo", "eldorado",
                                                        "bandeirantes"]),
        Estilo(titulo: "Gospel e católicas", palavras: ["gospel", "evangel", "catolic", "crista", "louvor", "aleluia",
                                                         "cancao nova", "novo tempo", "aparecida", "fe ", "deus",
                                                         "jesus", "igreja", "biblia"]),
        Estilo(titulo: "Pop e hits", palavras: ["pop", "hits", "dance", "mix", "jovem pan", "transamerica",
                                                 "energia", "eletro", "club", "pulse", "top"]),
        Estilo(titulo: "Sertanejo, MPB e samba", palavras: ["sertanej", "mpb", "samba", "pagode", "forro", "nativa",
                                                 "caipira", "brega", "axe", "piseiro", "moda de viola"]),
        Estilo(titulo: "Clássica e jazz", palavras: ["classic", "jazz", "cultura", "educativa", "universit",
                                                     "instrumental", "blues", "lounge"]),
    ]

    @Published private(set) var lista: [Radio] = []
    @Published private(set) var tocando: Radio?
    /// Som saindo de fato: carregando ou travada, as barras param.
    @Published private(set) var noAr = false
    @Published private(set) var falhou = false

    private let player = AVPlayer()
    private var observadores: [NSKeyValueObservation] = []
    private var observadorItem: NSKeyValueObservation?
    private var buscou = false

    private static let endereco = URL(
        string: Enderecos.canais + "radios.txt")!

    private static var arquivo: URL {
        let pasta = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("vod", isDirectory: true)
        try? FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        return pasta.appendingPathComponent("radios.txt")
    }

    private init() {
        player.automaticallyWaitsToMinimizeStalling = true
        observadores.append(player.observe(\.timeControlStatus, options: [.new]) { [weak self] p, _ in
            let tocandoAgora = p.timeControlStatus == .playing
            Task { @MainActor in self?.noAr = tocandoAgora }
        })
    }

    /// A lista em disco na hora; a do repositório por trás, uma vez por abertura.
    func carregar() async {
        if lista.isEmpty, let guardada = try? String(contentsOf: Self.arquivo, encoding: .utf8) {
            lista = Self.ler(guardada)
        }
        guard !buscou else { return }
        buscou = true
        var pedido = URLRequest(url: Self.endereco)
        pedido.timeoutInterval = 20
        guard let (dados, resposta) = try? await URLSession.shared.data(for: pedido),
              let http = resposta as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let texto = String(data: dados, encoding: .utf8) else { return }
        let nova = Self.ler(texto)
        // Página de erro ou arquivo pela metade não substitui a lista boa.
        guard nova.count >= 10 else { return }
        try? texto.write(to: Self.arquivo, atomically: true, encoding: .utf8)
        if nova != lista { lista = nova }
    }

    private static func ler(_ texto: String) -> [Radio] {
        var vistos = Set<String>()
        return texto.split(whereSeparator: \.isNewline).compactMap { linha in
            let partes = linha.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard partes.count >= 2, !partes[0].isEmpty, partes[1].hasPrefix("http"),
                  vistos.insert(partes[0]).inserted else { return nil }
            let logo = partes.count > 2 && partes[2].hasPrefix("http") ? partes[2] : nil
            return Radio(nome: partes[0], url: partes[1], logo: logo)
        }
    }

    // MARK: - Estilo e letra

    /// Nome sem acento e em minúsculas, para achar o estilo.
    static func chave(_ nome: String) -> String {
        nome.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
            .lowercased()
    }

    static func estilo(de radio: Radio) -> Estilo? {
        let nome = chave(radio.nome) + " "
        return estilos.first { e in e.palavras.contains { nome.contains($0) } }
    }

    /// A letra da fileira de A a Z; números e símbolos juntos, antes do A.
    static func letra(de radio: Radio) -> String {
        guard let primeira = chave(radio.nome).first, primeira.isLetter, primeira.isASCII else { return "#" }
        return String(primeira).uppercased()
    }

    // MARK: - Ouvidas por último

    private static let chaveRecentes = "radios.recentes"

    var recentes: [Radio] {
        let nomes = UserDefaults.standard.stringArray(forKey: Self.chaveRecentes) ?? []
        let porNome = Dictionary(lista.map { ($0.nome, $0) }, uniquingKeysWith: { a, _ in a })
        return nomes.compactMap { porNome[$0] }
    }

    private func ouviu(_ nome: String) {
        let nomes = UserDefaults.standard.stringArray(forKey: Self.chaveRecentes) ?? []
        UserDefaults.standard.set(Array(([nome] + nomes.filter { $0 != nome }).prefix(12)),
                                  forKey: Self.chaveRecentes)
    }

    // MARK: - Tocar

    func tocar(_ radio: Radio) {
        guard let url = URL(string: radio.url) else { return }
        // O vídeo não toca junto: um filme no ar pausa, o ao vivo já está
        // parado com a seção aberta.
        let model = PlayerModel.shared
        if model.playingFile != nil, model.isPlaying { model.togglePlayPause() }
        ouviu(radio.nome)
        objectWillChange.send()
        falhou = false
        tocando = radio
        let item = AVPlayerItem(url: url)
        observadorItem = item.observe(\.status, options: [.new]) { [weak self] it, _ in
            let deuErrado = it.status == .failed
            Task { @MainActor in
                if deuErrado { self?.falhou = true }
            }
        }
        player.replaceCurrentItem(with: item)
        player.volume = Float(model.volume)
        player.isMuted = model.isMuted
        player.play()
        Log.shared.write("rádio: \(radio.nome)")
    }

    func parar() {
        guard tocando != nil else { return }
        player.pause()
        player.replaceCurrentItem(with: nil)
        tocando = nil
        noAr = false
        falhou = false
    }

    func alternar() {
        if player.timeControlStatus == .paused, tocando != nil { player.play() } else { player.pause() }
    }

    var pausada: Bool { tocando != nil && player.timeControlStatus == .paused }
}
