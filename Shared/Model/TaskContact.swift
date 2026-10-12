import Foundation

/// Contact d'une tâche, ajouté dans les notes par le tri à partir du mémo :
/// « 📍 Dr Claire Martin · 12 rue de la Paix, 75002 Paris · 01 23 45 67 89 · https://… ».
/// Seul le nom est obligatoire ; l'ordre des autres parties est libre.
nonisolated struct TaskContact: Equatable, Sendable {
    static let marker = "📍"

    var name: String
    var address: String?
    var phone: String?
    var link: URL?

    /// Première ligne « 📍 … » des notes.
    init?(notes: String) {
        guard let line = notes.components(separatedBy: .newlines)
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .first(where: { $0.hasPrefix(Self.marker) }) else { return nil }
        let parts = line.dropFirst(Self.marker.count)
            .components(separatedBy: " · ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let first = parts.first else { return nil }
        name = first
        for part in parts.dropFirst() {
            if let url = URL(string: part), url.scheme?.hasPrefix("http") == true {
                link = url
            } else if part.range(of: #"^\+?[\d .\-()]{8,}$"#, options: .regularExpression) != nil {
                phone = part
            } else if address == nil {
                address = part
            }
        }
    }

    var phoneURL: URL? {
        phone.flatMap { URL(string: "tel:" + $0.filter { $0.isNumber || $0 == "+" }) }
    }

    /// Itinéraire dans Plans.
    var mapsURL: URL? {
        guard let address else { return nil }
        var c = URLComponents(string: "https://maps.apple.com/")!
        c.queryItems = [URLQueryItem(name: "daddr", value: address)]
        return c.url
    }
}
