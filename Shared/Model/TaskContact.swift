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

    init(name: String, address: String? = nil, phone: String? = nil, link: URL? = nil) {
        (self.name, self.address, self.phone, self.link) = (name, address, phone, link)
    }

    /// « 📍 Nom · adresse · téléphone · lien » (parties vides omises, « · » retiré des valeurs).
    var line: String {
        // Une simple adresse : écrite une fois (« 📍 67 rue X, 94140 Ville »), pas en nom puis en adresse.
        // Idem quand le nom n'est que le début de l'adresse (« 67 rue X » puis « 67 rue X, 94140 Ville »).
        let addressOnly = address.map { $0 == name || $0.lowercased().hasPrefix(name.lowercased()) } ?? false
        let parts = [addressOnly ? address : name, addressOnly ? nil : address, phone, link?.absoluteString]
            .compactMap { $0?.replacingOccurrences(of: " · ", with: ", ").trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return Self.marker + " " + parts.joined(separator: " · ")
    }

    /// Les notes avec ce lieu à la place de l'ancien (même ligne), ajouté à la fin s'il n'y en avait pas,
    /// ou retiré si `contact` est `nil`.
    static func notes(_ notes: String, setting contact: TaskContact?) -> String {
        var lines = notes.components(separatedBy: "\n")
        let index = lines.firstIndex { $0.trimmingCharacters(in: .whitespaces).hasPrefix(marker) }
        switch (index, contact) {
        case let (i?, c?): lines[i] = c.line
        case let (i?, nil): lines.remove(at: i)
        case let (nil, c?):
            while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeLast() }
            lines.append(c.line)
        case (nil, nil): break
        }
        return lines.joined(separator: "\n")
    }

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
        // Un « nom » qui est une adresse (code postal à 5 chiffres) sert aussi d'adresse : itinéraire, trajet.
        if first.range(of: #"\b\d{5}\b"#, options: .regularExpression) != nil { address = first }
        for part in parts.dropFirst() {
            if let url = URL(string: part), url.scheme?.hasPrefix("http") == true {
                link = url
            } else if part.range(of: #"^\+?[\d .\-()]{8,}$"#, options: .regularExpression) != nil {
                phone = part
            } else if address == nil || address == name {
                address = part
            }
        }
    }

    /// Lien de prise de rendez-vous (Doctolib…) plutôt que simple site web.
    var isBookingLink: Bool {
        guard let host = link?.host()?.lowercased() else { return false }
        return ["doctolib", "maiia", "keldoc", "rdv", "planity", "calendly"].contains { host.contains($0) }
    }

    var phoneURL: URL? {
        phone.flatMap { URL(string: "tel:" + $0.filter { $0.isNumber || $0 == "+" }) }
    }

    /// Fiche du lieu dans Google Maps (app si installée, sinon navigateur), pour l'enregistrer « À visiter ».
    /// Google ne permet pas d'ajouter un lieu à une liste depuis une autre app : il reste un toucher.
    var googleMapsURL: URL? {
        var c = URLComponents(string: "https://www.google.com/maps/search/")!
        let query = [name, address].compactMap { $0 }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        c.queryItems = [URLQueryItem(name: "api", value: "1"), URLQueryItem(name: "query", value: query.joined(separator: ", "))]
        return c.url
    }

    /// Itinéraire dans Plans.
    var mapsURL: URL? {
        guard let address else { return nil }
        var c = URLComponents(string: "https://maps.apple.com/")!
        c.queryItems = [URLQueryItem(name: "daddr", value: address)]
        return c.url
    }
}

/// « Me le rappeler en passant à côté » : ligne « 🔔 À l'approche » dans les notes, pour que le choix suive
/// la tâche sur tous les appareils (seul l'appareil qui relance surveille le lieu).
nonisolated enum NearbyReminder {
    static let line = "🔔 À l'approche"

    static func isOn(_ notes: String) -> Bool {
        notes.components(separatedBy: "\n").contains { NoteLines.isHidden($0) && $0.contains("À l'approche") }
    }

    static func notes(_ notes: String, on: Bool) -> String {
        var lines = notes.components(separatedBy: "\n").filter { !($0.contains("🔔") && $0.contains("À l'approche")) }
        while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeLast() }
        if on { lines.append(line) }
        return lines.joined(separator: "\n")
    }
}
