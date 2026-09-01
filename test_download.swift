import Foundation

let url = URL(string: "https://github.com/gabrielsaimo/SaimoPlayer/releases/download/v1.1/SaimoTV.dmg")!
let group = DispatchGroup()
group.enter()

Task {
    do {
        print("Starting download...")
        let (file, response) = try await URLSession.shared.download(from: url)
        print("Downloaded to \(file.path), response: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
    } catch {
        print("Error: \(error)")
    }
    group.leave()
}

group.wait()
