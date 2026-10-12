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
}
