import Foundation
import Testing
@testable import Relance

/// Reste du lot N2 (28/10/2026) : pastille du lieu par jour, libellé de la complication, contexte du jour en tête
/// du résumé du matin, un seul essai pour l'activité en direct, liens profonds `relance://`.
@MainActor
struct ResteN2Tests {
    static let paris = LieuTravailTests.paris

    static var lieu: LieuTravail { LieuTravail(etatHA: LieuTravailTests.reponse)! }

    static func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        paris.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    // MARK: - Pastille du lieu par jour

    @Test func pastilleOnlyOnWorkedDays() {
        let lieu = Self.lieu
        #expect(lieu.pastille(Self.date(26, 9), calendar: Self.paris) == "🏢 Bureau")
        #expect(lieu.pastille(Self.date(27), calendar: Self.paris) == "🏠 Télétravail")
        #expect(lieu.pastille(Self.date(28), calendar: Self.paris) == "🏢 Bureau ?")
        #expect(lieu.pastille(Self.date(29), calendar: Self.paris) == "🧪 Le Lab")
        // Repos, férié, jour hors des jours publiés, tâche sans date : rien.
        #expect(lieu.pastille(Self.date(24), calendar: Self.paris) == nil)
        #expect(lieu.pastille(Self.date(25), calendar: Self.paris) == nil)
        #expect(lieu.pastille(Self.date(31), calendar: Self.paris) == nil)
        #expect(lieu.pastille(nil, calendar: Self.paris) == nil)
        let toussaint = Self.paris.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        #expect(lieu.pastille(toussaint, calendar: Self.paris) == nil)
    }

    // MARK: - Complication de la montre

    @Test func complicationShowsOnlyWorkedDays() {
        let lieux = WatchLink.decodeLieux(Self.lieu.pourLaMontre)
        #expect(lieux == ["2026-10-26": "🏢 Bureau", "2026-10-27": "🏠 Télétravail", "2026-10-28": "🏢 Bureau ?",
                          "2026-10-29": "🧪 Le Lab"])
        #expect(WatchLink.libelleDuJour(lieux, date: Self.date(27, 7), calendar: Self.paris) == "🏠 Télétravail")
        #expect(WatchLink.libelleDuJour(lieux, date: Self.date(24, 12), calendar: Self.paris) == nil)
        #expect(WatchLink.libelleDuJour([:], date: Self.date(27, 7), calendar: Self.paris) == nil)
    }

    @Test func complicationTimelineChangesAtMidnight() {
        let debut = Self.date(26, 22, 30)
        #expect(WatchLink.minuits(apres: debut, jusqua: debut.addingTimeInterval(24 * 3600), calendar: Self.paris)
                == [Self.date(27)])
        #expect(WatchLink.minuits(apres: Self.date(26, 1), jusqua: Self.date(26, 23), calendar: Self.paris).isEmpty)
        #expect(WatchLink.minuits(apres: Self.date(26, 1), jusqua: Self.date(28), calendar: Self.paris)
                == [Self.date(27), Self.date(28)])
    }

    // MARK: - Relance du matin : contexte du jour en tête

    func tache(_ titre: String, day: Int?, contexte: ContexteTache?, minutes: Int? = nil,
               priority: TaskPriority = .normal) -> PlannableTask {
        PlannableTask(id: titre, title: titre, dueDay: day.map { DateComponents(year: 2026, month: 10, day: $0) },
                      dueMinutes: minutes, priority: priority, contexte: contexte)
    }

    func matin(_ taches: [PlannableTask], lieux: [String: String], now: Date, jour: Int) -> PlannedReminder? {
        let planner = ReminderPlanner(calendar: Self.paris, lieuxDuJour: lieux)
        return planner.plan(tasks: taches, inboxCount: 0, now: now)
            .first { $0.kind == .digest && $0.title == "Ta journée" && Self.paris.isDate($0.fireDate, inSameDayAs: Self.date(jour)) }
    }

    @Test func officeTasksLeadTheMorningDigestOnAnOfficeDay() throws {
        let lieux = Self.lieu.lieuxParDate
        let taches = [tache("Courses", day: 26, contexte: nil),
                      tache("Rendre le badge", day: 26, contexte: .bureau, minutes: 11 * 60),
                      tache("Imprimer le bail", day: nil, contexte: .bureau),
                      tache("Signer le contrat", day: 26, contexte: .bureau, priority: .urgent),
                      tache("Arroser les plantes", day: 26, contexte: .maison)]
        let lundi = try #require(matin(taches, lieux: lieux, now: Self.date(25, 20), jour: 26))
        // L'urgent d'abord, puis par échéance ; sans date en dernier ; « À la maison » absent un jour de bureau.
        #expect(lundi.body == "🏢 Au bureau : Signer le contrat, Rendre le badge… · 4 aujourd'hui")
    }

    @Test func homeTasksLeadOnRemoteAndRestDays() throws {
        let lieux = Self.lieu.lieuxParDate
        let taches = [tache("Arroser les plantes", day: 27, contexte: .maison),
                      tache("Rendre le badge", day: 27, contexte: .bureau)]
        let mardi = try #require(matin(taches, lieux: lieux, now: Self.date(26, 20), jour: 27))
        #expect(mardi.body == "🏠 À la maison : Arroser les plantes · 2 aujourd'hui")
        // Dimanche (repos) : une tâche « à la maison » sans date suffit à envoyer le résumé.
        let dimanche = try #require(matin([tache("Ranger la cave", day: nil, contexte: .maison)], lieux: lieux,
                                         now: Self.date(24, 20), jour: 25))
        #expect(dimanche.body == "🏠 À la maison : Ranger la cave")
    }

    @Test func noLeadWithoutTheSensor() throws {
        let taches = [tache("Rendre le badge", day: 26, contexte: .bureau)]
        let lundi = try #require(matin(taches, lieux: [:], now: Self.date(25, 20), jour: 26))
        #expect(lundi.body == "1 aujourd'hui")
        // Le Lab n'est ni le bureau ni la maison : pas de tête.
        let jeudi = try #require(matin([tache("Rendre le badge", day: 29, contexte: .bureau)],
                                       lieux: Self.lieu.lieuxParDate, now: Self.date(28, 20), jour: 29))
        #expect(jeudi.body == "1 aujourd'hui")
    }

    // MARK: - Activité en direct : un seul essai

    @Test func liveActivityTriesOnceAndOnlyInForeground() {
        var demarrage = DemarrageActivite()
        // En arrière-plan (synchro à 7 h 00) : jamais d'essai, autant de fois que ce soit.
        var essais = 0
        for _ in 0..<8 where demarrage.autoriser(auPremierPlan: false) { essais += 1 }
        #expect(essais == 0)
        // Au premier plan : un essai, puis plus rien jusqu'au prochain retour au premier plan.
        let premier = demarrage.autoriser(auPremierPlan: true)
        let second = demarrage.autoriser(auPremierPlan: true)
        #expect(premier && !second)
        demarrage.reinitialiser()
        let apresRetour = demarrage.autoriser(auPremierPlan: true)
        #expect(apresRetour)
    }

    // MARK: - Liens profonds

    @Test func parsesDeepLinks() {
        let cle = "3f2a8c1e-0b6d-4e5f-9a7b-1c2d3e4f5a6b"
        #expect(LienAiguillage(url: URL(string: "relance://tache/\(cle)")!) == .tache(cle))
        #expect(LienAiguillage(url: URL(string: "relance://memo/abc123")!) == .memo("abc123"))
        #expect(LienAiguillage(url: URL(string: "relance://memo/Dentiste%20Dupont")!) == .memo("Dentiste Dupont"))
        #expect(LienAiguillage(url: URL(string: "relance://nouvelle")!) == .nouvelle)
        #expect(LienAiguillage(url: URL(string: "RELANCE://TACHE/x")!) == .tache("x"))
        for faux in ["relance://tache", "relance://tache/", "relance://inconnu/x", "https://tache/x",
                     "com.googleusercontent.apps.123:/oauth"] {
            #expect(LienAiguillage(url: URL(string: faux)!) == nil, "\(faux)")
        }
        // Aller-retour : le lien fabriqué se relit à l'identique.
        for lien in [LienAiguillage.tache(cle), .memo("Fiche / avec espace"), .nouvelle] {
            #expect(LienAiguillage(url: lien.url) == lien)
        }
    }

    @Test func routesLinksToTasksAndMemo() {
        let id = UUID()
        let item = TaskItem(title: "Rendre le badge", notes: "", dueDay: nil, dueMinutes: nil)
        item.localID = id
        item.googleID = "g-42"
        let local: (UUID) -> TaskItem? = { $0 == id ? item : nil }
        let google: (String) -> TaskItem? = { $0 == "g-42" ? item : nil }
        #expect(LienAiguillage.tache(id.uuidString.lowercased(), local: local, google: google) === item)
        #expect(LienAiguillage.tache("g-42", local: local, google: google) === item)
        #expect(LienAiguillage.tache(UUID().uuidString, local: local, google: google) == nil)

        let fiches = [MemoEntry(id: "a1", title: "Dentiste", details: ""), MemoEntry(id: "b2", title: "Élodie", details: "")]
        #expect(LienAiguillage.fiche("b2", dans: fiches)?.title == "Élodie")
        #expect(LienAiguillage.fiche("elodie", dans: fiches)?.id == "b2")
        #expect(LienAiguillage.fiche("zz", dans: fiches) == nil)
    }
}
