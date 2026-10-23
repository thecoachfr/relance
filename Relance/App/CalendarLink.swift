import EventKit
import Foundation

/// Lien entre une tâche et un événement de l'agenda (Calendrier d'iOS, donc Google Agenda si le compte
/// Google y est ajouté). L'événement dure 1 h et n'a pas d'alerte : c'est Relance qui relance.
/// La tâche garde l'identifiant de l'événement (sur cet appareil) et une ligne « 📅 Dans l'agenda » dans ses
/// notes, pour que les autres appareils sachent qu'il existe.
@MainActor
final class CalendarLink {
    static let shared = CalendarLink()
    static let marker = "📅 Dans l'agenda"
    static let duration: TimeInterval = 3600

    /// Durée de la tâche (P9-H1), sinon une heure.
    static func duration(of item: TaskItem) -> TimeInterval {
        item.dureeMinutes.map { TimeInterval($0 * 60) } ?? duration
    }

    private let store = EKEventStore()

    var isAuthorized: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    /// Agenda qui recevra l'événement : l'agenda par défaut d'iOS (Réglages › Calendrier › Calendrier par défaut).
    var defaultCalendarName: String? { isAuthorized ? store.defaultCalendarForNewEvents?.title : nil }

    func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    static func isLinked(_ notes: String) -> Bool {
        notes.components(separatedBy: .newlines).contains { $0.hasPrefix(marker) }
    }

    func event(for item: TaskItem) -> EKEvent? {
        guard isAuthorized, let id = item.calendarEventID else { return nil }
        return store.event(withIdentifier: id)
    }

    /// Crée l'événement ; renvoie un message d'erreur lisible, ou `nil` si tout va bien.
    func add(_ item: TaskItem, taskStore: TaskStore) async -> String? {
        guard let start = item.dueInstant(), item.dueMinutes != nil else { return "Donne d'abord une heure à la tâche." }
        if !isAuthorized, !(await requestAccess()) {
            return "Aiguillage n'a pas accès au Calendrier. Autorise-le dans Réglages › Aiguillage."
        }
        guard let calendar = store.defaultCalendarForNewEvents else { return "Aucun agenda par défaut sur cet appareil." }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        fill(event, from: item, start: start)
        do {
            try store.save(event, span: .thisEvent)
        } catch {
            return "L'agenda a refusé l'événement : \(error.localizedDescription)"
        }
        item.calendarEventID = event.eventIdentifier
        if !Self.isLinked(item.notes) {
            let notes = item.notes.isEmpty ? Self.marker : item.notes + "\n" + Self.marker
            taskStore.update(item, title: item.title, notes: notes, day: item.dueDay, minutes: item.dueMinutes)
        }
        return nil
    }

    /// Retire l'événement de l'agenda et le lien de la tâche.
    func remove(_ item: TaskItem, taskStore: TaskStore, keepTask: Bool = true) {
        if let event = event(for: item) {
            Journal.essayer(.stockage, "Suppression de l'événement d'agenda") { try store.remove(event, span: .thisEvent) }
        }
        item.calendarEventID = nil
        guard keepTask else { return }
        let notes = item.notes.components(separatedBy: .newlines).filter { !$0.hasPrefix(Self.marker) }.joined(separator: "\n")
        taskStore.update(item, title: item.title, notes: notes, day: item.dueDay, minutes: item.dueMinutes)
    }

    /// Après chaque changement : l'événement suit le titre et l'heure de sa tâche.
    func reconcile(_ items: [TaskItem]) {
        guard isAuthorized else { return }
        for item in items where item.calendarEventID != nil {
            guard let event = event(for: item), let start = item.dueInstant(), item.dueMinutes != nil else { continue }
            let end = start.addingTimeInterval(Self.duration(of: item))
            guard event.startDate != start || event.endDate != end || event.title != item.title else { continue }
            fill(event, from: item, start: start)
            Journal.essayer(.stockage, "Mise à jour de l'événement d'agenda") { try store.save(event, span: .thisEvent) }
        }
    }

    private func fill(_ event: EKEvent, from item: TaskItem, start: Date) {
        event.title = item.title
        event.startDate = start
        event.endDate = start.addingTimeInterval(Self.duration(of: item))
        let contact = TaskContact(notes: item.notes)
        event.location = contact?.address
        event.url = contact?.link
        event.notes = item.notes.components(separatedBy: .newlines)
            .filter { !$0.hasPrefix(Self.marker) }
            .joined(separator: "\n") + "\n\nCréé par Aiguillage."
        event.alarms = []
    }
}
