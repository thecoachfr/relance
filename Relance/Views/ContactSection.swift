import SwiftUI

/// Contact de la tâche (ligne « 📍 » des notes) : appeler, itinéraire, prendre rendez-vous.
struct ContactSection: View {
    let notes: String
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let contact = TaskContact(notes: notes) {
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.name).font(.headline)
                    if let address = contact.address {
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
                if let url = contact.link {
                    Button { openURL(url) } label: { Label("Prendre rendez-vous", systemImage: "calendar.badge.plus") }
                }
            } header: {
                Text("Contact")
            }
        }
    }
}
