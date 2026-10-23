import Foundation
import Testing
@testable import Relance

/// Relances : on ne repose que ce qui change, on retire ce qui n'est plus prévu.
struct DiffRelancesTests {
    func relance(_ id: String, _ titre: String = "Appeler", dans minutes: Double = 60) -> PlannedReminder {
        PlannedReminder(id: id, taskID: "t", fireDate: Date(timeIntervalSince1970: 1_800_000_000 + minutes * 60),
                        kind: .due, title: titre, body: "", timeSensitive: false, badge: 0)
    }

    @Test func rienNeChangeRienAPoser() {
        let a = relance("a"), b = relance("b")
        let d = DiffRelances.calculer(voulues: [a, b], enAttente: ["a", "b"], posees: ["a": a, "b": b])
        #expect(d.aPoser.isEmpty)
        #expect(d.aRetirer.isEmpty)
        #expect(d.inchangees.count == 2)
    }

    @Test func nouvelleModifieeEtRetiree() {
        let a = relance("a"), b = relance("b"), c = relance("c")
        let bModifiee = relance("b", "Appeler le plombier")
        let d = DiffRelances.calculer(voulues: [a, bModifiee, c], enAttente: ["a", "b", "vieille"],
                                      posees: ["a": a, "b": b, "vieille": relance("vieille")])
        #expect(d.aPoser.map(\.id) == ["b", "c"])      // b a changé, c est nouvelle
        #expect(d.aRetirer == ["vieille"])
        #expect(Array(d.inchangees.keys) == ["a"])
    }

    @Test func partieChezIOSEstReposee() {
        // Posée la dernière fois mais plus en attente (déjà affichée, ou retirée par iOS) : reposée si encore prévue.
        let a = relance("a")
        let d = DiffRelances.calculer(voulues: [a], enAttente: [], posees: ["a": a])
        #expect(d.aPoser.map(\.id) == ["a"])
    }

    @Test func inconnueDeLaMemoireEstReposee() {
        // En attente mais posée par une version d'avant (pas dans la mémoire) : reposée par prudence.
        let a = relance("a")
        let d = DiffRelances.calculer(voulues: [a], enAttente: ["a"], posees: [:])
        #expect(d.aPoser.map(\.id) == ["a"])
    }

    @Test func memoireAllerRetour() throws {
        let defaults = try #require(UserDefaults(suiteName: "tests-relances-\(UUID().uuidString)"))
        let a = relance("a")
        DiffRelances.enregistrer(["a": a], defaults)
        #expect(DiffRelances.charger(defaults) == ["a": a])
    }
}
