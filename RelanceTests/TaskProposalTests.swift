import Foundation
import Testing
@testable import Relance

/// Tâche proposée par le tri d'un message partagé (ligne « ➕ »), créée d'un toucher dans la fiche.
@MainActor
struct TaskProposalTests {
    let calendar = Calendar.current
    func day(_ d: Int, _ m: Int, _ y: Int) -> Date { calendar.date(from: DateComponents(year: y, month: m, day: d))! }

    /// Cas réel du 16/10 : mail du centre de services, intervenante le lundi à 9 h 30.
    let notes = """
        📩 Message partagé
        Par la suite, elle interviendra les lundis à 9h30.
        ➕ Proposition : Intervenante ménage · 09:30 · 🔄 Toutes les semaines : lundi
        """

    @Test func parsesLine() {
        let p = TaskProposal(notes: notes)
        #expect(p?.title == "Intervenante ménage")
        #expect(p?.minutes == 9 * 60 + 30)
        #expect(p?.recurrence == .weekly(every: 1, weekdays: [2]))
        #expect(p?.day == nil)
        // Vendredi 16/10 → lundi 19/10 ; un lundi → le jour même.
        #expect(p?.startDay(today: day(16, 10, 2026)) == day(19, 10, 2026))
        #expect(p?.startDay(today: day(19, 10, 2026)) == day(19, 10, 2026))
        #expect(p?.notes == "🔄 Toutes les semaines : lundi")
        #expect(NoteLines.visible(notes) == "Par la suite, elle interviendra les lundis à 9h30.")

        let dated = TaskProposal(line: "➕ Proposition : Rappeler le centre · 2026-10-26 · 14h00")
        #expect(dated?.day == day(26, 10, 2026) && dated?.minutes == 14 * 60 && dated?.recurrence == nil)
        // Langue du simulateur : on vérifie seulement le jour et l'heure.
        let summary = dated?.summary(today: day(16, 10, 2026)) ?? ""
        #expect(summary.contains("26") && summary.hasSuffix("à 14:00"))
        #expect(TaskProposal(line: "➕ Proposition : Sans rien")?.startDay() == nil)
        #expect(TaskProposal(line: "➕ Proposition :  ") == nil)
        #expect(TaskProposal(notes: "💡 Suggestion : jeudi") == nil)
    }

    @Test func removesLine() {
        #expect(TaskProposal.removing(from: notes) == "📩 Message partagé\nPar la suite, elle interviendra les lundis à 9h30.")
        #expect(TaskProposal.removing(from: "rien") == "rien")
    }

    @Test func createsTask() {
        let store = TaskStore(auth: SlowAccount(), inMemory: true)
        let item = store.add(title: "Accueillir l'intervenante ménage", day: nil, minutes: nil, category: "Maison", notes: notes)
        let created = store.resolveProposal(of: item, create: true)
        #expect(created?.title == "Intervenante ménage")
        #expect(created?.category == "Maison")
        #expect(created?.dueMinutes == 9 * 60 + 30)
        #expect(created.flatMap { Recurrence(notes: $0.notes) } == .weekly(every: 1, weekdays: [2]))
        #expect(created?.dueDay.map { calendar.component(.weekday, from: $0) } == 2)
        #expect(TaskProposal(notes: item.notes) == nil)
        // Plus de proposition : rien de plus.
        #expect(store.resolveProposal(of: item, create: true) == nil)
    }

    @Test func ignoresProposal() {
        let store = TaskStore(auth: SlowAccount(), inMemory: true)
        let item = store.add(title: "Accueillir", day: nil, minutes: nil, notes: notes)
        #expect(store.resolveProposal(of: item, create: false) == nil)
        #expect(!item.notes.contains("➕"))
    }
}
