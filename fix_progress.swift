import Foundation

let path = "Sources/Atualizacao.swift"
var content = try! String(contentsOfFile: path)

let oldBaixar = """
    private func baixar(_ de: URL) async throws -> URL {
        let (fonte, resposta) = try await URLSession.shared.download(from: de)
        guard let http = resposta as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw NSError(domain: "Atualizacao", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "download recusado"])
        }
        let destino = FileManager.default.temporaryDirectory
            .appendingPathComponent("SaimoTV-\\(UUID().uuidString).dmg")
        try? FileManager.default.removeItem(at: destino)
        try FileManager.default.moveItem(at: fonte, to: destino)
        progresso = 1
        return destino
    }
"""

let newBaixar = """
    private func baixar(_ de: URL) async throws -> URL {
        let (bytes, resposta) = try await URLSession.shared.bytes(from: de)
        guard let http = resposta as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw NSError(domain: "Atualizacao", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "download recusado"])
        }
        
        let destino = FileManager.default.temporaryDirectory
            .appendingPathComponent("SaimoTV-\\(UUID().uuidString).dmg")
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
"""

if content.contains("URLSession.shared.download(from: de)") {
    content = content.replacingOccurrences(of: oldBaixar, with: newBaixar)
    try! content.write(toFile: path, atomically: true, encoding: .utf8)
    print("Fixed baixar to show progress")
} else {
    print("Could not find old baixar method")
}
