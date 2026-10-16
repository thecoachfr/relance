import SwiftUI

/// Lieu de la tâche (ligne « 📍 » des notes) : appeler, itinéraire, prendre rendez-vous ;
/// l'ajouter à la main, le changer ou le retirer.
struct ContactSection: View {
    @Binding var notes: String
    /// Ouvre la recherche. La feuille est portée par le formulaire (`placeSearch`) : ouverte depuis une ligne
    /// d'un formulaire lui-même dans une feuille, elle refermait la fiche de la tâche (iPhone).
    @Binding var searching: Bool
    /// Catégorie et tags de la tâche, repris dans la fiche « Garder dans le mémo » ;
    /// `nil` = pas de bouton (saisie rapide : la tâche n'existe pas encore).
    var memoSource: (category: String?, tags: [String])?
    @Environment(\.openURL) private var openURL
    @Environment(TaskStore.self) private var store
    @State private var remembering = false
    /// Résultat du dernier « Garder dans le mémo », pour le lieu de ce nom.
    @State private var remembered: (name: String, outcome: MemoMerge.Outcome?)?

    var body: some View {
        Section {
            if let contact = TaskContact(notes: notes) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.name).font(.headline)
                    if let address = contact.address, address != contact.name {
                        Text(address).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                if let url = contact.phoneURL, let phone = contact.phone {
                    Button { openURL(url) } label: { Label("Appeler · \(phone)", systemImage: "phone") }
                }
                if let url = contact.mapsURL {
                    Button { openURL(url) } label: { Label("Itinéraire", systemImage: "map") }
                }
                if let url = contact.googleMapsURL {
                    Button { openURL(url) } label: { Label("Ouvrir dans Google Maps", systemImage: "mappin.circle") }
                }
                // Le lien Plans d'un lieu sans adresse sert déjà à « Itinéraire ».
                if let url = contact.link, contact.coordinate == nil {
                    if contact.isBookingLink {
                        Button { openURL(url) } label: { Label("Prendre rendez-vous", systemImage: "calendar.badge.plus") }
                    } else {
                        Button { openURL(url) } label: { Label("Site web", systemImage: "safari") }
                    }
                }
                if let memoSource {
                    memoButton(contact, source: memoSource)
                }
                // Deux lignes visibles plutôt qu'un menu : retirer un lieu doit se trouver sans chercher.
                #if os(iOS)
                if contact.destination != nil {
                    Toggle(isOn: Binding(
                        get: { NearbyReminder.isOn(notes) },
                        set: { on in
                            notes = NearbyReminder.notes(notes, on: on)
                            if on { ProximityReminders.shared.requestAuthorization() }
                        })) {
                        Label("Me le rappeler en passant à côté", systemImage: "location.circle")
                    }
                }
                #endif
                Button("Changer de lieu", systemImage: "mappin.and.ellipse") { searching = true }
                Button("Retirer le lieu", systemImage: "mappin.slash", role: .destructive) {
                    notes = TaskContact.notes(notes, setting: nil)
                }
            } else {
                Button("Ajouter un lieu", systemImage: "mappin.and.ellipse") { searching = true }
            }
        } header: {
            Text("Lieu")
        } footer: {
            if let contact = TaskContact(notes: notes), let remembered, remembered.name == contact.name {
                Text(memoFooter(remembered.outcome, name: contact.name))
            } else if TaskContact(notes: notes) == nil {
                Text("Avec une adresse, Aiguillage peut te dire quand partir et l'ajouter à l'événement d'agenda.")
            } else if NearbyReminder.isOn(notes) {
                Text("L'appareil qui relance te prévient à moins de 200 m, une fois par jour (localisation « Toujours » requise).")
            } else {
                Text("Dans Google Maps : Enregistrer › À visiter, pour garder le lieu.")
            }
        }
    }

    /// Une fiche du mémo en un geste, sans saisie ; une fiche du même nom est complétée.
    @ViewBuilder
    private func memoButton(_ contact: TaskContact, source: (category: String?, tags: [String])) -> some View {
        let done = remembered?.name == contact.name && remembered?.outcome != nil
        Button {
            remembering = true
            Task {
                let draft = MemoMerge.draft(contact: contact, category: source.category, tags: source.tags)
                let outcome = await store.memo.remember(title: draft.title, details: draft.details)
                remembered = (contact.name, outcome)
                remembering = false
            }
        } label: {
            HStack {
                Label(done ? "Dans le mémo" : "Garder dans le mémo",
                      systemImage: done ? "checkmark.circle" : "text.book.closed")
                if remembering { Spacer(); ProgressView() }
            }
        }
        .disabled(done || remembering)
    }

    private func memoFooter(_ outcome: MemoMerge.Outcome?, name: String) -> String {
        switch outcome {
        case .added: "Fiche « \(name) » ajoutée au mémo : la routine s'en servira au prochain tri."
        case .completed: "La fiche « \(name) » existait : elle a été complétée."
        case .unchanged: "La fiche « \(name) » contenait déjà tout cela."
        case nil: "Google ne répond pas : la fiche n'a pas été enregistrée. Réessaie dans un moment."
        }
    }
}

extension View {
    /// Recherche de lieu pour `ContactSection`, à poser sur le formulaire entier.
    func placeSearch(isPresented: Binding<Bool>, notes: Binding<String>) -> some View {
        sheet(isPresented: isPresented) {
            PlaceSearchView { notes.wrappedValue = TaskContact.notes(notes.wrappedValue, setting: $0) }
        }
    }
}
