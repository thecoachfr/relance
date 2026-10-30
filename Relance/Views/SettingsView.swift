import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(TaskStore.self) private var store
    @Environment(GoogleAuth.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        // Revue d'ergonomie du 28/10 : regroupé par usage, avec icônes, comme les Réglages d'iOS. L'usage courant en
        // tête (relances, envies, lieux, tri), les comptes et le diagnostic en bas ; le journal de synchro, qui prenait
        // presque toute la page, est dans Diagnostic.
        NavigationStack {
            Form {
                Section {
                    NavigationLink { ReminderSettingsView() } label: { Label("Relances", systemImage: "bell.badge") }
                    NavigationLink { EnviesSettingsView() } label: { Label("Envies", systemImage: "bookmark") }
                }
                if HAConfig.isActive || PushRegistration.webhookURL != nil {
                    Section {
                        if HAConfig.isActive {
                            NavigationLink { MesLieuxView() } label: { Label("Mes lieux", systemImage: "mappin.and.ellipse") }
                            NavigationLink { LieuTravailView() } label: { Label("Lieu de travail", systemImage: "building.2") }
                        }
                        if PushRegistration.webhookURL != nil {
                            NavigationLink { TrajetsView() } label: { Label("Mes trajets", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
                        }
                    }
                }
                Section {
                    NavigationLink { MemoListView() } label: { Label("Mémo pour le tri", systemImage: "text.book.closed") }
                    NavigationLink { RecettesView() } label: { Label("Actions automatiques", systemImage: "bolt") }
                    RetrierToutSection()
                } header: {
                    Text("Tri par Claude")
                }
                Section {
                    NavigationLink {
                        Form { HASettingsSection() }.navigationTitle("Home Assistant").inlineNavigationTitle()
                    } label: {
                        LabeledContent { Text(HAConfig.isActive ? "Activé" : "Désactivé") } label: {
                            Label("Home Assistant", systemImage: "house")
                        }
                    }
                    NavigationLink {
                        GoogleSettingsView { dismiss() }
                    } label: {
                        LabeledContent { Text(auth.email ?? "—") } label: {
                            Label("Compte Google", systemImage: "person.crop.circle")
                        }
                    }
                } header: {
                    Text("Comptes")
                }
                Section {
                    NavigationLink { SyncLogView() } label: { Label("Journal de synchro", systemImage: "arrow.triangle.2.circlepath") }
                    NavigationLink { ErreursView() } label: { Label("Erreurs récentes", systemImage: "exclamationmark.triangle") }
                    NavigationLink { DiagnosticView() } label: { Label("Diagnostic batterie", systemImage: "battery.75percent") }
                } header: {
                    Text("Diagnostic")
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
            #if DEBUG
            // `-sousreglage relances|envies` (debug) : une sous-page ouverte d'emblée, pour les captures.
            .navigationDestination(item: $sousReglage) { page in
                if page == "envies" { EnviesSettingsView() } else { ReminderSettingsView() }
            }
            #endif
        }
    }
    #if DEBUG
    @State private var sousReglage = UserDefaults.standard.string(forKey: "sousreglage")
    #endif
}

/// Réglages › Compte Google (28/10) : en mode Home Assistant, Google ne sert plus qu'aux dictées Google Home.
struct GoogleSettingsView: View {
    @Environment(TaskStore.self) private var store
    @Environment(GoogleAuth.self) private var auth
    var onSignOut: () -> Void = {}

    var body: some View {
        Form {
            Section {
                LabeledContent("Connecté", value: auth.email ?? "—")
                LabeledContent("Liste suivie", value: HAConfig.isActive ? "Boîte d'entrée des dictées" : "Mes tâches")
                if let error = store.lastError {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            } footer: {
                if HAConfig.isActive {
                    Text("Les tâches sont dans Home Assistant ; Google Tasks ne sert plus qu'à recevoir les dictées de Google Home.")
                }
            }
            Section {
                Button("Se déconnecter", role: .destructive) {
                    store.signOut()
                    onSignOut()
                }
            }
        }
        .navigationTitle("Compte Google")
        .inlineNavigationTitle()
    }
}

/// Réglages › Diagnostic › Journal de synchro (sorti de la page des Réglages le 28/10).
struct SyncLogView: View {
    var body: some View {
        Form {
            Section {
                let entries = SyncLog.all().prefix(40)
                if entries.isEmpty {
                    Text("Aucune synchro enregistrée").foregroundStyle(.secondary)
                }
                ForEach(Array(entries), id: \.self) { entry in
                    LabeledContent(entry.text) {
                        Text(entry.date, format: .dateTime.hour().minute().second())
                    }
                    .font(.footnote)
                }
            } footer: {
                Text("Si « Push de la vigie reçu » n'apparaît jamais, vérifie Réglages iOS → Général → Actualisation en arrière-plan → Aiguillage, et le mode Économie d'énergie.")
            }
        }
        .navigationTitle("Journal de synchro")
        .inlineNavigationTitle()
    }
}

/// Bouton Réglages (roue dentée) en haut à gauche de chaque onglet : avant le 16/10, il n'était que sur « À faire »
/// et on ne le trouvait pas ailleurs (retour d'Alexandre).
struct SettingsToolbarButton: ViewModifier {
    /// Grand écran d'À faire (30/10) : les réglages sont dans son menu « ⋯ », pas de roue dentée à part.
    var visible = true
    /// `-reglages 1` au lancement (debug) : Réglages ouverts d'emblée, pour les captures d'écran.
    @State private var showSettings = UserDefaults.standard.bool(forKey: "reglages")

    func body(content: Content) -> some View {
        content
            .toolbar {
                if visible {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Réglages", systemImage: "gearshape") { showSettings = true }
                    }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
    }
}

extension View {
    func settingsButton(visible: Bool = true) -> some View { modifier(SettingsToolbarButton(visible: visible)) }
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
