import Foundation

/// L'API Google Tasks ne transmet pas l'heure d'échéance : on la range en tête des notes,
/// sur une ligne « ⏰ 15:00 », pour que l'iPhone et l'iPad la partagent.
nonisolated enum NotesTimeCodec {
    static let marker = "⏰"

    static func decode(_ notes: String?) -> (minutes: Int?, notes: String) {
        guard let notes, !notes.isEmpty else { return (nil, "") }
        var lines = notes.components(separatedBy: "\n")
        guard let first = lines.first, first.hasPrefix(marker) else { return (nil, notes) }

        let value = first.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else {
            return (nil, notes)
        }
        lines.removeFirst()
        return (parts[0] * 60 + parts[1], lines.joined(separator: "\n"))
    }

    static func encode(minutes: Int?, notes: String) -> String {
        guard let minutes else { return notes }
        let line = String(format: "%@ %02d:%02d", marker, minutes / 60, minutes % 60)
        return notes.isEmpty ? line : line + "\n" + notes
    }
}
