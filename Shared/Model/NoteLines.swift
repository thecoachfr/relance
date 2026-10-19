import Foundation

/// Lignes techniques des notes, cachées dans le champ Notes parce qu'elles sont déjà montrées ailleurs
/// (📍 dans la section Lieu, 📅 dans la section Agenda) ou ne servent qu'au tri (📩). Elles restent dans
/// Google Tasks : en modifiant le texte visible, on les garde telles quelles.
nonisolated enum NoteLines {
    static let hiddenPrefixes = ["📍", "📅 Dans l'agenda", "📩 Message partagé", "🔔 À l'approche", "🔕 Pas à l'approche", "👀 À voir", "🎟 Sortie", "📖 À lire", "🎧 À écouter", "🎬 À regarder", "🍽 À tester", "🛍 Magasin", "📷 Spot photo", "🗓", "🔄", "↪ Suivante créée", "➕ Proposition", "🛒 Liste :", "📎 "]

    static func isHidden(_ line: String) -> Bool {
        let clean = line.replacingOccurrences(of: "\u{FE0F}", with: "").trimmingCharacters(in: .whitespaces)
        return hiddenPrefixes.contains { clean.hasPrefix($0) }
    }

    /// Le texte à montrer et à modifier.
    static func visible(_ notes: String) -> String {
        notes.components(separatedBy: "\n").filter { !isHidden($0) }.joined(separator: "\n")
            .trimmingCharacters(in: .newlines)
    }

    /// Les notes complètes après modification du texte visible : les lignes cachées sont gardées
    /// (à la fin). Sans changement visible, les notes restent identiques, à l'octet près.
    static func replacingVisible(in notes: String, with text: String) -> String {
        guard text != visible(notes) else { return notes }
        let hidden = notes.components(separatedBy: "\n").filter(isHidden)
        let body = text.trimmingCharacters(in: .newlines)
        return ([body].filter { !$0.isEmpty } + hidden).joined(separator: "\n")
    }
}
