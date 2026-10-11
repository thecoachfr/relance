import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(TaskStore.self) private var store
    @Environment(GoogleAuth.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var notificationStatus: UNAuthorizationStatus?

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
