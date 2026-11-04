import Foundation

/// Rappel « pour info » (P9-P) : il signale (femme de ménage, poubelles…) et ne demande rien. Ligne cachée
/// `📣 Pour info` dans les notes. Ni relance, ni retard, ni « À trier », rien à cocher : annoncé dans le résumé
/// du matin et montré à part le jour venu. Passé, il avance à sa prochaine occurrence (ligne 🔄) ou se range.
nonisolated enum PourInfo {
    static let ligne = "📣 Pour info"

    static func est(_ notes: String) -> Bool { LigneDeNature.presente(ligne, dans: notes) }

    /// Les notes avec la ligne (à la fin), ou sans. Inchangées si rien ne change.
    static func notes(_ notes: String, actif: Bool) -> String {
        LigneDeNature.notes(notes, ligne: ligne, actif: actif)
    }

    /// L'info tombe ce jour-là : c'est sa date, ou sa date est passée et sa répétition tombe ce jour-là
    /// (l'affichage ne dépend pas de l'avancée, faite par l'appareil qui relance).
    static func tombe(le jour: Date, echeance: Date, repetition: Recurrence?, calendar: Calendar = .current) -> Bool {
        let jour = calendar.startOfDay(for: jour), echeance = calendar.startOfDay(for: echeance)
        if jour == echeance { return true }
        guard echeance < jour, let repetition else { return false }
        return prochaine(echeance: echeance, repetition: repetition, aPartirDe: jour, calendar: calendar) == jour
    }

    /// Jours où l'info tombe parmi les `nombre` jours à partir de `debut` (début de jour), pour le planificateur.
    static func jours(echeance: Date, repetition: Recurrence?, debut: Date, nombre: Int,
                      calendar: Calendar = .current) -> [Date] {
        let debut = calendar.startOfDay(for: debut)
        return (0..<nombre).compactMap { calendar.date(byAdding: .day, value: $0, to: debut) }
            .filter { tombe(le: $0, echeance: echeance, repetition: repetition, calendar: calendar) }
    }

    /// Ce que devient une info ou un rendez-vous passé (date avant `aujourdhui`) : sa prochaine date (≥ aujourd'hui) si elle se
    /// répète, rangée sinon ; inchangée si elle n'est pas passée.
    enum Suite: Equatable { case inchangee, avancee(Date), rangee }

    static func suite(echeance: Date, repetition: Recurrence?, aujourdhui: Date, calendar: Calendar = .current) -> Suite {
        let aujourdhui = calendar.startOfDay(for: aujourdhui)
        guard calendar.startOfDay(for: echeance) < aujourdhui else { return .inchangee }
        guard let repetition else { return .rangee }
        return .avancee(prochaine(echeance: echeance, repetition: repetition, aPartirDe: aujourdhui, calendar: calendar))
    }

    /// Première occurrence ≥ `jour` (`nextDay` rend la première après la veille).
    private static func prochaine(echeance: Date, repetition: Recurrence, aPartirDe jour: Date, calendar: Calendar) -> Date {
        let veille = calendar.date(byAdding: .day, value: -1, to: jour)!
        return calendar.startOfDay(for: repetition.nextDay(after: echeance, done: veille, calendar: calendar))
    }
}

extension TaskItem {
    var estPourInfo: Bool { PourInfo.est(notes) }

    /// Heure d'une info (« 7 h 30 »), seulement affichée ; `nil` sans heure.
    var heurePourInfo: String? { dueMinutes.map(ReminderPlanner.formatTime) }

    /// Info du jour : à montrer dans « Pour info aujourd'hui ».
    func pourInfoDuJour(now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard estPourInfo, !isCompleted, !isTrashed, let dueDay else { return false }
        return PourInfo.tombe(le: now, echeance: dueDay, repetition: Recurrence(notes: notes), calendar: calendar)
    }
}
