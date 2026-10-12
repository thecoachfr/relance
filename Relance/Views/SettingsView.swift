import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(TaskStore.self) private var store
    @Environment(GoogleAuth.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Form {
                Section("Compte Google") {
                    LabeledContent("Connecté", value: auth.email ?? "—")
                    LabeledContent("Liste suivie", value: "Mes tâches")
                    if let error = store.lastError {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                    Button("Se déconnecter", role: .destructive) {
                        store.signOut()
                        dismiss()
                    }
                }
                ReminderDeviceSection()
                Section {
                    NavigationLink("Quand et comment relancer") { ReminderSettingsView() }
                    NavigationLink("Mémo pour le tri") { MemoListView() }
                }
                Section {
                    let entries = SyncLog.all().prefix(12)
                    if entries.isEmpty {
                        Text("Aucune synchro enregistrée").foregroundStyle(.secondary)
                    }
                    ForEach(Array(entries), id: \.self) { entry in
                        LabeledContent(entry.text) {
                            Text(entry.date, format: .dateTime.hour().minute().second())
                        }
                        .font(.footnote)
                    }
                } header: {
                    Text("Journal de synchro")
                } footer: {
                    Text("Si « Push de la vigie reçu » n'apparaît jamais, vérifie Réglages iOS → Général → Actualisation en arrière-plan → Relance, et le mode Économie d'énergie.")
                }
            }
            .navigationTitle("Réglages")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } }
            }
        }
    }
}
