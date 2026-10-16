#if DEBUG
import Foundation

/// Tâches d'exemple pour le mode `-demo`.
enum DemoData {
    static func seed(_ store: TaskStore) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }
        let hour = calendar.component(.hour, from: .now)

        store.add(title: "Renvoyer le formulaire de la mutuelle", day: day(-2), minutes: 10 * 60, category: "Administratif")
        store.add(title: "Appeler le garage", day: day(0), minutes: max(0, hour - 1) * 60, priority: .urgent)
        store.add(title: "Payer la cantine", day: day(0), minutes: min(23, hour + 2) * 60, category: "Famille")
        store.add(title: "Acheter un cadeau pour Léa", day: day(0), minutes: nil, priority: .low)
        let garage = store.add(title: "Réserver le contrôle technique", day: day(1), minutes: 9 * 60 + 30, category: "Maison")
        garage.notes = "📍 Mairie du 4e · 2 place Baudoyer, 75004 Paris"
        let papers = store.add(title: "Déposer le dossier à la mairie", day: day(2), minutes: 11 * 60, category: "Administratif")
        papers.notes = "📍 Mairie du 4e · 2 place Baudoyer, 75004 Paris"
        let books = store.add(title: "Rendre les livres à la médiathèque", day: day(3), minutes: nil, category: "Perso")
        books.notes = "📍 Bibliothèque de l'Hôtel de Ville · 5 rue de Lobau, 75004 Paris"
        store.add(title: "Trier les papiers de la banque", day: nil, minutes: nil)
        // Lieu sans adresse (photo, point GPS) : seulement un lien Plans vers le point.
        store.add(title: "Le pont Marie", day: nil, minutes: nil, category: "Perso",
                  notes: "📍 Pont Marie · https://maps.apple.com/?ll=48.8519,2.3572&q=Pont%20Marie\n"
                      + ToSee(.photoSpot, note: "au couchant, en automne").lines.joined(separator: "\n"))
        store.add(title: "Chez Janou", day: nil, minutes: nil, category: "Perso",
                  notes: "📍 Chez Janou · https://maps.apple.com/?ll=48.8566,2.3683&q=Chez%20Janou\n"
                      + ToSee(.restaurant).lines.joined(separator: "\n"))
        // Resto dicté, sans lieu : Plans le propose dans la fiche.
        store.add(title: "Express de Lyon", day: nil, minutes: nil, category: "Perso",
                  notes: ToSee(.restaurant).lines.joined(separator: "\n"))
        store.add(title: "La papeterie du Marais", day: nil, minutes: nil, category: "Achats",
                  notes: "📍 Papeterie · https://maps.apple.com/?ll=48.8578,2.3560&q=Papeterie\n"
                      + ToSee(.shop).lines.joined(separator: "\n"))
        let expo = store.add(title: "Voir l'expo photo de la MEP", day: nil, minutes: nil, category: "Perso")
        expo.notes = "📍 Maison européenne de la photographie · 5 rue de Fourcy, 75004 Paris\n"
            + ToSee(start: day(-30), end: day(19)).lines.joined(separator: "\n")
        store.add(title: "Perfect Days", day: nil, minutes: nil, category: "Perso",
                  notes: "📩 Message partagé\nhttps://www.youtube.com/watch?v=exemple\n" + ToSee(.watch).lines.joined(separator: "\n"))
        store.add(title: "Le film de Kore-eda au cinéma", day: nil, minutes: nil, category: "Perso",
                  notes: ToSee(.watch, end: day(12)).lines.joined(separator: "\n"))
        store.add(title: "L'Anomalie, Hervé Le Tellier", day: nil, minutes: nil, category: "Perso",
                  notes: ToSee(.read).lines.joined(separator: "\n"))
        store.add(title: "Le dernier album de Feist", day: nil, minutes: nil, category: "Perso",
                  notes: "https://open.spotify.com/album/exemple\n" + ToSee(.listen).lines.joined(separator: "\n"))
        let read = store.add(title: "Un article sur la photo argentique", day: nil, minutes: nil,
                             notes: ToSee(.read).lines.joined(separator: "\n"))
        store.complete(read)
        let done = store.add(title: "Prendre rendez-vous chez le dentiste", day: day(-1), minutes: 14 * 60)
        store.complete(done)
    }
}
#endif
