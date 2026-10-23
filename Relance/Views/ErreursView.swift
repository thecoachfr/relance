import SwiftUI

/// Réglages › Erreurs récentes : ce qui a échoué en silence (synchro, enregistrement, notifications, réseau),
/// noté par `Journal`. Sert à comprendre un souci sans câble ni Console.
struct ErreursView: View {
    @State private var entrees = Journal.recentes()

    var body: some View {
        Form {
            Section {
                if entrees.isEmpty {
                    Text("Aucune erreur enregistrée").foregroundStyle(.secondary)
                }
                ForEach(entrees, id: \.self) { entree in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entree.texte)
                        Text(Self.ligne(entree)).foregroundStyle(.secondary)
                    }
                    .font(.footnote)
                    .textSelection(.enabled)
                }
            } footer: {
                Text("Les 30 dernières, de cet appareil et de son extension de partage. Une erreur répétée n'apparaît qu'une fois, avec son nombre.")
            }
            if !entrees.isEmpty {
                Section {
                    Button("Effacer", role: .destructive) {
                        Journal.effacer()
                        entrees = []
                    }
                }
            }
        }
        .navigationTitle("Erreurs récentes")
        .onAppear { entrees = Journal.recentes() }
    }

    private static func ligne(_ entree: Journal.Entree) -> String {
        let date = entree.date.formatted(.dateTime.day().month().hour().minute())
        return entree.fois > 1 ? "\(entree.domaine) · \(date) · \(entree.fois) fois" : "\(entree.domaine) · \(date)"
    }
}
