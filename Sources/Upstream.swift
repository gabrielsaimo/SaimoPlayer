import Foundation
import Network

struct UpstreamResponse {
    var status: Int
    var headers: [String: String]
    var body: Data
    var finalURL: URL

    var contentType: String { headers["content-type"] ?? "" }
}

enum UpstreamError: Error, CustomStringConvertible {
    case badURL
    case transport(String)
    case tooManyRedirects

    var description: String {
        switch self {
        case .badURL: return "URL inválida"
        case .transport(let m): return m
        case .tooManyRedirects: return "redirects demais"
        }
    }
}

/// Fetches upstream resources.
///
/// Fast path is URLSession. When the system resolver refuses to resolve a host
/// (blocked / filtered DNS, error -1003), it falls back to resolving over
/// DNS-over-HTTPS and speaking HTTP/1.1 directly on an NWConnection with the
/// original hostname pinned as the TLS SNI.
final class Upstream {
    static let shared = Upstream()

    static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 " +
        "(KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    private let session: URLSession
    private var dnsCache: [String: [String]] = [:]
    private let lock = NSLock()

    private init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 40
        cfg.httpAdditionalHeaders = [
            "User-Agent": Upstream.userAgent,
            "Accept": "*/*",
            "Accept-Encoding": "identity",
        ]
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: cfg)
    }

    func fetch(_ url: URL, method: String = "GET", referer: String? = nil) throws -> UpstreamResponse {
        do {
            return try fetchViaURLSession(url, method: method, referer: referer)
        } catch let e as NSError where e.domain == NSURLErrorDomain
            && (e.code == NSURLErrorCannotFindHost || e.code == NSURLErrorDNSLookupFailed) {
            Log.shared.write("DNS do sistema bloqueou \(url.host ?? "?") — usando DoH")
            return try fetchViaRawTLS(url, method: method, referer: referer, redirectsLeft: 4)
        }
    }

    // MARK: - URLSession path

    private func fetchViaURLSession(_ url: URL, method: String, referer: String?) throws -> UpstreamResponse {
        var req = URLRequest(url: url)
        req.httpMethod = method
        if let referer { req.setValue(referer, forHTTPHeaderField: "Referer") }

        let sem = DispatchSemaphore(value: 0)
        var result: Result<UpstreamResponse, Error>!
        let task = session.dataTask(with: req) { data, response, error in
            defer { sem.signal() }
            if let error {
                result = .failure(error)
                return
            }
            guard let http = response as? HTTPURLResponse else {
                result = .failure(UpstreamError.transport("resposta não-HTTP"))
                return
            }
            var headers: [String: String] = [:]
            for (k, v) in http.allHeaderFields {
                headers[String(describing: k).lowercased()] = String(describing: v)
            }
            result = .success(UpstreamResponse(
                status: http.statusCode,
                headers: headers,
                body: data ?? Data(),
                finalURL: http.url ?? url))
        }
        task.resume()
        _ = sem.wait(timeout: .now() + 45)
        guard let result else { throw UpstreamError.transport("timeout") }
        return try result.get()
    }

    // MARK: - DoH + raw TLS path

    private func resolve(_ host: String) throws -> [String] {
        lock.lock()
        if let cached = dnsCache[host] { lock.unlock(); return cached }
        lock.unlock()

        var ips: [String] = []
        for resolver in ["https://1.1.1.1/dns-query", "https://8.8.8.8/resolve"] {
            guard var comps = URLComponents(string: resolver) else { continue }
            comps.queryItems = [
                URLQueryItem(name: "name", value: host),
                URLQueryItem(name: "type", value: "A"),
            ]
            guard let u = comps.url else { continue }
            var req = URLRequest(url: u)
            req.setValue("application/dns-json", forHTTPHeaderField: "Accept")

            let sem = DispatchSemaphore(value: 0)
            var payload: Data?
            session.dataTask(with: req) { d, _, _ in payload = d; sem.signal() }.resume()
            _ = sem.wait(timeout: .now() + 12)

            guard let payload,
                  let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
                  let answers = json["Answer"] as? [[String: Any]] else { continue }
            for a in answers where (a["type"] as? Int) == 1 {
                if let ip = a["data"] as? String { ips.append(ip) }
            }
            if !ips.isEmpty { break }
        }
        guard !ips.isEmpty else {
            throw UpstreamError.transport("DoH não resolveu \(host)")
        }
        lock.lock(); dnsCache[host] = ips; lock.unlock()
        return ips
    }

    private func fetchViaRawTLS(_ url: URL, method: String, referer: String?, redirectsLeft: Int) throws -> UpstreamResponse {
        guard redirectsLeft > 0 else { throw UpstreamError.tooManyRedirects }
        guard let host = url.host, let scheme = url.scheme else { throw UpstreamError.badURL }
        let port = UInt16(url.port ?? (scheme == "https" ? 443 : 80))
        let ips = try resolve(host)

        var lastError: Error = UpstreamError.transport("sem endpoint")
        for ip in ips.prefix(3) {
            do {
                let raw = try rawRequest(ip: ip, port: port, tls: scheme == "https",
                                         host: host, url: url, method: method, referer: referer)
                if (300...399).contains(raw.status), let loc = raw.headers["location"],
                   let next = URL(string: loc, relativeTo: url)?.absoluteURL {
                    return try fetchViaRawTLS(next, method: method, referer: referer, redirectsLeft: redirectsLeft - 1)
                }
                return raw
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func rawRequest(ip: String, port: UInt16, tls: Bool, host: String,
                            url: URL, method: String, referer: String?) throws -> UpstreamResponse {
        var path = url.path.isEmpty ? "/" : url.path
        if let q = url.query, !q.isEmpty { path += "?" + q }

        var head = "\(method) \(path) HTTP/1.1\r\n"
        head += "Host: \(host)\r\n"
        head += "User-Agent: \(Upstream.userAgent)\r\n"
        head += "Accept: */*\r\n"
        head += "Accept-Encoding: identity\r\n"
        if let referer { head += "Referer: \(referer)\r\n" }
        head += "Connection: close\r\n\r\n"

        let params: NWParameters
        if tls {
            let tlsOpts = NWProtocolTLS.Options()
            sec_protocol_options_set_tls_server_name(tlsOpts.securityProtocolOptions, host)
            params = NWParameters(tls: tlsOpts, tcp: NWProtocolTCP.Options())
        } else {
            params = NWParameters(tls: nil, tcp: NWProtocolTCP.Options())
        }

        let conn = NWConnection(
            host: NWEndpoint.Host(ip),
            port: NWEndpoint.Port(rawValue: port)!,
            using: params)

        let sem = DispatchSemaphore(value: 0)
        var buffer = Data()
        var failure: Error?
        var done = false
        let finish = { (err: Error?) in
            if done { return }
            done = true
            failure = err
            sem.signal()
        }

        func receiveLoop() {
            conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { data, _, isComplete, error in
                if let data, !data.isEmpty { buffer.append(data) }
                if let error { finish(error); return }
                if isComplete { finish(nil); return }
                receiveLoop()
            }
        }

        conn.stateUpdateHandler = { state in
            switch state {
            case .ready:
                conn.send(content: Data(head.utf8), completion: .contentProcessed { err in
                    if let err { finish(err) }
                })
                receiveLoop()
            case .failed(let err):
                finish(err)
            case .cancelled:
                finish(UpstreamError.transport("conexão cancelada"))
            default:
                break
            }
        }
        conn.start(queue: .global(qos: .userInitiated))
        let waited = sem.wait(timeout: .now() + 25)
        conn.cancel()
        if waited == .timedOut { throw UpstreamError.transport("timeout em \(host)") }
        if let failure, buffer.isEmpty { throw failure }

        return try parseHTTP(buffer, finalURL: url)
    }

    private func parseHTTP(_ raw: Data, finalURL: URL) throws -> UpstreamResponse {
        guard let sep = raw.range(of: Data("\r\n\r\n".utf8)) else {
            throw UpstreamError.transport("resposta HTTP truncada")
        }
        let headText = String(decoding: raw[raw.startIndex..<sep.lowerBound], as: UTF8.self)
        var body = raw[sep.upperBound...]

        var lines = headText.components(separatedBy: "\r\n")
        let statusLine = lines.removeFirst()
        let status = Int(statusLine.split(separator: " ").dropFirst().first.map(String.init) ?? "") ?? 0

        var headers: [String: String] = [:]
        for l in lines {
            guard let colon = l.firstIndex(of: ":") else { continue }
            let k = l[l.startIndex..<colon].lowercased()
            let v = l[l.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[k] = v
        }

        if headers["transfer-encoding"]?.lowercased().contains("chunked") == true {
            body = Self.dechunk(Data(body))[...]
        } else if let len = headers["content-length"].flatMap(Int.init), body.count > len {
            body = body.prefix(len)
        }

        return UpstreamResponse(status: status, headers: headers,
                                body: Data(body), finalURL: finalURL)
    }

    private static func dechunk(_ data: Data) -> Data {
        var out = Data()
        var i = data.startIndex
        while i < data.endIndex {
            guard let crlf = data[i...].range(of: Data("\r\n".utf8)) else { break }
            let sizeStr = String(decoding: data[i..<crlf.lowerBound], as: UTF8.self)
                .split(separator: ";").first.map(String.init) ?? ""
            guard let size = Int(sizeStr.trimmingCharacters(in: .whitespaces), radix: 16), size > 0 else { break }
            let start = crlf.upperBound
            let end = data.index(start, offsetBy: size, limitedBy: data.endIndex) ?? data.endIndex
            out.append(data[start..<end])
            i = data.index(end, offsetBy: 2, limitedBy: data.endIndex) ?? data.endIndex
        }
        return out
    }
}
