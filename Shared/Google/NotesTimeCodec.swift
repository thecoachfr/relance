import Foundation

/// Google Tasks n'a ni heure d'échéance (dans son API) ni étiquettes : on range les deux
/// en tête des notes, pour que l'iPhone, l'iPad, la montre et le tri du matin les partagent.
///
///     ⏰ 15:00
///     🏷 Administratif
///     ❗ Urgente            (ou « 🔽 Basse » ; rien pour Normale)
///     🔁 Prévenir 1 jour avant · Relancer toutes les 15 min   (relances propres à la tâche)
///     Notes de l'utilisateur…
nonisolated enum NotesTimeCodec {
    static let timeMarker = "⏰"
    static let categoryMarker = "🏷"

    struct Meta: Equatable {
        var minutes: Int?
        var category: String?
        var priority: TaskPriority = .normal
        var reminders: ReminderOverride?
        var notes: String
    }

    static func decode(_ raw: String?) -> Meta {
        guard let raw, !raw.isEmpty else { return Meta(notes: "") }
        var lines = raw.components(separatedBy: "\n")
        var meta = Meta(notes: "")

        var hasPriority = false
        // Les lignes ⏰, 🏷 et ❗/🔽 sont en tête, dans n'importe quel ordre ; on s'arrête à la première autre ligne.
        while let raw = lines.first {
            // « 🏷️ » (avec le sélecteur de variante U+FE0F) est un autre caractère que « 🏷 » pour Swift :
            // on l'enlève, car le tri (ou un humain) peut écrire l'une ou l'autre forme.
            let first = raw.replacingOccurrences(of: "\u{FE0F}", with: "")
            if meta.minutes == nil, first.hasPrefix(timeMarker), let minutes = parseTime(first) {
                meta.minutes = minutes
            } else if meta.category == nil, first.hasPrefix(categoryMarker) {
                let name = first.dropFirst(categoryMarker.count).trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { break }
                meta.category = name
            } else if meta.reminders == nil, let reminders = ReminderOverride(line: first) {
                meta.reminders = reminders
            } else if !hasPriority, let priority = Self.priority(first) {
                meta.priority = priority
                hasPriority = true
            } else {
                break
            }
            lines.removeFirst()
        }
        meta.notes = lines.joined(separator: "\n")
        return meta
    }

    static func encode(minutes: Int?, category: String? = nil, priority: TaskPriority = .normal,
                       reminders: ReminderOverride? = nil, notes: String) -> String {
        var lines: [String] = []
        if let minutes { lines.append(String(format: "%@ %02d:%02d", timeMarker, minutes / 60, minutes % 60)) }
        if let category, !category.isEmpty { lines.append("\(categoryMarker) \(category)") }
        if let marker = priority.marker { lines.append("\(marker) \(priority.rawValue)") }
        if let line = reminders?.line { lines.append(line) }
        if !notes.isEmpty { lines.append(notes) }
        return lines.joined(separator: "\n")
    }

    /// « ❗ Urgente », « 🔽 Basse » ; le marqueur seul suffit si le mot manque ou est inconnu.
    private static func priority(_ line: String) -> TaskPriority? {
        for p in [TaskPriority.urgent, .low] {
            guard let marker = p.marker, line.hasPrefix(marker) else { continue }
            let name = line.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
            return TaskPriority(name: name) ?? p
        }
        return nil
    }

    private static func parseTime(_ line: String) -> Int? {
        let value = line.dropFirst(timeMarker.count).trimmingCharacters(in: .whitespaces)
        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
        return parts[0] * 60 + parts[1]
    }
}
