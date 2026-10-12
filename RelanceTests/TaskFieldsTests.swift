import Foundation
import Testing
@testable import Relance

/// Cas du 12/10 : la routine ajoute 📍 aux notes pendant que la tâche est ouverte sur l'iPad ;
/// enregistrer depuis l'iPad ne doit pas effacer cet ajout.
struct TaskFieldsTests {
    let base = TaskFields(title: "Rendez-vous chez le dentiste", notes: "🎙 Dicté : x", day: nil, minutes: nil,
                          category: "Santé", priority: .normal, reminders: nil, tags: [])

    @Test func untouchedFieldsKeepCurrentValue() {
        var current = base
        current.notes = "🎙 Dicté : x\n📍 Dr Claire Martin · 12 rue de la Paix"
        var entered = base
        entered.priority = .urgent          // seule modification faite sur l'iPad
        let merged = entered.merged(base: base, current: current)
        #expect(merged.notes == current.notes)
        #expect(merged.priority == .urgent)
    }

    @Test func editedFieldWins() {
        var current = base
        current.notes = "changé ailleurs"
        var entered = base
        entered.notes = "changé ici"
        #expect(entered.merged(base: base, current: current).notes == "changé ici")
    }
}
