import Foundation
import Testing
@testable import Relance

struct DueTextTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        c.locale = Locale(identifier: "fr_FR")
        return c
    }()

    func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    @Test func lateSameDayWithTime() {
        #expect(DueText.long(due: date(12, 21), hasTime: true, now: date(12, 23), calendar: calendar) == "En retard · depuis 21 h")
        #expect(DueText.short(due: date(12, 21), hasTime: true, now: date(12, 23), calendar: calendar) == "21 h")
    }

    @Test func lateSinceYesterdayAndDays() {
        #expect(DueText.long(due: date(11, 9, 30), hasTime: true, now: date(12, 8), calendar: calendar) == "En retard · depuis hier")
        #expect(DueText.short(due: date(9, 9), hasTime: true, now: date(12, 8), calendar: calendar) == "3 j")
    }

    /// Une tâche « date seule » du 11 a pour échéance minuit le 12 : en retard depuis hier.
    @Test func dateOnlyLate() {
        #expect(DueText.long(due: date(12, 0), hasTime: false, now: date(12, 8), calendar: calendar) == "En retard · depuis hier")
    }

    @Test func upcoming() {
        #expect(DueText.long(due: date(12, 15), hasTime: true, now: date(12, 8), calendar: calendar) == "Aujourd'hui à 15 h")
        #expect(DueText.long(due: date(13, 9, 30), hasTime: true, now: date(12, 8), calendar: calendar) == "Demain à 9 h 30")
        #expect(DueText.long(due: date(13, 0), hasTime: false, now: date(12, 8), calendar: calendar) == "Aujourd'hui")
        #expect(DueText.short(due: date(13, 11), hasTime: true, now: date(12, 8), calendar: calendar) == "demain")
    }
}
