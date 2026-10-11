#if DEBUG
import Foundation

/// Tâches d'exemple pour le mode `-demo`.
enum DemoData {
    static func seed(_ store: TaskStore) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }
        let hour = calendar.component(.hour, from: .now)

        store.add(title: "Renvoyer le formulaire de la mutuelle", day: day(-2), minutes: 10 * 60)
        store.add(title: "Appeler le garage", day: day(0), minutes: max(0, hour - 1) * 60)
        store.add(title: "Payer la cantine", day: day(0), minutes: min(23, hour + 2) * 60)
        store.add(title: "Acheter un cadeau pour Léa", day: day(0), minutes: nil)
        store.add(title: "Réserver le contrôle technique", day: day(1), minutes: 9 * 60 + 30)
        store.add(title: "Rendre les livres à la médiathèque", day: day(3), minutes: nil)
        store.add(title: "Trier les papiers de la banque", day: nil, minutes: nil)
        let done = store.add(title: "Prendre rendez-vous chez le dentiste", day: day(-1), minutes: 14 * 60)
        store.complete(done)
    }
}
#endif
