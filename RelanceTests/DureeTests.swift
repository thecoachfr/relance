import Foundation
import Testing
@testable import Relance

/// Durée facultative d'une tâche (P9-H1).
@MainActor
struct DureeTests {
    @Test func formatEtTache() throws {
        let store = TaskStore(auth: SlowAccount(), inMemory: true)
        let item = store.add(title: "Kiné", day: .now, minutes: 10 * 60)
        store.setDuree(45, of: item)
        let tache = TacheHA(item)
        #expect(tache.duree == 45)
        let json = String(decoding: try JSONEncoder().encode(tache), as: UTF8.self)
        #expect(json.contains("\"duree\":45") && json.contains("\"v\":2"))
        let autre = TaskItem(title: "")
        try JSONDecoder().decode(TacheHA.self, from: Data(json.utf8)).apply(to: autre)
        #expect(autre.dureeMinutes == 45)
        #expect(CalendarLink.duration(of: autre) == 45 * 60)
        // Sans heure, pas de durée envoyée.
        item.dueMinutes = nil
        #expect(TacheHA(item).duree == nil)
        store.setDuree(0, of: item)
        #expect(item.dureeMinutes == nil && CalendarLink.duration(of: item) == 3600)
    }

    @Test func texte() {
        #expect(DureeRow.texte(45) == "45 min")
        #expect(DureeRow.texte(90) == "1 h 30")
        #expect(DureeRow.texte(120) == "2 h")
        #expect(DureeRow.texte(255) == "4 h 15")
    }
}
