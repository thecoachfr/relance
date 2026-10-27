import Foundation
import Testing
@testable import Relance

/// Rappels « pour info » (P9-P) : marqueur, jours où ils tombent, avancée, résumé du matin.
@MainActor
struct PourInfoTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        c.firstWeekday = 2
        return c
    }()

    /// Octobre 2026 : le 12, le 19 et le 26 sont des lundis.
    func day(_ d: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: d, hour: hour, minute: minute))!
    }

    let lundi = Recurrence.weekly(every: 1, weekdays: [2])

    @Test func markerRoundTripAndHidden() {
        let notes = PourInfo.notes("Clés sous le paillasson", actif: true)
        #expect(notes == "Clés sous le paillasson\n📣 Pour info")
        #expect(PourInfo.est(notes))
        #expect(PourInfo.est("📣\u{FE0F} Pour info"))
        #expect(NoteLines.visible(notes) == "Clés sous le paillasson")
        #expect(PourInfo.notes(notes, actif: false) == "Clés sous le paillasson")
        #expect(PourInfo.notes(notes, actif: true) == notes)
    }

    @Test func fallsOnItsDayOrOnARepeatAfterIt() {
        #expect(PourInfo.tombe(le: day(19, 9), echeance: day(19), repetition: nil, calendar: calendar))
        #expect(!PourInfo.tombe(le: day(20), echeance: day(19), repetition: nil, calendar: calendar))
        // Pas encore avancée (l'app n'a pas tourné) : le lundi suivant reste juste.
        #expect(PourInfo.tombe(le: day(26), echeance: day(12), repetition: lundi, calendar: calendar))
        #expect(!PourInfo.tombe(le: day(27), echeance: day(12), repetition: lundi, calendar: calendar))
        #expect(!PourInfo.tombe(le: day(5), echeance: day(12), repetition: lundi, calendar: calendar))
        #expect(PourInfo.jours(echeance: day(19), repetition: lundi, debut: day(20, 8), nombre: 9, calendar: calendar)
                == [day(26)])
    }

    @Test func pastInfoMovesOnOrIsPutAway() {
        #expect(PourInfo.suite(echeance: day(26), repetition: lundi, aujourdhui: day(26, 22), calendar: calendar) == .inchangee)
        #expect(PourInfo.suite(echeance: day(19), repetition: lundi, aujourdhui: day(26, 6), calendar: calendar) == .avancee(day(26)))
        #expect(PourInfo.suite(echeance: day(19), repetition: lundi, aujourdhui: day(27, 6), calendar: calendar)
                == .avancee(calendar.date(byAdding: .day, value: 7, to: day(26))!))
        #expect(PourInfo.suite(echeance: day(19), repetition: nil, aujourdhui: day(20), calendar: calendar) == .rangee)
    }

    @Test func taskItemIsNeverOverdueNorToTriage() {
        let item = TaskItem(title: "Femme de ménage", notes: PourInfo.notes(lundi.line, actif: true), dueDay: day(19))
        #expect(item.estPourInfo)
        #expect(!item.isOverdue(now: day(26, 12), calendar: calendar))
        #expect(!item.needsTriage(now: day(19, 12), calendar: calendar))
        #expect(item.pourInfoDuJour(now: day(26, 12), calendar: calendar))
        #expect(!item.pourInfoDuJour(now: day(27, 12), calendar: calendar))
    }

    // MARK: - Planificateur

    var planner: ReminderPlanner { ReminderPlanner(calendar: calendar) }

    func info(_ title: String, jours: [Date]) -> PlannableTask {
        PlannableTask(id: title, title: title, dueDay: calendar.dateComponents([.year, .month, .day], from: jours[0]),
                      dueMinutes: nil, snoozedUntil: nil, pourInfo: jours)
    }

    @Test func noReminderOnlyTheMorningDigest() {
        let tasks = [info("Femme de ménage", jours: [day(27)]), info("Poubelles", jours: [day(27)])]
        let plan = planner.plan(tasks: tasks, inboxCount: 0, now: day(26, 21, 30))
        #expect(plan.allSatisfy { $0.taskID == nil })
        let digest = plan.first { $0.kind == .digest && $0.title == "Ta journée" }!
        #expect(digest.fireDate == day(27, 7, 30))
        #expect(digest.body == "Pour info : Femme de ménage, Poubelles")
        #expect(digest.badge == 0)
    }

    @Test func digestListsTwoNamesThenEllipsisAfterTheTasks() {
        var a = PlannableTask(id: "a", title: "a", dueDay: DateComponents(year: 2026, month: 10, day: 27), dueMinutes: 14 * 60,
                              snoozedUntil: nil)
        a.priority = .normal
        let tasks = [a, info("Femme de ménage", jours: [day(27)]), info("Poubelles", jours: [day(27)]),
                     info("Marché", jours: [day(27)])]
        let plan = planner.plan(tasks: tasks, inboxCount: 0, now: day(26, 21, 30))
        let digest = plan.first { $0.kind == .digest && $0.title == "Ta journée" }!
        #expect(digest.body == "1 aujourd'hui · Pour info : Femme de ménage, Marché…")
    }

    /// Une info peut avoir une heure (27/10) : nommée avec elle, en premier, toujours sans relance.
    @Test func timedInfoIsNamedWithItsTimeAndNeverReminded() {
        var sport = info("Sport", jours: [day(27)])
        sport.dueMinutes = 7 * 60 + 30
        let plan = planner.plan(tasks: [info("Poubelles", jours: [day(27)]), sport], inboxCount: 0, now: day(26, 21, 30))
        #expect(plan.allSatisfy { $0.taskID == nil })
        let digest = plan.first { $0.kind == .digest && $0.title == "Ta journée" }!
        #expect(digest.body == "Pour info : Sport à 7 h 30, Poubelles")
        let item = TaskItem(title: "Sport", notes: PourInfo.ligne, dueDay: day(27), dueMinutes: 7 * 60 + 30)
        #expect(!item.isOverdue(now: day(27, 22), calendar: calendar))
        #expect(item.heurePourInfo == "7 h 30")
    }

    @Test func eveningDigestIgnoresInfos() {
        let plan = planner.plan(tasks: [info("Poubelles", jours: [day(27)])], inboxCount: 0, now: day(26, 18))
        #expect(!plan.contains { $0.title == "Demain" })
    }
}
