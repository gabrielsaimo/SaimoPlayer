import Foundation

/// Small UserDefaults-backed persistence for things the user builds up:
/// imported channels, favourites and volume.
enum Store {
    private static let customKey = "customChannels"
    private static let favoritesKey = "favorites"
    private static let volumeKey = "volume"

    private static let defaults = UserDefaults.standard

    static func customChannels() -> [Channel] {
        guard let raw = defaults.array(forKey: customKey) as? [[String: String]] else { return [] }
        return raw.compactMap { entry in
            guard let name = entry["name"], let s = entry["url"], let url = URL(string: s) else { return nil }
            return Channel(name: name, source: url)
        }
    }

    static func appendCustom(_ channels: [Channel]) {
        var raw = defaults.array(forKey: customKey) as? [[String: String]] ?? []
        let known = Set(raw.compactMap { $0["url"] })
        for c in channels where !known.contains(c.source.absoluteString) {
            raw.append(["name": c.name, "url": c.source.absoluteString])
        }
        defaults.set(raw, forKey: customKey)
    }

    static func removeCustom(_ channel: Channel) {
        var raw = defaults.array(forKey: customKey) as? [[String: String]] ?? []
        raw.removeAll { $0["url"] == channel.source.absoluteString }
        defaults.set(raw, forKey: customKey)
    }

    static func favorites() -> Set<String> {
        Set(defaults.stringArray(forKey: favoritesKey) ?? [])
    }

    static func setFavorites(_ f: Set<String>) {
        defaults.set(Array(f), forKey: favoritesKey)
    }

    static func volume() -> Double {
        defaults.object(forKey: volumeKey) as? Double ?? 1.0
    }

    static func setVolume(_ v: Double) {
        defaults.set(v, forKey: volumeKey)
    }
}
