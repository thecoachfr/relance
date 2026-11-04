import Foundation

/// Ligne cachée qui donne sa nature à une tâche (`📣 Pour info`, `📌 Rendez-vous`), à la fin des notes.
nonisolated enum LigneDeNature {
    static func presente(_ ligne: String, dans notes: String) -> Bool {
        notes.components(separatedBy: "\n").contains { propre($0) == ligne }
    }

    /// Les notes avec la ligne (à la fin), ou sans. Inchangées si rien ne change.
    static func notes(_ notes: String, ligne: String, actif: Bool) -> String {
        guard presente(ligne, dans: notes) != actif else { return notes }
        let corps = notes.components(separatedBy: "\n").filter { propre($0) != ligne }
            .joined(separator: "\n").trimmingCharacters(in: .newlines)
        guard actif else { return corps }
        return corps.isEmpty ? ligne : corps + "\n" + ligne
    }

    private static func propre(_ ligne: String) -> String {
        ligne.replacingOccurrences(of: "\u{FE0F}", with: "").trimmingCharacters(in: .whitespaces)
    }
}

/// Rendez-vous (P9-T) : il a lieu à une date fixe et il suffit d'y aller (dentiste, soirée). Ligne cachée
/// `📌 Rendez-vous` dans les notes. Rappels avant, jamais de retard, rien à cocher ; passé, il avance à sa prochaine
/// occurrence (ligne 🔄) ou se range, comme une info (`PourInfo.suite`).
nonisolated enum RendezVous {
    static let ligne = "📌 Rendez-vous"

    static func est(_ notes: String) -> Bool { LigneDeNature.presente(ligne, dans: notes) }

    static func notes(_ notes: String, actif: Bool) -> String {
        LigneDeNature.notes(notes, ligne: ligne, actif: actif)
    }
}
