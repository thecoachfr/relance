import Foundation
import Testing
@testable import Relance

@MainActor
struct ReminderPlannerTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        return c
    }()

    var planner: ReminderPlanner { ReminderPlanner(calendar: calendar) }

    func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    func task(_ id: String, day: Int?, minutes: Int? = nil, snoozed: Date? = nil,
              priority: TaskPriority = .normal) -> PlannableTask {
        PlannableTask(id: id, title: id,
                      dueDay: day.map { DateComponents(year: 2026, month: 10, day: $0) },
                      dueMinutes: minutes, snoozedUntil: snoozed, priority: priority)
    }

    func taskReminders(_ plan: [PlannedReminder], _ id: String) -> [(Date, ReminderKind)] {
        plan.filter { $0.taskID == id }.map { ($0.fireDate, $0.kind) }
    }

    @Test func timedTaskFiresAtDueThenPlusOneHourThenEvening() {
        let plan = planner.plan(tasks: [task("a", day: 12, minutes: 15 * 60)], inboxCount: 0, now: date(12, 8))
        let a = taskReminders(plan, "a")
        #expect(a.prefix(3).map(\.0) == [date(12, 15), date(12, 16), date(12, 20)])
        #expect(a.prefix(3).map(\.1) == [.due, .followUp, .evening])
        // Jours suivants : 20 h uniquement (le matin passe par le résumé).
        #expect(a.dropFirst(3).allSatisfy { $0.1 == .overdue && calendar.component(.hour, from: $0.0) == 20 })
    }

    @Test func eveningSkippedWhenFollowUpIsAfterIt() {
        let plan = planner.plan(tasks: [task("a", day: 12, minutes: 19 * 60 + 30)], inboxCount: 0, now: date(12, 8))
        let sameDay = taskReminders(plan, "a").filter { calendar.isDate($0.0, inSameDayAs: date(12, 0)) }
        #expect(sameDay.map(\.1) == [.due, .followUp])
    }

    @Test func dateOnlyTaskAsksTimeInMorningThenEvening() {
        let plan = planner.plan(tasks: [task("a", day: 12)], inboxCount: 0, now: date(11, 21))
        let a = taskReminders(plan, "a")
        #expect(a.prefix(2).map(\.0) == [date(12, 7, 30), date(12, 20)])
        #expect(a.prefix(2).map(\.1) == [.askTime, .evening])
    }

    @Test func quietHoursMuteFollowUpButNotDue() {
        let plan = planner.plan(tasks: [task("a", day: 12, minutes: 22 * 60 + 15)], inboxCount: 0, now: date(12, 8))
        let sameDay = taskReminders(plan, "a").filter { calendar.isDate($0.0, inSameDayAs: date(12, 0)) }
        #expect(sameDay.map(\.1) == [.due])  // 20 h tombe avant l'échéance, +1 h dans la plage silencieuse
    }

    @Test func snoozeReplacesEarlierReminders() {
        let plan = planner.plan(tasks: [task("a", day: 12, minutes: 15 * 60, snoozed: date(12, 18))],
                                inboxCount: 0, now: date(12, 15, 5))
        let sameDay = taskReminders(plan, "a").filter { calendar.isDate($0.0, inSameDayAs: date(12, 0)) }
        #expect(sameDay.map(\.0) == [date(12, 18), date(12, 20)])
        #expect(sameDay.map(\.1) == [.snoozed, .evening])
    }

    @Test func overdueTextCountsDays() {
        let plan = planner.plan(tasks: [task("a", day: 10, minutes: 9 * 60)], inboxCount: 0, now: date(12, 8))
        let first = plan.first { $0.taskID == "a" }!
        #expect(first.fireDate == date(12, 20))
        #expect(first.body == "En retard depuis 2 jours.")
        #expect(first.timeSensitive)
    }

    @Test func pastRemindersAreDropped() {
        let plan = planner.plan(tasks: [task("a", day: 12, minutes: 9 * 60)], inboxCount: 0, now: date(12, 12))
        #expect(taskReminders(plan, "a").first?.0 == date(12, 20))
    }

    @Test func undatedTasksOnlyAppearInDigest() {
        let plan = planner.plan(tasks: [task("a", day: nil)], inboxCount: 1, now: date(12, 8))
        #expect(plan.allSatisfy { $0.kind == .digest })
        #expect(plan.first?.fireDate == date(13, 7, 30))
        #expect(plan.first?.body == "1 à trier")
    }

    @Test func eveningDigestAnnouncesTomorrow() {
        let tasks = [task("a", day: 13, minutes: 9 * 60), task("b", day: 13, minutes: 14 * 60, priority: .urgent),
                     task("c", day: 13), task("late", day: 11, minutes: 10 * 60)]
        let plan = planner.plan(tasks: tasks, inboxCount: 0, now: date(12, 18))
        let evening = plan.first { $0.kind == .digest && $0.title == "Demain" }!
        #expect(evening.fireDate == date(12, 21))
        #expect(evening.body == "3 tâches, dont 1 urgente · la première à 9 h · 1 encore en retard")
    }

    @Test func eveningDigestSkipsEmptyTomorrowAndCanBeOff() {
        let quiet = planner.plan(tasks: [task("a", day: 20, minutes: 9 * 60)], inboxCount: 0, now: date(12, 18))
        #expect(!quiet.contains { $0.title == "Demain" && $0.fireDate == date(12, 21) })
        var off = planner
        off.settings.eveningDigest = false
        let plan = off.plan(tasks: [task("a", day: 13, minutes: 9 * 60)], inboxCount: 0, now: date(12, 18))
        #expect(!plan.contains { $0.title == "Demain" })
    }

    @Test func digestSummarisesOverdueAndToday() {
        let tasks = [task("late", day: 11, minutes: 10 * 60), task("today", day: 13, minutes: 14 * 60)]
        let plan = planner.plan(tasks: tasks, inboxCount: 2, now: date(12, 21))
        let digest = plan.first { $0.kind == .digest }!
        #expect(digest.fireDate == date(13, 7, 30))
        #expect(digest.body == "1 en retard · 1 aujourd'hui · 2 à trier")
        #expect(digest.badge == 1)
    }

    @Test func capsAtMaxRequestsKeepingEarliest() {
        let tasks = (0..<30).map { task("t\($0)", day: 12, minutes: 9 * 60) }
        let plan = planner.plan(tasks: tasks, inboxCount: 0, now: date(12, 8))
        #expect(plan.count == 60)
        #expect(plan.map(\.fireDate) == plan.map(\.fireDate).sorted())
        #expect(plan.first?.fireDate == date(12, 9))
    }

    @Test func formatsFrenchTimes() {
        #expect(ReminderPlanner.formatTime(15 * 60) == "15 h")
        #expect(ReminderPlanner.formatTime(7 * 60 + 5) == "7 h 05")
    }

    // MARK: - Priorité

    @Test func urgentRepeatsEvery30MinutesUntilQuietHours() {
        let plan = planner.plan(tasks: [task("a", day: 12, minutes: 20 * 60, priority: .urgent)], inboxCount: 0, now: date(12, 8))
        let sameDay = taskReminders(plan, "a").filter { calendar.isDate($0.0, inSameDayAs: date(12, 0)) }
        // 20 h, 20 h 30, 21 h, 21 h 30 ; 22 h et après : plage silencieuse.
        #expect(sameDay.map(\.0) == [date(12, 20), date(12, 20, 30), date(12, 21), date(12, 21, 30)])
        #expect(plan.filter { $0.taskID == "a" }.allSatisfy { $0.timeSensitive && $0.subtitle == "Urgente" })
        // En retard : 7 h 30, midi et 20 h.
        let nextDay = taskReminders(plan, "a").filter { calendar.isDate($0.0, inSameDayAs: date(13, 0)) }
        #expect(nextDay.map(\.0) == [date(13, 7, 30), date(13, 12), date(13, 20)])
    }

    @Test func lowFiresOnceAndNeverWhenDateOnly() {
        let plan = planner.plan(tasks: [task("a", day: 12, minutes: 15 * 60, priority: .low),
                                        task("b", day: 12, priority: .low)], inboxCount: 0, now: date(12, 8))
        #expect(taskReminders(plan, "a").map(\.1) == [.due])
        #expect(plan.filter { $0.taskID == "a" }.allSatisfy { !$0.timeSensitive })
        #expect(taskReminders(plan, "b").isEmpty)
    }

    // MARK: - Réglages par priorité

    @Test func advanceReminderBeforeDue() {
        var settings = ReminderSettings()
        settings.normal.advanceMinutes = 15
        let plan = ReminderPlanner(calendar: calendar, settings: settings)
            .plan(tasks: [task("a", day: 12, minutes: 15 * 60)], inboxCount: 0, now: date(12, 8))
        let first = plan.first { $0.taskID == "a" }!
        #expect(first.fireDate == date(12, 14, 45))
        #expect(first.kind == .advance)
        #expect(first.body == "Dans 15 min · prévu à 15 h.")
    }

    @Test func customProfileRepeatsAndSlots() {
        var settings = ReminderSettings()
        settings.normal = ReminderProfile(advanceMinutes: nil, followUpMinutes: 120, followUpRepeats: true,
                                          slots: [.midday], askTime: false, breakthrough: .never, liveActivity: .never)
        let plan = ReminderPlanner(calendar: calendar, settings: settings)
            .plan(tasks: [task("a", day: 12, minutes: 14 * 60)], inboxCount: 0, now: date(12, 8))
        let sameDay = taskReminders(plan, "a").filter { calendar.isDate($0.0, inSameDayAs: date(12, 0)) }
        #expect(sameDay.map(\.0) == [date(12, 14), date(12, 16), date(12, 18), date(12, 20)])
        let nextDay = taskReminders(plan, "a").filter { calendar.isDate($0.0, inSameDayAs: date(13, 0)) }
        #expect(nextDay.map(\.0) == [date(13, 12)])
        #expect(plan.filter { $0.taskID == "a" }.allSatisfy { !$0.timeSensitive })
    }

    /// 17 octobre 2026 = samedi : une Normale ne relance qu'à l'heure, une Urgente comme d'habitude.
    @Test func calmWeekends() {
        var settings = ReminderSettings()
        settings.calmWeekends = true
        let plan = ReminderPlanner(calendar: calendar, settings: settings)
            .plan(tasks: [task("n", day: 17, minutes: 15 * 60), task("u", day: 17, minutes: 15 * 60, priority: .urgent)],
                  inboxCount: 0, now: date(16, 8))
        let saturday = { (id: String) in self.taskReminders(plan, id).filter { self.calendar.isDate($0.0, inSameDayAs: self.date(17, 0)) } }
        #expect(saturday("n").map(\.1) == [.due])
        #expect(saturday("u").count > 1)
    }

    /// Un réglage absent (ajouté dans une version suivante) garde sa valeur d'origine.
    @Test func settingsSurviveMissingKeys() throws {
        var settings = ReminderSettings()
        settings.evening = 21 * 60
        settings.urgent.followUpMinutes = 15
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(ReminderSettings.self, from: data) == settings)
        let partial = try JSONDecoder().decode(ReminderSettings.self, from: Data(#"{"evening": 1230}"#.utf8))
        #expect(partial.evening == 1230 && partial.morning == ReminderSettings().morning && partial.low == .defaults(for: .low))
    }

    @Test func taskOverrideBeatsPriority() {
        var t = task("a", day: 12, minutes: 15 * 60)
        t.reminders = ReminderOverride(advance: .minutes(60), followUp: .off)
        let plan = planner.plan(tasks: [t], inboxCount: 0, now: date(12, 8))
        let sameDay = taskReminders(plan, "a").filter { calendar.isDate($0.0, inSameDayAs: date(12, 0)) }
        #expect(sameDay.map(\.1) == [.advance, .due, .evening])
        #expect(sameDay.first?.0 == date(12, 14))
    }

    /// Une tâche relancée toutes les 15 min ne doit pas évincer l'heure prévue d'une autre, dans 3 jours.
    @Test func essentialRemindersSurviveTheLimit() {
        var busy = task("busy", day: 12, minutes: 8 * 60)
        busy.reminders = ReminderOverride(followUp: .every(15))
        let plan = planner.plan(tasks: [busy, task("later", day: 15, minutes: 10 * 60)], inboxCount: 0, now: date(12, 7))
        #expect(plan.count <= ReminderSettings().maxRequests)
        #expect(plan.contains { $0.taskID == "later" && $0.kind == .due })
    }

    // MARK: - Pars maintenant

    /// RDV à 14 h 50, 18 min de trajet, 5 min de marge : départ annoncé à 14 h 27, même en plage silencieuse.
    @Test func departureReminder() {
        var t = task("a", day: 12, minutes: 14 * 60 + 50)
        t.travelMinutes = 18
        let plan = planner.plan(tasks: [t], inboxCount: 0, now: date(12, 8))
        let leave = plan.first { $0.taskID == "a" && $0.kind == .departure }
        #expect(leave?.fireDate == date(12, 14, 27))
        #expect(leave?.timeSensitive == true)
        #expect(leave?.body == "Pars maintenant · 18 min en transports · prévu à 14 h 50.")

        var early = task("b", day: 12, minutes: 7 * 60 + 30)
        early.travelMinutes = 30
        #expect(planner.plan(tasks: [early], inboxCount: 0, now: date(11, 20)).contains { $0.kind == .departure })
    }

    @Test func departureDisabled() {
        var settings = ReminderSettings()
        settings.departure.enabled = false
        var t = task("a", day: 12, minutes: 15 * 60)
        t.travelMinutes = 20
        let plan = ReminderPlanner(calendar: calendar, settings: settings).plan(tasks: [t], inboxCount: 0, now: date(12, 8))
        #expect(!plan.contains { $0.kind == .departure })
    }
}

struct ActivityButtonTests {
    typealias Item = TaskActivityAttributes.ContentState.Item
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func item(dueIn hours: Double, route: Bool = false, hasTime: Bool = true) -> Item {
        Item(id: "a", title: "a", due: now.addingTimeInterval(hours * 3600), hasTime: hasTime,
             routeURL: route ? URL(string: "https://maps.apple.com/?daddr=x") : nil)
    }

    @Test func secondButtonFollowsTheClock() {
        if case .later = item(dueIn: 4).secondAction(at: now) {} else { Issue.record("loin avant : Plus tard") }
        if case .later = item(dueIn: 4, route: true).secondAction(at: now) {} else { Issue.record("loin avant, lieu : Plus tard") }
        if case .route = item(dueIn: 1, route: true).secondAction(at: now) {} else { Issue.record("2 h avant, lieu : Itinéraire") }
        if case .later = item(dueIn: 1).secondAction(at: now) {} else { Issue.record("2 h avant, sans lieu : Plus tard") }
        if case .snooze = item(dueIn: -1).secondAction(at: now) {} else { Issue.record("en retard : Dans 1 h") }
        if case .snooze = item(dueIn: 4, hasTime: false).secondAction(at: now) {} else { Issue.record("sans heure : Dans 1 h") }
    }

    @Test func laterHidesUntilTwoHoursBeforeOrDue() {
        let due = now.addingTimeInterval(5 * 3600)
        #expect(ActivityHiding.laterDate(due: due, now: now) == due.addingTimeInterval(-2 * 3600))
        let soon = now.addingTimeInterval(3600)
        #expect(ActivityHiding.laterDate(due: soon, now: now) == soon)
    }

    @Test func urgentLiveActivityMigratesOnce() throws {
        var old = ReminderSettings()
        old.urgent.liveActivity = .always
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as! [String: Any]
        json.removeValue(forKey: "version")
        let migrated = try JSONDecoder().decode(ReminderSettings.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(migrated.urgent.liveActivity == .upcoming)
        // Choix fait après la migration (version 2) : gardé.
        let kept = try JSONDecoder().decode(ReminderSettings.self, from: JSONEncoder().encode(old))
        #expect(kept.urgent.liveActivity == .always)
    }
}

struct ToSeePlannerTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        return c
    }()
    func date(_ d: Int, _ m: Int, _ h: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: m, day: d, hour: h))!
    }

    @Test func expoRemindersAroundThePeriod() {
        var planner = ReminderPlanner(calendar: calendar)
        planner.settings.horizonDays = 60
        // Fin le dimanche 22/11/2026 : 3 semaines avant = 01/11, dernier week-end = samedi 21/11, à 10 h.
        let expo = PlannableTask(id: "expo", title: "Expo", toSee: ToSee(start: date(20, 10), end: date(22, 11)))
        let plan = planner.plan(tasks: [expo], inboxCount: 0, now: date(13, 10, 12))
        let mine = plan.filter { $0.taskID == "expo" }
        #expect(mine.map(\.fireDate) == [date(20, 10, 10), date(1, 11, 10), date(21, 11, 10)])
        #expect(mine.map(\.kind) == [.toSeeOpening, .toSeeEnding, .toSeeLastWeekend])
        #expect(mine.allSatisfy { $0.subtitle == "À voir" })
        // Sans période : aucune relance.
        #expect(planner.plan(tasks: [PlannableTask(id: "x", title: "x", toSee: ToSee())], inboxCount: 0, now: date(13, 10)).isEmpty)
    }
}

