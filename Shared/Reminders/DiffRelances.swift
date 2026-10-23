import Foundation

/// Ce qui change entre les relances prévues et celles déjà posées chez iOS. Fonction pure, testée (`DiffRelancesTests`).
nonisolated enum DiffRelances {
    struct Resultat: Equatable {
        /// Nouvelles ou modifiées (poser une relance avec un identifiant existant la remplace).
        var aPoser: [PlannedReminder]
        /// En attente chez iOS mais plus prévues.
        var aRetirer: [String]
        /// Déjà en attente, identiques : rien à faire.
        var inchangees: [String: PlannedReminder]
    }

    /// - `enAttente` : identifiants en attente chez iOS ; `posees` : ce que l'app y a posé la dernière fois.
    ///   Une relance en attente mais inconnue de `posees` (posée par une version d'avant) est reposée, par prudence.
    static func calculer(voulues: [PlannedReminder], enAttente: Set<String>,
                         posees: [String: PlannedReminder]) -> Resultat {
        var aPoser: [PlannedReminder] = []
        var inchangees: [String: PlannedReminder] = [:]
        for r in voulues {
            if enAttente.contains(r.id), posees[r.id] == r { inchangees[r.id] = r } else { aPoser.append(r) }
        }
        let ids = Set(voulues.map(\.id))
        return Resultat(aPoser: aPoser, aRetirer: enAttente.subtracting(ids).sorted(), inchangees: inchangees)
    }

    private static let cle = "relancesPosees"

    static func charger(_ defaults: UserDefaults = AppGroup.defaults) -> [String: PlannedReminder] {
        defaults.data(forKey: cle).flatMap { try? JSONDecoder().decode([String: PlannedReminder].self, from: $0) } ?? [:]
    }

    static func enregistrer(_ posees: [String: PlannedReminder], _ defaults: UserDefaults = AppGroup.defaults) {
        Journal.essayer(.notifications, "Mémoire des relances posées") {
            defaults.set(try JSONEncoder().encode(posees), forKey: cle)
        }
    }
}
