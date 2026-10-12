import Foundation

/// Tags : le contexte ou le projet d'une tâche (#SCI, #Photo…), en plus de sa catégorie.
/// Transversaux et cumulables (3 au plus). Rangés dans les notes Google : « 🔖 SCI, Photo ».
nonisolated enum TaskTag {
    static let marker = "🔖"
    static let maxPerTask = 3
    /// Tags de départ (12/10) ; ceux créés ensuite sont retrouvés dans les tâches.
    static let defaults = ["SCI", "Micro", "Photo", "Syndic", "Travaux", "Spectacle"]

    static func line(_ tags: [String]) -> String? {
        let tags = normalized(tags)
        return tags.isEmpty ? nil : "\(marker) " + tags.joined(separator: ", ")
    }

    static func parse(_ line: String) -> [String]? {
        guard line.hasPrefix(marker) else { return nil }
        let tags = normalized(line.dropFirst(marker.count).components(separatedBy: ","))
        return tags.isEmpty ? nil : tags
    }

    /// Sans « # », sans doublon (majuscules ignorées), 3 au plus.
    static func normalized(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags
            .map { $0.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "#"))) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            .prefix(maxPerTask)
            .map { $0 }
    }
}
