import Foundation
import SwiftData

/// Copie locale d'une tâche Google Tasks (liste « Mes tâches »).
@Model
final class TaskItem {
    /// Identifiant Google ; `nil` tant qu'une tâche créée dans l'app n'a pas été envoyée.
    @Attribute(.unique) var localID: UUID
    var googleID: String?
    var title: String
    /// Notes saisies par l'utilisateur, sans la ligne d'heure gérée par l'app.
    var notes: String
    /// Début du jour d'échéance, dans le fuseau local.
    var dueDay: Date?
    /// Heure d'échéance en minutes depuis minuit (stockée dans les notes côté Google).
    var dueMinutes: Int?
    /// Catégorie (ligne « 🏷 » des notes côté Google).
    var category: String?
    /// Ligne « ❗ » / « 🔽 » des notes ; `nil` = Normale.
    var priorityRaw: String?
    /// Ligne « 🔖 … » des notes, sans le marqueur ; `nil` = aucun tag.
    var tagsRaw: String?
    /// Ligne « 🔁 … » des notes : relances propres à la tâche ; `nil` = selon la priorité.
    var remindersRaw: String?
    /// Dernier `lieu` reçu de Home Assistant (JSON de `TacheHA.Lieu`) : garde coordonnées et source,
    /// que la ligne 📍 des notes n'a pas toujours. `nil` en mode Google Tasks.
    var placeRaw: String?
    /// Dernière `envie` reçue de Home Assistant (JSON de `TacheHA.Envie`) : plateforme, identifiant et champs
    /// de la vigie (TMDB), que les lignes des notes n'ont pas. `nil` en mode Google Tasks.
    var envieRaw: String?
    /// Actions reçues de Home Assistant (JSON de `[TacheHA.Action]`, P9-D1) ; `nil` = aucune.
    var actionsRaw: String?
    /// Pièces jointes (JSON de `[TacheHA.Piece]`, P9-K) ; `nil` = aucune.
    var piecesRaw: String?
    /// Durée en minutes (P9-H1), seulement avec une heure ; `nil` = sans durée (1 h dans l'agenda).
    var dureeMinutes: Int?
    /// Liste d'articles (JSON de `TacheHA.Liste`, P9-G) ; `nil` = pas de liste.
    var listeRaw: String?
    /// Dernière liste reçue de Home Assistant : l'ancêtre commun de la fusion article par article.
    var listeBaseRaw: String?
    /// Champs de premier niveau inconnus de l'app (JSON), renvoyés tels quels à Home Assistant.
    var haExtrasRaw: String?
    /// Événement d'agenda créé depuis CET appareil (identifiant EventKit, propre à l'appareil).
    var calendarEventID: String?
    var isCompleted: Bool
    var completedAt: Date?
    var snoozedUntil: Date?
    var isTrashed: Bool
    /// Modifiée localement et pas encore envoyée à Google.
    var isDirty: Bool
    var updatedAt: Date

    init(title: String, notes: String = "", dueDay: Date? = nil, dueMinutes: Int? = nil) {
        localID = UUID()
        self.title = title
        self.notes = notes
        self.dueDay = dueDay
        self.dueMinutes = dueMinutes
        isCompleted = false
        isTrashed = false
        isDirty = true
        updatedAt = .now
    }

    /// Instant de l'échéance : l'heure si connue, sinon la fin du jour.
    func dueInstant(calendar: Calendar = .current) -> Date? {
        guard let dueDay else { return nil }
        if let dueMinutes {
            return calendar.date(bySettingHour: dueMinutes / 60, minute: dueMinutes % 60, second: 0, of: dueDay)
        }
        return calendar.date(byAdding: .day, value: 1, to: dueDay)
    }

    /// Une sortie passée n'est pas en retard : elle attend « Vu » dans Envies (Passées).
    func isOverdue(now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard !isCompleted, toSee?.kind.isDated != true, let due = dueInstant(calendar: calendar) else { return false }
        return due < now
    }

    var priority: TaskPriority {
        get { priorityRaw.flatMap(TaskPriority.init(rawValue:)) ?? .normal }
        set { priorityRaw = newValue == .normal ? nil : newValue.rawValue }
    }

    var tags: [String] {
        get { tagsRaw.flatMap { TaskTag.parse(TaskTag.marker + $0) } ?? [] }
        set { tagsRaw = TaskTag.line(newValue).map { String($0.dropFirst(TaskTag.marker.count + 1)) } }
    }

    var reminderOverride: ReminderOverride? {
        get { remindersRaw.flatMap(ReminderOverride.init(line:)) }
        set { remindersRaw = newValue?.line }
    }

    /// À trier : pas de date, ou une date sans heure.
    /// À garder sans échéance (« 👀 À voir ») : ni dans À trier, ni relancée chaque jour.
    var toSee: ToSee? { ToSee(notes: notes) }
    /// À trier : sans date, ou datée d'aujourd'hui (ou d'avant) sans heure — là, l'heure devient utile.
    /// Une tâche datée plus tard sans heure reste dans À faire ; le matin du jour, une notification demande l'heure.
    /// Rattachée à mes lieux (liste de courses) : datée sans heure, elle reste dans À faire, le magasin la rappelle
    /// (17/10, remarque d'Alexandre).
    var needsTriage: Bool { needsTriage() }

    func needsTriage(now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard toSee == nil else { return false }
        guard let dueDay else { return true }
        return dueMinutes == nil && calendar.startOfDay(for: dueDay) <= calendar.startOfDay(for: now) && groupesDeLieux.isEmpty
    }

    func markChanged() {
        isDirty = true
        updatedAt = .now
    }

    func plannable(calendar: Calendar = .current) -> PlannableTask {
        PlannableTask(
            id: localID.uuidString,
            title: title,
            dueDay: dueDay.map { calendar.dateComponents([.year, .month, .day], from: $0) },
            dueMinutes: dueMinutes,
            snoozedUntil: snoozedUntil,
            priority: priority,
            reminders: reminderOverride,
            hasPlace: TaskContact(notes: notes)?.destination != nil,
            toSee: toSee,
            linkHost: toSee == nil ? nil : ToSee.link(in: notes)?.host()?.replacingOccurrences(of: "www.", with: ""),
            atMyPlaces: !groupesDeLieux.isEmpty,
            imageID: pieces.first(where: \.estImage)?.id)
    }
}
