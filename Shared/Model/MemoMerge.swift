import Foundation

/// Ajout au mémo sans doublon : une fiche du même sujet est complétée au lieu d'en créer une autre.
/// Utilisé par l'iPhone, l'iPad, le Mac (`MemoStore`) et la montre (`WatchStore`).
nonisolated enum MemoMerge {
    static let listTitle = "Relance · mémo"
    static let separator = " — "

    enum Outcome: Equatable, Sendable {
        case added, completed, unchanged
    }

    /// Même sujet, sans tenir compte des majuscules ni des accents (« dentiste » = « Dentiste »).
    static func sameSubject(_ a: String, _ b: String) -> Bool {
        a.trimmingCharacters(in: .whitespaces)
            .compare(b.trimmingCharacters(in: .whitespaces), options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    /// Détails existants complétés des seules parties nouvelles (séparées par « — ») ; `nil` si rien de neuf.
    static func merged(_ existing: String, adding new: String) -> String? {
        let known = existing.lowercased()
        let fresh = new.components(separatedBy: separator)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !known.contains($0.lowercased()) }
        guard !fresh.isEmpty else { return nil }
        let base = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        return ([base].filter { !$0.isEmpty } + fresh).joined(separator: separator)
    }

    /// Réponse de Siri ; `nil` = Google injoignable.
    static func confirmation(_ outcome: Outcome?, subject: String) -> String {
        switch outcome {
        case .added: "C'est noté dans le mémo : « \(subject) »."
        case .completed: "J'ai complété la fiche « \(subject) »."
        case .unchanged: "La fiche « \(subject) » le dit déjà."
        case nil: "Je n'ai pas pu enregistrer la fiche. Réessaie dans un moment."
        }
    }
}
