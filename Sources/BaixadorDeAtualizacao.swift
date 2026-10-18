import Foundation
import CryptoKit

/// Baixa o DMG da versão nova por trás, enquanto o app segue tocando.
///
/// Uma conexão só, sem limite de velocidade: a CDN do GitHub entrega os 25 MB
/// em segundos, e várias conexões em pedaços só trariam mais jeitos de falhar.
/// O que importa é chegar inteiro:
///
/// - grava num `.part` e só vira `.dmg` depois de conferido, com uma troca de
///   nome — um arquivo pela metade nunca passa por pronto;
/// - caiu no meio, retoma de onde parou (cabeçalho Range), inclusive numa
///   abertura seguinte do app; tenta de novo algumas vezes, esperando mais a
///   cada vez;
/// - no fim confere o tamanho e o SHA-256 que o GitHub anuncia para o arquivo,
///   e o rodapé "koly" que todo DMG tem nos últimos 512 bytes. Não bateu,
///   apaga e baixa de novo — é o que pega um `.part` de um DMG que foi trocado
///   no mesmo release, que de outro modo seria emendado com o novo.
///
/// Tudo aqui roda na fila serial do delegate; o app só ouve o progresso e o fim.
final class BaixadorDeAtualizacao: NSObject, URLSessionDataDelegate, @unchecked Sendable {

    private let origem: URL
    private let parcial: URL
    private let destino: URL
    /// Tamanho anunciado pelo GitHub; sem ele, vale o que o servidor disser.
    private var esperado: Int64?
    /// SHA-256 anunciado pelo GitHub, em hexadecimal; sem ele, tamanho e rodapé.
    private let resumo: String?
    private let aoAvancar: @Sendable (Double) -> Void
    private let aoTerminar: @Sendable (URL?) -> Void

    private let fila: OperationQueue = {
        let fila = OperationQueue()
        fila.maxConcurrentOperationCount = 1
        fila.name = "dev.saimo.player.atualizacao"
        return fila
    }()
    private var sessao: URLSession?
    private var arquivo: FileHandle?
    private var recebido: Int64 = 0
    private var respostaBoa = false
    private var ultimoAviso: Double = -1
    private var tentativa = 0
    private let tentativas = 6
    private var acabou = false

    init(origem: URL, destino: URL, tamanho: Int64?, sha256: String?,
         aoAvancar: @escaping @Sendable (Double) -> Void,
         aoTerminar: @escaping @Sendable (URL?) -> Void) {
        self.origem = origem
        self.destino = destino
        self.parcial = destino.appendingPathExtension("part")
        self.esperado = tamanho
        self.resumo = sha256?.lowercased()
        self.aoAvancar = aoAvancar
        self.aoTerminar = aoTerminar
        super.init()
    }

    func comecar() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.waitsForConnectivity = true
        sessao = URLSession(configuration: config, delegate: self, delegateQueue: fila)
        fila.addOperation { self.pedir() }
    }

    func cancelar() {
        fila.addOperation {
            self.acabou = true
            try? self.arquivo?.close()
            self.arquivo = nil
            self.sessao?.invalidateAndCancel()
            self.sessao = nil
        }
    }

    /// Já baixado e conferido numa vez anterior.
    static func pronto(_ arquivo: URL, tamanho: Int64?, sha256: String?) -> Bool {
        guard let real = tamanhoDe(arquivo), real > 0 else { return false }
        if let tamanho, real != tamanho { return false }
        guard temRodapeDeDMG(arquivo) else { return false }
        if let sha256 { return resumoDe(arquivo) == sha256.lowercased() }
        return true
    }

    // MARK: - Pedido

    private func pedir() {
        guard !acabou, let sessao else { return }
        let gerente = FileManager.default
        if !gerente.fileExists(atPath: parcial.path) {
            gerente.createFile(atPath: parcial.path, contents: nil)
        }
        recebido = Self.tamanhoDe(parcial) ?? 0
        if let esperado, recebido > esperado { zerar() }
        if let esperado, recebido == esperado { concluir(); return }

        var pedido = URLRequest(url: origem)
        pedido.setValue(Upstream.userAgent, forHTTPHeaderField: "User-Agent")
        pedido.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        if recebido > 0 { pedido.setValue("bytes=\(recebido)-", forHTTPHeaderField: "Range") }
        respostaBoa = false
        sessao.dataTask(with: pedido).resume()
    }

    /// O endereço do GitHub redireciona para a CDN com um link assinado; o
    /// Range precisa ir junto no pedido novo.
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        // Só segue para a CDN do GitHub; qualquer outro destino é recusado.
        guard let destino = request.url, VersaoPublicada.redirecionamentoPermitido(destino) else {
            completionHandler(nil); return
        }
        var novo = request
        if recebido > 0 { novo.setValue("bytes=\(recebido)-", forHTTPHeaderField: "Range") }
        completionHandler(novo)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse else {
            completionHandler(.cancel); return
        }
        switch http.statusCode {
        case 206:
            // Confere que o servidor retomou exatamente de onde se pediu.
            let faixa = http.value(forHTTPHeaderField: "Content-Range") ?? ""
            guard Self.inicio(faixa) == recebido else {
                zerar(); completionHandler(.cancel); return
            }
            if let total = Self.total(faixa) { esperado = esperado ?? total }
        case 200:
            // Sem retomada: começa do zero, que é o que chegou.
            zerar()
            if esperado == nil, http.expectedContentLength > 0 { esperado = http.expectedContentLength }
        case 416:
            // Pediu além do fim: ou já está tudo aqui, ou o arquivo é outro.
            completionHandler(.cancel)
            if let esperado, recebido == esperado { respostaBoa = true } else { zerar() }
            return
        default:
            completionHandler(.cancel); return
        }
        do {
            let escrita = try FileHandle(forWritingTo: parcial)
            try escrita.seekToEnd()
            arquivo = escrita
            respostaBoa = true
            completionHandler(.allow)
        } catch {
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let arquivo else { return }
        do {
            try arquivo.write(contentsOf: data)
        } catch {
            respostaBoa = false
            dataTask.cancel()
            return
        }
        recebido += Int64(data.count)
        if let esperado, esperado > 0 {
            let fracao = min(Double(recebido) / Double(esperado), 1)
            // Meio por cento de cada vez: o bastante para a barra andar lisa.
            if fracao - ultimoAviso >= 0.005 || fracao >= 1 {
                ultimoAviso = fracao
                aoAvancar(fracao)
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        try? arquivo?.synchronize()
        try? arquivo?.close()
        arquivo = nil
        guard !acabou else { return }
        if error == nil, respostaBoa, esperado == nil || recebido == esperado {
            concluir()
        } else {
            tentarDeNovo()
        }
    }

    // MARK: - Fim

    private func concluir() {
        guard Self.pronto(parcial, tamanho: esperado, sha256: resumo) else {
            // Tamanho certo e conteúdo errado (ou o contrário): de novo, do zero.
            zerar()
            tentarDeNovo()
            return
        }
        let gerente = FileManager.default
        try? gerente.removeItem(at: destino)
        do {
            try gerente.moveItem(at: parcial, to: destino)
        } catch {
            tentarDeNovo()
            return
        }
        terminar(destino)
    }

    private func tentarDeNovo() {
        tentativa += 1
        guard tentativa < tentativas else { terminar(nil); return }
        // 1, 2, 4, 8, 16 segundos: rede que caiu costuma voltar nesse intervalo.
        let espera = pow(2, Double(tentativa - 1))
        DispatchQueue.global().asyncAfter(deadline: .now() + espera) {
            self.fila.addOperation { self.pedir() }
        }
    }

    private func terminar(_ arquivo: URL?) {
        guard !acabou else { return }
        acabou = true
        sessao?.finishTasksAndInvalidate()
        sessao = nil
        aoTerminar(arquivo)
    }

    private func zerar() {
        try? arquivo?.close()
        arquivo = nil
        try? Data().write(to: parcial)
        recebido = 0
        ultimoAviso = -1
    }

    // MARK: - Peças

    private static func tamanhoDe(_ arquivo: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: arquivo.path)[.size] as? NSNumber)?.int64Value
    }

    /// SHA-256 do arquivo, lido em blocos de 1 MB para não pôr tudo na memória.
    private static func resumoDe(_ arquivo: URL) -> String? {
        guard let leitura = try? FileHandle(forReadingFrom: arquivo) else { return nil }
        defer { try? leitura.close() }
        var conta = SHA256()
        while let bloco = try? leitura.read(upToCount: 1 << 20), !bloco.isEmpty {
            conta.update(data: bloco)
        }
        return conta.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Todo DMG termina num bloco de 512 bytes que começa com "koly".
    private static func temRodapeDeDMG(_ arquivo: URL) -> Bool {
        guard let leitura = try? FileHandle(forReadingFrom: arquivo) else { return false }
        defer { try? leitura.close() }
        guard let fim = try? leitura.seekToEnd(), fim >= 512 else { return false }
        try? leitura.seek(toOffset: fim - 512)
        guard let bloco = try? leitura.read(upToCount: 4) else { return false }
        return bloco == Data("koly".utf8)
    }

    /// "bytes 1000-1999/25328310" → 1000.
    private static func inicio(_ faixa: String) -> Int64? {
        guard let resto = faixa.split(separator: " ").last,
              let primeiro = resto.split(separator: "-").first else { return nil }
        return Int64(primeiro)
    }

    /// "bytes 1000-1999/25328310" → 25328310.
    private static func total(_ faixa: String) -> Int64? {
        faixa.split(separator: "/").last.flatMap { Int64($0) }
    }
}
