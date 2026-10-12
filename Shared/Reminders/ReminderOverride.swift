import Foundation

/// Durées lisibles des réglages : « 15 min », « 1 h », « 1 jour ».
nonisolated enum ReminderDuration {
    static func text(_ minutes: Int) -> String {
        switch minutes {
        case 24 * 60: "1 jour"
        case let m where m % 60 == 0: "\(m / 60) h"
        default: "\(minutes) min"
        }
    }

    static func parse(_ text: String) -> Int? {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t == "1 jour" { return 24 * 60 }
        let parts = t.split(separator: " ")
        guard parts.count == 2, let n = Int(parts[0]), n > 0 else { return nil }
        switch parts[1] {
        case "min": return n
        case "h": return n * 60
        default: return nil
        }
    }
}

/// Relances propres à une tâche, qui remplacent celles de sa priorité. Rangées dans les notes Google
/// sur une ligne lisible : « 🔁 Prévenir 1 jour avant · Relancer toutes les 15 min ».
nonisolated struct ReminderOverride: Hashable, Sendable {
    enum Advance: Hashable, Sendable { case off, minutes(Int) }
    enum FollowUp: Hashable, Sendable { case off, once(Int), every(Int) }

    static let marker = "🔁"

    /// `nil` = comme la priorité.
    var advance: Advance?
    var followUp: FollowUp?

    var isEmpty: Bool { advance == nil && followUp == nil }

    // MARK: - Ligne des notes

    var line: String? {
        var parts: [String] = []
        switch advance {
        case .off: parts.append("Ne pas prévenir avant")
        case .minutes(let m): parts.append("Prévenir \(ReminderDuration.text(m)) avant")
        case nil: break
        }
        switch followUp {
        case .off: parts.append("Ne pas relancer")
        case .once(let m): parts.append("Relancer après \(ReminderDuration.text(m))")
        case .every(let m): parts.append("Relancer toutes les \(ReminderDuration.text(m))")
        case nil: break
        }
        return parts.isEmpty ? nil : "\(Self.marker) " + parts.joined(separator: " · ")
    }

    /// Lit une ligne « 🔁 … » ; `nil` si elle n'est pas comprise (elle reste alors dans les notes, intacte).
    init?(line: String) {
        guard line.hasPrefix(Self.marker) else { return nil }
        let body = line.dropFirst(Self.marker.count).trimmingCharacters(in: .whitespaces)
        for part in body.components(separatedBy: " · ") {
            switch part {
            case "Ne pas prévenir avant": advance = .off
            case "Ne pas relancer": followUp = .off
            case let p where p.hasPrefix("Prévenir ") && p.hasSuffix(" avant"):
                guard let m = ReminderDuration.parse(String(p.dropFirst(9).dropLast(6))) else { return nil }
                advance = .minutes(m)
            case let p where p.hasPrefix("Relancer après "):
                guard let m = ReminderDuration.parse(String(p.dropFirst(15))) else { return nil }
                followUp = .once(m)
            case let p where p.hasPrefix("Relancer toutes les "):
                guard let m = ReminderDuration.parse(String(p.dropFirst(20))) else { return nil }
                followUp = .every(m)
            default: return nil
            }
        }
        if isEmpty { return nil }
    }

    init(advance: Advance? = nil, followUp: FollowUp? = nil) {
        self.advance = advance
        self.followUp = followUp
    }
}
