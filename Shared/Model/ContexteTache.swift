import Foundation

/// Contexte d'une tâche (P9-N2, 24/10/2026) : à faire au bureau ou à la maison. Le champ `contexte` de HA fait foi ;
/// la ligne des notes (`🏢 Au bureau` / `🏠 À la maison`) en est la copie, lue par la routine de tri, la vigie, le
/// Nest Hub et le mode Google Tasks. Une tâche sans date à qui l'on donne un contexte prend la date du prochain jour
/// qui correspond, d'après `sensor.aiguillage_lieu_travail` (`LieuTravail.prochainJour`).
nonisolated enum ContexteTache: String, CaseIterable, Sendable, Identifiable {
    case bureau, maison

    var id: String { rawValue }

    /// La ligne des notes, telle quelle (sans sélecteur de variante).
    var ligne: String {
        switch self {
        case .bureau: "🏢 Au bureau"
        case .maison: "🏠 À la maison"
        }
    }

    var libelle: String {
        switch self {
        case .bureau: "Au bureau"
        case .maison: "À la maison"
        }
    }

    var symbole: String {
        switch self {
        case .bureau: "building.2"
        case .maison: "house"
        }
    }

    /// Lieux du jour (`jours[].lieu` du capteur) qui conviennent : bureau → jour de bureau ; maison → télétravail,
    /// ou jour sans Barrière (repos, férié). Même règle que `aiguillage_tri.LIEUX_CONTEXTE`.
    var lieuxDuJour: Set<String> {
        switch self {
        case .bureau: ["bureau"]
        case .maison: ["teletravail", "off", "ferie"]
        }
    }

    /// Le contexte lu dans les notes (ligne exacte, sélecteur de variante ignoré), ou `nil`.
    init?(notes: String) {
        for ligne in notes.components(separatedBy: "\n") {
            let propre = ligne.replacingOccurrences(of: "\u{FE0F}", with: "").trimmingCharacters(in: .whitespaces)
            if let trouve = Self.allCases.first(where: { $0.ligne == propre }) {
                self = trouve
                return
            }
        }
        return nil
    }

    /// Les notes avec la ligne du contexte (à la fin), ou sans ligne pour `nil`. Inchangées si rien ne change.
    static func notes(_ notes: String, setting contexte: ContexteTache?) -> String {
        guard ContexteTache(notes: notes) != contexte || (contexte != nil && !notes.contains(contexte!.ligne)) else {
            return notes
        }
        let lignes = notes.components(separatedBy: "\n").filter { ligne in
            let propre = ligne.replacingOccurrences(of: "\u{FE0F}", with: "").trimmingCharacters(in: .whitespaces)
            return !allCases.contains { $0.ligne == propre }
        }
        let corps = lignes.joined(separator: "\n").trimmingCharacters(in: .newlines)
        guard let contexte else { return corps }
        return corps.isEmpty ? contexte.ligne : corps + "\n" + contexte.ligne
    }
}

extension TaskItem {
    /// Contexte de la tâche (P9-N2), d'après la ligne des notes.
    var contexte: ContexteTache? { ContexteTache(notes: notes) }
}
