import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(TaskStore.self) private var store
    @Environment(GoogleAuth.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var notificationStatus: UNAuthorizationStatus?
    @State private var remindersHere = ReminderScheduler.isEnabledOnThisDevice

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
                Section {
                    Toggle("Relances sur cet appareil", isOn: $remindersHere)
                        .onChange(of: remindersHere) { _, on in
                            ReminderScheduler.isEnabledOnThisDevice = on
                            Task { await store.reschedule() }
                        }
                } footer: {
                    Text("Activé d'origine sur l'iPhone seulement, pour ne pas être relancé deux fois pour la même tâche.")
                }
                Section {
                    let s = store.scheduler.settings
                    LabeledContent("Relances", value: "à l'heure, +1 h, \(ReminderPlanner.formatTime(s.evening))")
                    LabeledContent("En retard", value: "\(ReminderPlanner.formatTime(s.morning)) et \(ReminderPlanner.formatTime(s.evening))")
                    LabeledContent("Silence", value: "\(ReminderPlanner.formatTime(s.quietStart)) – \(ReminderPlanner.formatTime(s.quietEnd))")
                    if notificationStatus == .denied {
                        Button("Notifications désactivées : ouvrir les réglages") {
                            openURL(URL(string: UIApplication.openNotificationSettingsURLString)!)
                        }
                    }
                } header: {
                    Text("Rythme")
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } }
            }
            .task { notificationStatus = await store.scheduler.authorizationStatus() }
        }
    }
}
