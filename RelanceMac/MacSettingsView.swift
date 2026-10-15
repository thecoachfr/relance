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
            Tab("Mémo", systemImage: "text.book.closed") {
                NavigationStack { MemoListView() }
                    .formStyle(.grouped)
                    .frame(width: 520, height: 560)
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

    var body: some View {
        Form {
            Section("Compte Google") {
                LabeledContent("Connecté", value: auth.email ?? "—")
                LabeledContent("Liste suivie", value: HAConfig.isActive ? "Boîte d'entrée des dictées" : "Mes tâches")
                if let error = store.lastError {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
                if auth.isSignedIn {
                    Button("Se déconnecter", role: .destructive) { store.signOut() }
                }
            }
            HASettingsSection()
            ReminderDeviceSection()
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 620)
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
                Text("Aiguillage synchronise à l'ouverture, toutes les 5 minutes et au réveil du Mac.")
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Version", value: AppVersion.text)
                Button("Synchroniser maintenant") { Task { await store.sync() } }
                    .disabled(store.isSyncing)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 520)
    }
}
