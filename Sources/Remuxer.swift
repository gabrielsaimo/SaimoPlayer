import Foundation

/// AVFoundation decodes HEVC only inside fMP4 — HEVC carried in MPEG-TS plays
/// as audio over a black picture. For those streams ffmpeg is used to repackage
/// (stream copy, no re-encode) the live TS into fMP4 HLS on disk, which the
/// proxy then serves in place of the upstream playlist.
final class Remuxer {
    static let shared = Remuxer()

    private final class Session {
        let dir: URL
        let process: Process
        /// Which source this session was started for; a change restarts it.
        let variant: Variant
        var lastAccess = Date()
        init(dir: URL, process: Process, variant: Variant) {
            self.dir = dir
            self.process = process
            self.variant = variant
        }
    }

    private var sessions: [UUID: Session] = [:]
    private let lock = NSLock()
    private var reaper: Timer?

    private init() {
        DispatchQueue.main.async { [weak self] in
            self?.reaper = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { _ in
                Remuxer.shared.reapIdle()
            }
        }
    }

    /// The copy shipped inside the bundle wins, so the app keeps working on a
    /// machine without Homebrew.
    static let ffmpegPath: String? = tool("ffmpeg")
    static let ffprobePath: String? = tool("ffprobe")

    private static func tool(_ name: String) -> String? {
        var candidates: [String] = []
        if let bundled = Bundle.main.url(forResource: name, withExtension: nil) {
            candidates.append(bundled.path)
        }
        candidates += ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "/usr/bin/\(name)"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private var probeCache: [URL: (audioCount: Int, isHEVC: Bool)] = [:]

    private func probe(for variant: Variant, input: URL) -> (audioCount: Int, isHEVC: Bool) {
        lock.lock()
        if let cached = probeCache[variant.url] { lock.unlock(); return cached }
        lock.unlock()

        var count = 1
        var isHEVC = false
        if let ffprobe = Remuxer.ffprobePath {
            // Estes CDNs entregam o segmento com extensão de disfarce (.pdf,
            // .png). O ffmpeg recusa o que não reconhece, então a lista fica
            // aberta: o que manda é o conteúdo, não o nome do arquivo.
            //
            // "-extension_picky" só existe na classe de opções do demuxer HLS;
            // passada antes de "-i" ela é aplicada cedo demais para o ffmpeg
            // saber que a entrada vai ser DASH, e ele recusa a opção com
            // "Option not found" — derrubando o canal inteiro antes de tentar
            // ler qualquer coisa. Por isso só entra quando não é DASH.
            var args = ["-v", "error", "-show_programs", "-show_streams", "-of", "json",
                        "-allowed_extensions", "ALL"]
            if !variant.isDASH { args += ["-extension_picky", "0"] }
            if let ua = variant.userAgent { args += ["-user_agent", ua] }
            if let ref = variant.referer { args += ["-referer", ref] }
            if variant.isDASH, let key = variant.clearKey, !key.isEmpty {
                args += ["-cenc_decryption_key", key]
            }
            args += ["-i", input.absoluteString]

            let process = Process()
            process.executableURL = URL(fileURLWithPath: ffprobe)
            process.arguments = args
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            if (try? process.run()) != nil {
                DispatchQueue.global().asyncAfter(deadline: .now() + 10) {
                    if process.isRunning { process.terminate() }
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                
                if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let programs = root["programs"] as? [[String: Any]], !programs.isEmpty {
                        let perProgram = programs.map { program -> Int in
                            let streams = program["streams"] as? [[String: Any]] ?? []
                            if let video = streams.first(where: { $0["codec_type"] as? String == "video" }),
                               let codec = video["codec_name"] as? String, codec.lowercased() == "hevc" {
                                isHEVC = true
                            }
                            return streams.filter { $0["codec_type"] as? String == "audio" }.count
                        }
                        count = max(1, perProgram.max() ?? 1)
                    } else {
                        let streams = root["streams"] as? [[String: Any]] ?? []
                        if let video = streams.first(where: { $0["codec_type"] as? String == "video" }),
                           let codec = video["codec_name"] as? String, codec.lowercased() == "hevc" {
                            isHEVC = true
                        }
                        count = max(1, streams.filter { $0["codec_type"] as? String == "audio" }.count)
                    }
                }
            }
        }
        lock.lock(); probeCache[variant.url] = (count, isHEVC); lock.unlock()
        if count > 1 { Log.shared.write("remux: \(count) faixas de áudio") }
        if isHEVC { Log.shared.write("remux: vídeo é HEVC") }
        return (count, isHEVC)
    }

    var isAvailable: Bool { Remuxer.ffmpegPath != nil }

    /// Returns the rewritten local playlist, or nil when the session is not
    /// ready yet or ffmpeg is unavailable.
    func playlist(for channel: Channel, variant: Variant,
                  sourceURL: URL, rewriteBase: String) -> String? {
        guard let session = ensureSession(channel: channel, variant: variant,
                                          sourceURL: sourceURL) else { return nil }

        // A multi-audio session publishes a master listing each rendition; a
        // single-audio one publishes the media playlist directly.
        let master = session.dir.appendingPathComponent("master.m3u8")
        let index = session.dir.appendingPathComponent("index.m3u8")
        let deadline = Date().addingTimeInterval(25)
        while Date() < deadline {
            if let text = try? String(contentsOf: master, encoding: .utf8),
               text.contains("#EXT-X-STREAM-INF") {
                return rewrite(text, base: rewriteBase)
            }
            if let text = try? String(contentsOf: index, encoding: .utf8),
               text.contains("#EXTINF") {
                return rewrite(text, base: rewriteBase)
            }
            if !session.process.isRunning { return nil }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return nil
    }

    /// Serves a file from the session directory. Sub-paths are allowed because
    /// multi-audio sessions write into `stream_N/`, but the resolved path must
    /// stay inside the session directory.
    func file(for channelID: UUID, named name: String) -> URL? {
        lock.lock()
        let session = sessions[channelID]
        session?.lastAccess = Date()
        lock.unlock()
        guard let session, !name.isEmpty else { return nil }
        guard !name.split(separator: "/").contains("..") else { return nil }

        let url = session.dir.appendingPathComponent(name).standardizedFileURL
        let root = session.dir.standardizedFileURL.path
        guard url.path.hasPrefix(root),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    // MARK: - Session lifecycle

    private func ensureSession(channel: Channel, variant: Variant, sourceURL: URL) -> Session? {
        let channelID = channel.id
        lock.lock()
        if let existing = sessions[channelID], existing.process.isRunning,
           existing.variant == variant {
            existing.lastAccess = Date()
            lock.unlock()
            return existing
        }
        sessions[channelID]?.process.terminate()
        sessions.removeValue(forKey: channelID)
        lock.unlock()

        guard let ffmpeg = Remuxer.ffmpegPath else {
            Log.shared.write("ffmpeg não encontrado — HEVC ficará sem imagem")
            return nil
        }

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("saimo-remux/\(channelID.uuidString)", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Mesma ressalva do probe: "-extension_picky" derruba a leitura de um
        // canal DASH com "Option not found" antes mesmo de abrir o manifesto.
        var args = ["-hide_banner", "-loglevel", "error", "-fflags", "+genpts",
                    "-allowed_extensions", "ALL"]
        if !variant.isDASH { args += ["-extension_picky", "0"] }
        if let ua = variant.userAgent { args += ["-user_agent", ua] }
        if let ref = variant.referer { args += ["-referer", ref] }
        // CENC ClearKey — only the DASH demuxer understands this option;
        // -decryption_key belongs to the mov demuxer and breaks manifest reads.
        if variant.isDASH, let key = variant.clearKey, !key.isEmpty {
            args += ["-cenc_decryption_key", key]
        }
        let probeResult = probe(for: variant, input: sourceURL)

        args += [
            "-i", sourceURL.absoluteString,
            "-map", "0:v:0",
        ]
        // Every audio track is carried through: dropping all but the first is
        // what loses the second language on dual-audio channels.
        args += probeResult.audioCount > 1 ? ["-map", "0:a"] : ["-map", "0:a:0"]
        args += ["-c", "copy"]
        if probeResult.isHEVC {
            args += ["-tag:v", "hvc1"]
        }
        // ADTS only exists in MPEG-TS input; the filter errors out on fMP4/DASH.
        if !variant.isDASH { args += ["-bsf:a", "aac_adtstoasc"] }

        args += [
            "-f", "hls",
            "-hls_time", "4",
            "-hls_list_size", "8",
            "-hls_flags", "delete_segments+append_list+omit_endlist+independent_segments",
            "-hls_segment_type", "fmp4",
            "-hls_fmp4_init_filename", "init.mp4",
        ]

        if probeResult.audioCount > 1 {
            // Separate renditions in one audio group, which is what makes
            // AVFoundation show a switchable audio menu.
            // No `name:` here on purpose — it would rename the output folders
            // to stream_<name>, and the directories are pre-created by index.
            var mapping = ["v:0,agroup:aud"]
            for index in 0..<probeResult.audioCount {
                mapping.append("a:\(index),agroup:aud" + (index == 0 ? ",default:yes" : ""))
            }
            args += [
                "-var_stream_map", mapping.joined(separator: " "),
                "-master_pl_name", "master.m3u8",
                "-hls_segment_filename", dir.appendingPathComponent("stream_%v/seg%05d.m4s").path,
                dir.appendingPathComponent("stream_%v/index.m3u8").path,
            ]
            // The hls muxer will not create the per-variant directories itself.
            for index in 0...probeResult.audioCount {
                try? FileManager.default.createDirectory(
                    at: dir.appendingPathComponent("stream_\(index)"),
                    withIntermediateDirectories: true)
            }
        } else {
            args += [
                "-hls_segment_filename", dir.appendingPathComponent("seg%05d.m4s").path,
                dir.appendingPathComponent("index.m3u8").path,
            ]
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.arguments = args
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = FileHandle.nullDevice
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { Log.shared.write("ffmpeg: \(text.prefix(160))") }
        }

        do {
            try process.run()
        } catch {
            Log.shared.write("falha ao iniciar ffmpeg: \(error)")
            return nil
        }

        let session = Session(dir: dir, process: process, variant: variant)
        lock.lock(); sessions[channelID] = session; lock.unlock()
        Log.shared.write("remux iniciado para \(channelID.uuidString.prefix(8))")
        return session
    }

    private func rewrite(_ playlist: String, base: String) -> String {
        var out: [String] = []
        for raw in playlist.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(raw)
            if line.hasSuffix("\r") { line.removeLast() }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Covers EXT-X-MAP and the EXT-X-MEDIA entries of a master playlist.
            if trimmed.hasPrefix("#"), let r = line.range(of: "URI=\"") {
                if let close = line[r.upperBound...].firstIndex(of: "\"") {
                    let name = String(line[r.upperBound..<close])
                    if !name.hasPrefix("http") {
                        line = line.replacingCharacters(in: r.upperBound..<close, with: base + name)
                    }
                }
                out.append(line)
            } else if trimmed.isEmpty || trimmed.hasPrefix("#") {
                out.append(line)
            } else {
                out.append(base + trimmed)
            }
        }
        return out.joined(separator: "\n")
    }

    private func reapIdle() {
        lock.lock()
        let stale = sessions.filter { Date().timeIntervalSince($0.value.lastAccess) > 90 }
        for (id, session) in stale {
            session.process.terminate()
            try? FileManager.default.removeItem(at: session.dir)
            sessions.removeValue(forKey: id)
            Log.shared.write("remux encerrado (ocioso) \(id.uuidString.prefix(8))")
        }
        lock.unlock()
    }

    func stopAll() {
        lock.lock()
        for (_, s) in sessions {
            s.process.terminate()
            try? FileManager.default.removeItem(at: s.dir)
        }
        sessions.removeAll()
        lock.unlock()
    }
}
