import SwiftUI
import UserNotifications

/// Réglages (⌘,) : compte et synchro, puis les relances.
struct MacSettingsView: View {
    var body: some View {
        TabView {
            Tab("Général", systemImage: "gearshape") {
                GeneralSettings()
            }
            Tab("Relances", systemImage: "bell") {
                NavigationStack { ReminderSettingsView() }
                    .formStyle(.grouped)
                    .frame(width: 520, height: 620)
            }
            Tab("Synchro", systemImage: "arrow.triangle.2.circlepath") {
                SyncLogSettings()
            }
        }
        .scenePadding(.top)
    }
}

private struct GeneralSettings: View {
    @Environment(TaskStore.self) private var store
    @Environment(GoogleAuth.self) private var auth
    @Environment(\.openURL) private var openURL
    @State private var remindersHere = ReminderScheduler.isEnabledOnThisDevice
    @State private var notificationStatus: UNAuthorizationStatus?

    var body: some View {
        Form {
            Section("Compte Google") {
                LabeledContent("Connecté", value: auth.email ?? "—")
                LabeledContent("Liste suivie", value: "Mes tâches")
                if let error = store.lastError {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
                if auth.isSignedIn {
                    Button("Se déconnecter", role: .destructive) { store.signOut() }
                }
            }
            Section {
                Toggle("Relances sur ce Mac", isOn: $remindersHere)
                    .onChange(of: remindersHere) { _, on in
                        ReminderScheduler.isEnabledOnThisDevice = on
                        Task {
                            if on { _ = await store.scheduler.requestAuthorization() }
                            notificationStatus = await store.scheduler.authorizationStatus()
                            await store.reschedule()
                        }
                    }
                if remindersHere, notificationStatus == .denied {
                    Button("Notifications refusées : ouvrir Réglages Système") {
                        openURL(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                    }
                }
            } header: {
                Text("Notifications")
            } footer: {
                Text("Désactivées d'origine : l'iPhone relance déjà, et un « Fait » sur un appareil ne coupe l'autre qu'à la synchro suivante.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 340)
        .task { notificationStatus = await store.scheduler.authorizationStatus() }
    }
}

/// Journal de synchro : pour comprendre un retard, sans encombrer les réglages courants.
private struct SyncLogSettings: View {
    @Environment(TaskStore.self) private var store

    var body: some View {
        Form {
            Section {
                let entries = SyncLog.all().prefix(20)
                if entries.isEmpty {
                    Text("Aucune synchro enregistrée").foregroundStyle(.secondary)
                }
                ForEach(Array(entries), id: \.self) { entry in
                    LabeledContent(entry.text) {
                        Text(entry.date, format: .dateTime.hour().minute().second())
                    }
                }
            } footer: {
                Text("Relance synchronise à l'ouverture, toutes les 5 minutes et au réveil du Mac.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Synchroniser maintenant") { Task { await store.sync() } }
                    .disabled(store.isSyncing)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 520)
    }
}
