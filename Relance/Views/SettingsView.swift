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
                    LabeledContent("Liste suivie", value: HAConfig.isActive ? "Boîte d'entrée des dictées" : "Mes tâches")
                    if let error = store.lastError {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                    Button("Se déconnecter", role: .destructive) {
                        store.signOut()
                        dismiss()
                    }
                }
                HASettingsSection()
                ReminderDeviceSection()
                Section {
                    NavigationLink("Quand et comment relancer") { ReminderSettingsView() }
                    NavigationLink("Mémo pour le tri") { MemoListView() }
                    NavigationLink("Actions automatiques") { RecettesView() }
                    if HAConfig.isActive { NavigationLink("Mes lieux") { MesLieuxView() } }
                    if PushRegistration.webhookURL != nil { NavigationLink("Mes trajets") { TrajetsView() } }
                    NavigationLink("Diagnostic batterie") { DiagnosticView() }
                    NavigationLink("Erreurs récentes") { ErreursView() }
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
                    Text("Si « Push de la vigie reçu » n'apparaît jamais, vérifie Réglages iOS → Général → Actualisation en arrière-plan → Aiguillage, et le mode Économie d'énergie.")
                }
                Section("À propos") {
                    LabeledContent("Version", value: AppVersion.text)
                    LabeledContent("Commit", value: AppVersion.commit)
                        .textSelection(.enabled)
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

/// Bouton Réglages (roue dentée) en haut à gauche de chaque onglet : avant le 16/10, il n'était que sur « À faire »
/// et on ne le trouvait pas ailleurs (retour d'Alexandre).
struct SettingsToolbarButton: ViewModifier {
    @State private var showSettings = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Réglages", systemImage: "gearshape") { showSettings = true }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
    }
}

extension View {
    func settingsButton() -> some View { modifier(SettingsToolbarButton()) }
}

/// Même bouton, flottant, pour les écrans sans barre de navigation (la carte).
struct FloatingSettingsButton: View {
    @State private var showSettings = false

    var body: some View {
        Button("Réglages", systemImage: "gearshape") { showSettings = true }
            .labelStyle(.iconOnly)
            .font(.title3.weight(.semibold))
            // Comme la roue dentée des barres de navigation : noire (ou blanche en sombre), pas orange.
            .foregroundStyle(.primary)
            .frame(width: 48, height: 48)
            .background(.regularMaterial, in: .circle)
            .shadow(radius: 3, y: 1)
            .sheet(isPresented: $showSettings) { SettingsView() }
    }
}
