import SwiftUI
import AppKit
import CryptoKit

/// Loads channel artwork through the same DoH-capable client the streams use,
/// with an in-memory and on-disk cache so the sidebar stays instant.
@MainActor
final class LogoLoader: ObservableObject {
    static let shared = LogoLoader()

    @Published private(set) var images: [URL: NSImage] = [:]
    private var inFlight: Set<URL> = []

    private let cacheDir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("dev.saimo.player/logos", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    private init() {}

    func image(for url: URL) -> NSImage? {
        if let img = images[url] { return img }
        load(url)
        return nil
    }

    private func cacheFile(_ url: URL) -> URL {
        let digest = Insecure.MD5.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return cacheDir.appendingPathComponent(name).appendingPathExtension("img")
    }

    private func load(_ url: URL) {
        guard !inFlight.contains(url) else { return }
        inFlight.insert(url)

        let file = cacheFile(url)
        if let data = try? Data(contentsOf: file), let img = NSImage(data: data) {
            images[url] = img
            inFlight.remove(url)
            return
        }

        Task.detached(priority: .utility) {
            let data: Data?
            do {
                let res = try Upstream.shared.fetch(url)
                data = (200...299).contains(res.status) ? res.body : nil
            } catch {
                data = nil
            }
            guard let data, let img = NSImage(data: data) else {
                await MainActor.run { LogoLoader.shared.inFlight.remove(url) }
                return
            }
            try? data.write(to: file)
            await MainActor.run {
                LogoLoader.shared.images[url] = img
                LogoLoader.shared.inFlight.remove(url)
            }
        }
    }
}
