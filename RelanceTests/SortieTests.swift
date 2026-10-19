import Foundation
import Testing
@testable import Relance

/// Sorties réservées (P9-L1) : envie datée par l'échéance, rappels une semaine avant, la veille et 2 h avant,
/// jamais en retard, rangée À venir / Passées.
@MainActor
struct SortieTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        return c
    }()

    func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    func sortie(_ id: String, day: Int?, minutes: Int? = nil, image: String? = nil) -> PlannableTask {
        PlannableTask(id: id, title: id, dueDay: day.map { DateComponents(year: 2026, month: 10, day: $0) },
                      dueMinutes: minutes, toSee: ToSee(.event), imageID: image)
    }

    @Test func markerAndHAType() {
        #expect(ToSee(.event).lines == ["🎟 Sortie"])
        #expect(ToSee(notes: "Billet en PDF\n🎟\u{FE0F} Sortie")?.kind == .event)
        #expect(ToSee.Kind.event.haType == "sortie")
        #expect(ToSee.Kind(haType: "sortie") == .event)
        #expect(ToSee.Kind.event.isDated && !ToSee.Kind.outing.isDated)
        #expect(ToSee.Kind.event.doneTitle == "Vu")
    }

    @Test func remindersWeekEveAndTwoHoursBefore() {
        // Horizon de 8 jours : la semaine avant et les 2 h avant dans le même plan.
        var settings = ReminderSettings()
        settings.horizonDays = 8
        let plan = ReminderPlanner(calendar: calendar, settings: settings)
            .plan(tasks: [sortie("concert", day: 25, minutes: 20 * 60, image: "abc")], inboxCount: 0, now: date(18, 8))
        let mine = plan.filter { $0.taskID == "concert" }
        #expect(mine.map(\.kind) == [.eventWeek, .eventEve, .eventSoon])
        #expect(mine.map(\.fireDate) == [date(18, 10), date(24, 20), date(25, 18)])
        #expect(mine[1].body == "Demain à 20 h.")
        // Le billet (image) seulement 2 h avant ; pas de relance ni de retard.
        #expect(mine.map(\.imageID) == [nil, nil, "abc"])
        #expect(!plan.contains { $0.taskID == "concert" && [.due, .followUp, .overdue, .evening].contains($0.kind) })
    }

    @Test func withoutTimeTheMorningOfTheDay() {
        let plan = ReminderPlanner(calendar: calendar)
            .plan(tasks: [sortie("expo", day: 20)], inboxCount: 0, now: date(18, 8))
        #expect(plan.filter { $0.taskID == "expo" }.map(\.fireDate) == [date(19, 20), date(20, 7, 30)])
        // Sans date : aucun rappel.
        #expect(ReminderPlanner(calendar: calendar)
            .plan(tasks: [sortie("plus tard", day: nil)], inboxCount: 0, now: date(18, 8)).isEmpty)
    }

    @Test func neverOverdue() {
        let past = sortie("passé", day: 10, minutes: 20 * 60)
        #expect(!ReminderPlanner(calendar: calendar).isOverdue(past, at: date(18, 8)))
        let item = TaskItem(title: "Spectacle", notes: ToSee(.event).lines.joined(), dueDay: date(10, 0), dueMinutes: 20 * 60)
        #expect(!item.isOverdue(now: date(18, 8), calendar: calendar))
        let task = TaskItem(title: "Facture", dueDay: date(10, 0), dueMinutes: 20 * 60)
        #expect(task.isOverdue(now: date(18, 8), calendar: calendar))
    }

    @Test func groupedUpcomingUndatedPast() {
        let notes = ToSee(.event).lines.joined()
        let soon = TaskItem(title: "Bientôt", notes: notes, dueDay: date(20, 0), dueMinutes: 20 * 60)
        let later = TaskItem(title: "Plus tard", notes: notes, dueDay: date(30, 0), dueMinutes: 21 * 60)
        let undated = TaskItem(title: "Sans date", notes: notes)
        let past = TaskItem(title: "Passée", notes: notes, dueDay: date(12, 0), dueMinutes: 20 * 60)
        let other = TaskItem(title: "Expo", notes: ToSee(.outing).lines.joined())
        let groups = ToSeeListView.groups([later, past, other, undated, soon], kind: .event, now: date(18, 8))
        #expect(groups.map(\.title) == ["À venir", "Date à préciser", "Passées"])
        #expect(groups[0].items.map(\.title) == ["Bientôt", "Plus tard"])
        #expect(groups[2].items.map(\.title) == ["Passée"])
        // « Tout » : les sorties à venir seulement, avec les autres types.
        let all = ToSeeListView.groups([later, past, other, soon], now: date(18, 8))
        #expect(all.first { $0.title == "Sorties" }?.items.map(\.title) == ["Bientôt", "Plus tard"])
    }
}
