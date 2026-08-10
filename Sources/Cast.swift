import Foundation
import Network
import Combine

/// A Google Cast receiver on the local network: Chromecast, Google TV boxes
/// (Xiaomi Mi Box, TV Stick), Android TVs, Nest speakers with a display.
struct CastDevice: Identifiable, Hashable {
    let id: String
    var name: String
    var model: String
    let endpoint: NWEndpoint

    var label: String { model.isEmpty ? name : "\(name) · \(model)" }
}

/// Discovery and playback control for Google Cast.
///
/// AirPlay and Cast are unrelated protocols — the system AirPlay picker will
/// never list a Google TV box — so this speaks CASTV2 directly: Bonjour to find
/// receivers, then a TLS socket on port 8009 carrying length-prefixed protobuf
/// frames whose payloads are JSON.
@MainActor
final class CastService: ObservableObject {
    static let shared = CastService()

    @Published private(set) var devices: [CastDevice] = []
    @Published private(set) var connected: CastDevice?
    @Published private(set) var status: String = ""

    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var buffer = Data()
    private var requestID = 1
    private var sessionTransport: String?
    private var heartbeat: Timer?
    private var pendingMedia: (url: URL, title: String)?

    private let senderID = "sender-saimo"
    private let receiverID = "receiver-0"
    private let defaultReceiverApp = "CC1AD845"

    private enum Namespace {
        static let connection = "urn:x-cast:com.google.cast.tp.connection"
        static let heartbeat = "urn:x-cast:com.google.cast.tp.heartbeat"
        static let receiver = "urn:x-cast:com.google.cast.receiver"
        static let media = "urn:x-cast:com.google.cast.media"
    }

    private init() {}

    // MARK: - Discovery

    func startDiscovery() {
        guard browser == nil else { return }
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        let browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: "_googlecast._tcp", domain: nil),
            using: parameters)

        browser.browseResultsChangedHandler = { results, _ in
            Task { @MainActor in
                CastService.shared.devices = results.compactMap(CastService.device(from:))
                    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            }
        }
        browser.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                Task { @MainActor in
                    Log.shared.write("busca de Cast falhou: \(error)")
                    CastService.shared.browser = nil
                }
            }
        }
        self.browser = browser
        browser.start(queue: .main)
    }

    func stopDiscovery() {
        browser?.cancel()
        browser = nil
    }

    /// The friendly name and model live in the Bonjour TXT record (`fn`, `md`).
    private static func device(from result: NWBrowser.Result) -> CastDevice? {
        guard case .service(let name, _, _, _) = result.endpoint else { return nil }
        var friendly = name
        var model = ""
        if case .bonjour(let txt) = result.metadata {
            if let value = txt["fn"], !value.isEmpty { friendly = value }
            if let value = txt["md"], !value.isEmpty { model = value }
        }
        return CastDevice(id: name, name: friendly, model: model, endpoint: result.endpoint)
    }

    // MARK: - Casting

    func cast(url: URL, title: String, to device: CastDevice) {
        disconnect()
        pendingMedia = (url, title)
        status = "conectando a \(device.name)…"
        Log.shared.write("Cast: conectando a \(device.label)")

        let tls = NWProtocolTLS.Options()
        // Receivers present a self-signed certificate; the payload is a public
        // LAN stream, so accepting it is the intended behaviour here.
        sec_protocol_options_set_verify_block(
            tls.securityProtocolOptions,
            { _, _, complete in complete(true) },
            DispatchQueue.global(qos: .userInitiated))

        let connection = NWConnection(
            to: device.endpoint,
            using: NWParameters(tls: tls, tcp: NWProtocolTCP.Options()))
        self.connection = connection
        self.connected = device

        connection.stateUpdateHandler = { state in
            Task { @MainActor in
                switch state {
                case .ready: CastService.shared.handshake()
                case .failed(let error):
                    CastService.shared.status = "falhou: \(error.localizedDescription)"
                    Log.shared.write("Cast falhou: \(error)")
                    CastService.shared.disconnect()
                case .cancelled:
                    CastService.shared.status = ""
                default: break
                }
            }
        }
        connection.start(queue: .global(qos: .userInitiated))
        receiveLoop()
    }

    func disconnect() {
        heartbeat?.invalidate(); heartbeat = nil
        connection?.cancel()
        connection = nil
        connected = nil
        sessionTransport = nil
        pendingMedia = nil
        buffer.removeAll()
    }

    private func handshake() {
        send(namespace: Namespace.connection, to: receiverID, payload: ["type": "CONNECT"])
        send(namespace: Namespace.receiver, to: receiverID,
             payload: ["type": "LAUNCH", "appId": defaultReceiverApp, "requestId": nextRequest()])

        heartbeat = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            Task { @MainActor in
                CastService.shared.send(namespace: Namespace.heartbeat,
                                        to: CastService.shared.receiverID,
                                        payload: ["type": "PING"])
            }
        }
    }

    private func nextRequest() -> Int {
        requestID += 1
        return requestID
    }

    private func loadMedia(on transport: String) {
        guard let media = pendingMedia else { return }
        send(namespace: Namespace.connection, to: transport, payload: ["type": "CONNECT"])
        send(namespace: Namespace.media, to: transport, payload: [
            "type": "LOAD",
            "requestId": nextRequest(),
            "autoplay": true,
            "media": [
                "contentId": media.url.absoluteString,
                "contentType": "application/vnd.apple.mpegurl",
                "streamType": "LIVE",
                "metadata": [
                    "metadataType": 0,
                    "title": media.title,
                ],
            ],
        ])
        status = "transmitindo \(media.title)"
        Log.shared.write("Cast: enviado \(media.title)")
    }

    // MARK: - Framing

    private func send(namespace: String, to destination: String, payload: [String: Any]) {
        guard let connection,
              let json = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: json, encoding: .utf8) else { return }

        var message = Data()
        message.append(contentsOf: [0x08, 0x00])                       // protocol_version = 0
        message.append(field(2, senderID))                             // source_id
        message.append(field(3, destination))                          // destination_id
        message.append(field(4, namespace))                            // namespace
        message.append(contentsOf: [0x28, 0x00])                       // payload_type = STRING
        message.append(field(6, text))                                 // payload_utf8

        var frame = Data()
        var length = UInt32(message.count).bigEndian
        withUnsafeBytes(of: &length) { frame.append(contentsOf: $0) }
        frame.append(message)
        connection.send(content: frame, completion: .contentProcessed { _ in })
    }

    /// Length-delimited protobuf field.
    private func field(_ number: Int, _ value: String) -> Data {
        var out = Data([UInt8((number << 3) | 2)])
        let bytes = Data(value.utf8)
        out.append(varint(bytes.count))
        out.append(bytes)
        return out
    }

    private func varint(_ value: Int) -> Data {
        var v = value
        var out = Data()
        repeat {
            var byte = UInt8(v & 0x7F)
            v >>= 7
            if v != 0 { byte |= 0x80 }
            out.append(byte)
        } while v != 0
        return out
    }

    private func receiveLoop() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { data, _, isComplete, error in
            if let data, !data.isEmpty {
                Task { @MainActor in CastService.shared.consume(data) }
            }
            if error != nil || isComplete {
                Task { @MainActor in CastService.shared.disconnect() }
                return
            }
            Task { @MainActor in CastService.shared.receiveLoop() }
        }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        // Data keeps its original index base after removeFirst, so every offset
        // is taken from startIndex and the remainder is re-based explicitly.
        // Indexing from zero crashed the moment a second frame arrived.
        while buffer.count >= 4 {
            let base = buffer.startIndex
            let length = (0..<4).reduce(0) { $0 << 8 | Int(buffer[base + $1]) }
            guard length > 0, length < 8 << 20 else { buffer.removeAll(); return }
            guard buffer.count >= 4 + length else { return }

            let start = base + 4
            let message = Data(buffer[start..<(start + length)])
            buffer = Data(buffer[(start + length)...])
            handle(message)
        }
    }

    /// Only three things matter coming back: the receiver's heartbeat, which
    /// must be answered or it drops the connection and playback stops; the
    /// receiver status, which carries the session to load media into; and media
    /// status, which is where failures surface.
    private func handle(_ message: Data) {
        var index = message.startIndex
        var namespace = ""
        var payload = ""

        while index < message.endIndex {
            let key = Int(message[index]); index += 1
            let number = key >> 3, wire = key & 7
            switch wire {
            case 0:
                while index < message.endIndex, message[index] & 0x80 != 0 { index += 1 }
                if index < message.endIndex { index += 1 }
            case 2:
                var length = 0, shift = 0
                while index < message.endIndex {
                    let byte = message[index]; index += 1
                    length |= Int(byte & 0x7F) << shift
                    if byte & 0x80 == 0 { break }
                    shift += 7
                }
                let end = min(index + length, message.endIndex)
                let text = String(decoding: message[index..<end], as: UTF8.self)
                if number == 4 { namespace = text }
                if number == 6 { payload = text }
                index = end
            default:
                return
            }
        }

        // Answering the receiver's PING is what keeps the session alive.
        if namespace == Namespace.heartbeat, payload.contains("\"PING\"") {
            send(namespace: Namespace.heartbeat, to: receiverID, payload: ["type": "PONG"])
            return
        }

        guard let data = payload.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        if namespace == Namespace.media {
            let type = root["type"] as? String ?? ""
            if type.hasSuffix("_ERROR") || type.contains("FAILED") {
                let reason = root["reason"] as? String ?? type
                status = "o aparelho recusou: \(reason)"
                Log.shared.write("Cast recusado: \(payload.prefix(200))")
            } else if let first = (root["status"] as? [[String: Any]])?.first,
                      let state = first["playerState"] as? String {
                status = state == "PLAYING" ? "transmitindo" : "no aparelho: \(state.lowercased())"
            }
            return
        }

        guard namespace == Namespace.receiver,
              root["type"] as? String == "RECEIVER_STATUS",
              let statusBlock = root["status"] as? [String: Any],
              let apps = statusBlock["applications"] as? [[String: Any]],
              let transport = apps.first?["transportId"] as? String
        else { return }

        guard sessionTransport != transport else { return }
        sessionTransport = transport
        loadMedia(on: transport)
    }
}
