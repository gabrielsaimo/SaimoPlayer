import Foundation

extension PlayerModel {
    func playChannel(bySlug slug: String) {
        let nameToFind: String
        switch slug.lowercased() {
        case "espn": nameToFind = "ESPN"
        case "espn2": nameToFind = "ESPN 2"
        case "espn3": nameToFind = "ESPN 3"
        case "espn4": nameToFind = "ESPN 4"
        case "espn5": nameToFind = "ESPN 5"
        case "espn6": nameToFind = "ESPN 6"
        case "sportv": nameToFind = "SporTV"
        case "sportv2": nameToFind = "SporTV 2"
        case "sportv3": nameToFind = "SporTV 3"
        case "globo": nameToFind = "Globo RJ" // or standard Globo
        default:
            nameToFind = slug.replacingOccurrences(of: "-", with: " ").capitalized
        }
        
        let exactMatch = channels.first(where: { $0.name.lowercased().replacingOccurrences(of: " ", with: "") == slug.lowercased() })
        let fuzzyMatch = channels.first(where: { $0.name.caseInsensitiveCompare(nameToFind) == .orderedSame || $0.name.lowercased().contains(nameToFind.lowercased()) })
        
        if let match = exactMatch ?? fuzzyMatch {
            self.selection = match.id
        }
    }
}
