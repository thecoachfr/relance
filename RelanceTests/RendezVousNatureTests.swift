import Foundation
import Testing
@testable import Relance

/// Nature « Rendez-vous » (P9-T) : marqueur, jamais en retard, rappels avant, résumés, passage.
@MainActor
struct RendezVousNatureTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        c.firstWeekday = 2
        return c
    }()

    /// Octobre 2026 : le 12, le 19 et le 26 sont des lundis.
    func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    func rdv(_ id: String, day: Int?, minutes: Int? = nil, repete: Bool = false,
             reminders: ReminderOverride? = nil, travel: Int? = nil) -> PlannableTask {
        PlannableTask(id: id, title: id, dueDay: day.map { DateComponents(year: 2026, month: 10, day: $0) },
                      dueMinutes: minutes, reminders: reminders, travelMinutes: travel,
                      rendezVous: day.map { [date($0)] } ?? [], rendezVousRepete: repete)
    }

    func plan(_ tasks: [PlannableTask], now: Date, settings: ReminderSettings = ReminderSettings()) -> [PlannedReminder] {
        ReminderPlanner(calendar: calendar, settings: settings).plan(tasks: tasks, inboxCount: 0, now: now)
    }

    @Test func markerRoundTripAndHidden() {
        let notes = RendezVous.notes("Apporter la radio", actif: true)
        #expect(notes == "Apporter la radio\n📌 Rendez-vous")
        #expect(RendezVous.est(notes) && RendezVous.est("📌\u{FE0F} Rendez-vous"))
        #expect(NoteLines.visible(notes) == "Apporter la radio")
        #expect(RendezVous.notes(notes, actif: false) == "Apporter la radio")
        #expect(RendezVous.notes(notes, actif: true) == notes)
        #expect(RendezVous.notes("", actif: true) == RendezVous.ligne)
    }

    @Test func neverLateNeverInTriage() {
        let item = TaskItem(title: "Dentiste", notes: RendezVous.ligne, dueDay: date(19), dueMinutes: 14 * 60)
        #expect(!item.isOverdue(now: date(25), calendar: calendar))
        #expect(item.aHoraireFixe)
        let sansHeure = TaskItem(title: "Expertise", notes: RendezVous.ligne, dueDay: date(19))
        #expect(!sansHeure.needsTriage(now: date(19, 8), calendar: calendar))
        // Sans date, il reste visible dans À trier.
        #expect(TaskItem(title: "Dîner", notes: RendezVous.ligne).needsTriage(now: date(19, 8), calendar: calendar))
        // Une sortie aussi a un horaire fixe ; pas une tâche ordinaire.
        #expect(TaskItem(title: "Concert", notes: "🎟 Sortie", dueDay: date(19)).aHoraireFixe)
        #expect(!TaskItem(title: "Appeler", dueDay: date(19)).aHoraireFixe)
    }

    @Test func eveAndTwoHoursBeforeNothingAfter() {
        let mine = plan([rdv("dentiste", day: 20, minutes: 14 * 60)], now: date(18, 8)).filter { $0.taskID == "dentiste" }
        #expect(mine.map(\.kind) == [.eventEve, .eventSoon])
        #expect(mine.map(\.fireDate) == [date(19, 20), date(20, 12)])
        #expect(mine.map(\.body) == ["Demain à 14 h.", "Dans 2 h à 14 h."])
        #expect(mine.allSatisfy { $0.subtitle == PlannedReminder.sousTitreRendezVous })
        // Pas de billet, pas de rappel une semaine avant.
        var large = ReminderSettings()
        large.horizonDays = 8
        #expect(plan([rdv("dentiste", day: 25, minutes: 14 * 60)], now: date(18, 8), settings: large)
            .filter { $0.taskID == "dentiste" }.map(\.kind) == [.eventEve, .eventSoon])
    }

    @Test func withoutTimeTheMorningOfTheDay() {
        let mine = plan([rdv("expertise", day: 20)], now: date(18, 8)).filter { $0.taskID == "expertise" }
        #expect(mine.map(\.kind) == [.eventEve, .eventSoon])
        #expect(mine.last?.fireDate == date(20, 7, 30))
        #expect(mine.last?.body == "Aujourd'hui.")
    }

    @Test func departureAndAdvanceAddUp() {
        var prevenir = ReminderOverride()
        prevenir.advance = .minutes(30)
        let mine = plan([rdv("dentiste", day: 20, minutes: 14 * 60, reminders: prevenir, travel: 20)], now: date(18, 8))
            .filter { $0.taskID == "dentiste" }
        #expect(Set(mine.map(\.kind)) == [.eventEve, .eventSoon, .advance, .departure])
        #expect(mine.first { $0.kind == .advance }?.fireDate == date(20, 13, 30))
    }

    @Test func aFollowUpOverrideNeverRemindsAfterwards() {
        var relance = ReminderOverride()
        relance.followUp = .every(30)
        #expect(!plan([rdv("dentiste", day: 20, minutes: 14 * 60, reminders: relance)], now: date(18, 8))
            .contains { $0.taskID == "dentiste" && [.due, .followUp, .evening, .overdue, .askTime].contains($0.kind) })
    }

    @Test func recurringOnlyGetsItsAdvance() {
        #expect(!plan([rdv("sport", day: 20, minutes: 7 * 60 + 30, repete: true, travel: 10)], now: date(18, 8))
            .contains { $0.taskID == "sport" })
        var prevenir = ReminderOverride()
        prevenir.advance = .minutes(60)
        #expect(plan([rdv("kiné", day: 20, minutes: 18 * 60, repete: true, reminders: prevenir)], now: date(18, 8))
            .filter { $0.taskID == "kiné" }.map(\.kind) == [.advance])
    }

    @Test func justAfterMidnightDoesNotCrash() {
        // 2 h avant 1 h du matin tombe la veille ; même chose pour une sortie.
        #expect(plan([rdv("vol", day: 20, minutes: 60)], now: date(18, 8)).contains { $0.taskID == "vol" })
        let sortie = PlannableTask(id: "club", title: "club", dueDay: DateComponents(year: 2026, month: 10, day: 20),
                                   dueMinutes: 60, toSee: ToSee(.event))
        #expect(plan([sortie], now: date(18, 8)).contains { $0.taskID == "club" })
    }

    @Test func morningDigestNamesThem() {
        let digest = plan([rdv("Dentiste", day: 20, minutes: 14 * 60), rdv("Sport", day: 20, minutes: 7 * 60, repete: true)],
                          now: date(19, 21, 30))
            .first { $0.kind == .digest && $0.fireDate == date(20, 7, 30) }
        #expect(digest?.body == "Rendez-vous : Sport à 7 h, Dentiste à 14 h")
    }

    @Test func noEveningDigestForThem() {
        #expect(!plan([rdv("Dentiste", day: 20, minutes: 14 * 60)], now: date(19, 8))
            .contains { $0.kind == .digest && $0.title == "Demain" })
    }

    @Test func plannableCarriesTheDays() {
        let lundi = Recurrence.weekly(every: 1, weekdays: [2])
        let simple = TaskItem(title: "Dentiste", notes: RendezVous.ligne, dueDay: date(20))
            .plannable(calendar: calendar, now: date(19, 8))
        #expect(simple.rendezVous == [date(20)] && !simple.rendezVousRepete && simple.pourInfo == nil)
        let repete = TaskItem(title: "Kiné", notes: lundi.line + "\n" + RendezVous.ligne, dueDay: date(19))
            .plannable(calendar: calendar, now: date(19, 8))
        #expect(repete.rendezVous == [date(19), date(26)] && repete.rendezVousRepete)
        #expect(TaskItem(title: "Appeler").plannable(calendar: calendar).rendezVous == nil)
    }

    @Test func pastOnesAreFiledOrAdvanced() {
        let store = TaskStore(auth: SlowAccount(), inMemory: true)
        let hier = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: .now))!
        let passe = store.add(title: "Dentiste", day: hier, minutes: 14 * 60)
        passe.notes = RendezVous.ligne
        let tache = store.add(title: "Appeler", day: hier, minutes: 14 * 60)
        let repete = store.add(title: "Kiné", day: hier, minutes: 18 * 60)
        repete.notes = Recurrence.weekly(every: 1, weekdays: [1, 2, 3, 4, 5, 6, 7]).line + "\n" + RendezVous.ligne
        #expect(store.avancerPasses())
        #expect(passe.isCompleted && !tache.isCompleted && !repete.isCompleted)
        #expect(repete.dueDay == Calendar.current.startOfDay(for: .now))
        #expect(!store.avancerPasses())
    }
}

/// Sélecteur de nature, notifications, widgets et montre (P9-T, R2).
@MainActor
struct RendezVousEcransTests {
    @Test func natureRoundTrip() {
        #expect(NatureTache(notes: RendezVous.ligne) == .rendezVous)
        #expect(NatureTache.allCases.map(\.rawValue) == ["Tâche", "Rendez-vous", "Info", "Envie"])
        // D'une nature à l'autre, une seule ligne reste et le texte ne bouge pas.
        var notes = "Apporter la radio"
        for nature in [NatureTache.rendezVous, .info, .rendezVous, .envie, .rendezVous, .tache] {
            notes = nature.notes(notes)
            #expect(NatureTache(notes: notes) == nature)
            #expect(NoteLines.visible(notes) == "Apporter la radio")
        }
        #expect(notes == "Apporter la radio")
        #expect(NatureTache.rendezVous.explication?.isEmpty == false)
    }

    @Test func notificationsHaveNothingToTick() {
        func rappel(_ kind: ReminderKind, subtitle: String, hasPlace: Bool) -> PlannedReminder {
            PlannedReminder(id: "x", taskID: "t", fireDate: .now, kind: kind, title: "t", body: "", timeSensitive: false,
                            badge: 0, subtitle: subtitle, hasPlace: hasPlace)
        }
        for kind in [ReminderKind.eventEve, .eventSoon, .advance, .departure] {
            #expect(ReminderScheduler.categorie(of: rappel(kind, subtitle: PlannedReminder.sousTitreRendezVous, hasPlace: true))
                    == ReminderScheduler.Category.rendezVous)
            #expect(ReminderScheduler.categorie(of: rappel(kind, subtitle: PlannedReminder.sousTitreRendezVous, hasPlace: false))
                    == ReminderScheduler.Category.digest)
        }
        // Une sortie et une tâche gardent Fait.
        #expect(ReminderScheduler.categorie(of: rappel(.eventSoon, subtitle: "Sorties", hasPlace: false)) == ReminderScheduler.Category.early)
        #expect(ReminderScheduler.categorie(of: rappel(.due, subtitle: "", hasPlace: false)) == ReminderScheduler.Category.task)
    }

    @Test func widgetNeverLateAndDropsPastOnes() {
        let now = Date.now
        let demain = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))!
        let hier = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: now))!
        let items = [TaskItem(title: "Dentiste", notes: RendezVous.ligne, dueDay: demain, dueMinutes: 14 * 60),
                     TaskItem(title: "Passé", notes: RendezVous.ligne, dueDay: hier, dueMinutes: 14 * 60),
                     TaskItem(title: "Appeler", dueDay: hier, dueMinutes: 14 * 60)]
        let widgets = WidgetTask.depuis(items, now: now)
        #expect(widgets.map(\.title) == ["Dentiste", "Appeler"])
        #expect(widgets[0].rendezVous && !widgets[0].enRetard(at: now.addingTimeInterval(3 * 86400)))
        #expect(widgets[1].enRetard(at: now))
    }

    @Test func watchNeverLate() throws {
        let hier = Date.now.addingTimeInterval(-86400)
        var task = WatchTask(id: "1", title: "Dentiste", due: hier, hasTime: true)
        #expect(task.isLate(at: .now))
        task.rendezVous = true
        #expect(!task.isLate(at: .now))
        // Une ancienne version de l'iPhone n'envoie pas le champ.
        let ancien = try JSONDecoder().decode(WatchTask.self, from: Data(#"{"id":"1","title":"t","hasTime":false}"#.utf8))
        #expect(ancien.rendezVous == nil)
    }

    @Test func pastTextNeverSaysLate() {
        let item = TaskItem(title: "Dentiste", notes: RendezVous.ligne, dueDay: Date.now.addingTimeInterval(-3 * 86400), dueMinutes: 9 * 60)
        #expect(item.jamaisEnRetard)
        #expect(!DueText.long(due: item.dueInstant()!, hasTime: true, jamaisEnRetard: item.jamaisEnRetard).hasPrefix("En retard"))
    }
}
