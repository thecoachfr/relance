import Foundation
import Testing
@testable import Relance

/// Suggestions d'envies au bon moment : créneaux, rotation, « Pas maintenant », période.
struct EnvieSuggestionTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        return c
    }()
    /// Octobre 2026 : le jeudi 15, le vendredi 16, le samedi 17.
    func date(_ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: min))!
    }
    func envie(_ id: String, _ kind: ToSee.Kind, start: Date? = nil, end: Date? = nil) -> PlannableTask {
        PlannableTask(id: id, title: id, toSee: ToSee(kind, start: start, end: end))
    }
    func planner(horizon: Int = 3) -> ReminderPlanner {
        var p = ReminderPlanner(calendar: calendar)
        p.settings.horizonDays = horizon
        p.settings.eveningDigest = false
        return p
    }

    @Test func oneSuggestionPerSlotInRotation() {
        let plan = planner().plan(tasks: [envie("a", .read), envie("b", .read)], inboxCount: 0, now: date(15, 12))
        let read = plan.filter { $0.kind == .suggestion }
        // Lire tous les jours à 21 h 30 : jeudi, vendredi, samedi (l'horizon s'arrête dimanche midi).
        #expect(read.map(\.fireDate) == [date(15, 21, 30), date(16, 21, 30), date(17, 21, 30)])
        #expect(read.map(\.taskID) == ["a", "b", "a"])
        #expect(read.first?.subtitle == "À lire")
        #expect(read.first?.body == "Un moment pour lire ce soir ?")
        #expect(read.allSatisfy { !$0.timeSensitive })
    }

    @Test func weekdaysAndKinds() {
        let tasks = [envie("film", .watch), envie("album", .listen), envie("expo", .outing)]
        let plan = planner(horizon: 7).plan(tasks: tasks, inboxCount: 0, now: date(15, 12)).filter { $0.kind == .suggestion }
        // Regarder : vendredi et samedi à 20 h 45 ; écouter : les jours de semaine à 8 h 30 ; une sortie : jamais.
        #expect(plan.filter { $0.taskID == "film" }.map(\.fireDate) == [date(16, 20, 45), date(17, 20, 45)])
        #expect(plan.filter { $0.taskID == "album" }.map(\.fireDate) == [date(16, 8, 30), date(19, 8, 30), date(20, 8, 30), date(21, 8, 30), date(22, 8, 30)])
        #expect(!plan.contains { $0.taskID == "expo" })
    }

    @Test func leastRecentlySuggestedFirstAndSkipped() {
        var history = EnvieHistory()
        history.lastSuggested["a"] = date(14, 21, 30)
        var p = planner(horizon: 1)
        p.history = history
        #expect(p.plan(tasks: [envie("a", .read), envie("b", .read)], inboxCount: 0, now: date(15, 12))
            .filter { $0.kind == .suggestion }.map(\.taskID) == ["b"])

        // « Pas maintenant » : une semaine sans elle ; seule, rien n'est proposé.
        history.skip("b", now: date(15, 12), calendar: calendar)
        p.history = history
        #expect(p.plan(tasks: [envie("b", .read)], inboxCount: 0, now: date(15, 12)).filter { $0.kind == .suggestion }.isEmpty)
        #expect(p.plan(tasks: [envie("a", .read), envie("b", .read)], inboxCount: 0, now: date(15, 12))
            .filter { $0.kind == .suggestion }.map(\.taskID) == ["a"])
    }

    @Test func periodSettingsAndQuietHours() {
        // Un film qui ne sort que samedi n'est pas proposé vendredi.
        let film = envie("film", .watch, start: date(17))
        #expect(planner().plan(tasks: [film], inboxCount: 0, now: date(15, 12))
            .filter { $0.kind == .suggestion }.map(\.fireDate) == [date(17, 20, 45)])
        // Créneau désactivé, ou dans la plage silencieuse : rien.
        var p = planner()
        p.settings.suggestions.watch.enabled = false
        #expect(p.plan(tasks: [film], inboxCount: 0, now: date(15, 12)).filter { $0.kind == .suggestion }.isEmpty)
        p = planner()
        p.settings.suggestions.read.minutes = 23 * 60
        #expect(p.plan(tasks: [envie("a", .read)], inboxCount: 0, now: date(15, 12)).filter { $0.kind == .suggestion }.isEmpty)
    }

    @Test func historyRecordsShownSuggestions() {
        var history = EnvieHistory()
        history.planned = ["a": date(15, 21, 30), "b": date(16, 21, 30)]
        history.recordShown(now: date(16, 8))
        #expect(history.lastSuggested == ["a": date(15, 21, 30)])
        #expect(history.planned == ["b": date(16, 21, 30)])
        history.skippedUntil["gone"] = date(20)
        history.keepOnly(["a"], now: date(16, 8))
        #expect(history.skippedUntil.isEmpty && history.lastSuggested.keys.sorted() == ["a"])
    }

    @Test func settingsKeepTheirDefaultsWhenMissing() throws {
        let old = try JSONDecoder().decode(ReminderSettings.self, from: Data(#"{"morning": 480}"#.utf8))
        #expect(old.suggestions == EnvieSuggestions())
        var s = ReminderSettings()
        s.suggestions.listen.weekdays = [1]
        let back = try JSONDecoder().decode(ReminderSettings.self, from: JSONEncoder().encode(s))
        #expect(back.suggestions.listen.weekdays == [1])
    }
}
