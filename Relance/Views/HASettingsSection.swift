import DonneesHA
import SwiftUI

/// « Home Assistant » : où ranger les tâches. L'URL et le jeton restent sur l'appareil
/// (App Group et trousseau), jamais dans le dépôt.
struct HASettingsSection: View {
    @Environment(TaskStore.self) private var store
    @State private var urlText = HAConfig.url?.absoluteString ?? ""
    @State private var tokenText = ""
    @State private var hasToken = HAConfig.token?.isEmpty == false
    @State private var isActive = HAConfig.isActive
    @State private var message: String?
    @State private var working = false
    @State private var confirmActivate = false
    @State private var confirmDeactivate = false

    var body: some View {
        Section {
            TextField("Adresse (https://…ui.nabu.casa)", text: $urlText)
                .textContentType(.URL)
                .autocorrectionDisabled()
                #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                #endif
            SecureField(hasToken ? "Jeton enregistré (coller pour le remplacer)" : "Jeton de l'utilisateur apps-perso",
                        text: $tokenText)
            Button("Enregistrer et tester") { Task { await saveAndTest() } }
                .disabled(working || urlText.isEmpty || (!hasToken && tokenText.isEmpty))
            if isActive {
                LabeledContent("Synchro", value: store.haStatus ?? "—")
                if let conflict = store.synchro?.dernierConflit {
                    Text(conflict).font(.footnote).foregroundStyle(.secondary)
                }
                Button("Synchroniser maintenant") { Task { await store.sync() } }
                    .disabled(store.isSyncing)
                Button("Revenir à Google Tasks", role: .destructive) { confirmDeactivate = true }
                    .disabled(working)
            } else if HAConfig.isConfigured {
                Button("Passer les tâches dans Home Assistant") { confirmActivate = true }
                    .disabled(working)
            }
            if let message {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("Home Assistant")
        } footer: {
            Text(isActive
                 ? "Les tâches sont rangées dans Home Assistant. Sans connexion, elles restent sur l'appareil et une copie part dans iCloud ; tout repart vers Home Assistant dès qu'il répond. Google Tasks ne sert plus qu'aux dictées Google Home (reprises par la vigie) et au mémo."
                 : "Tant que ce n'est pas activé, les tâches restent dans Google Tasks. À faire sur chaque appareil (iPhone, iPad, Mac).")
        }
        .confirmationDialog("Passer les tâches dans Home Assistant ?", isPresented: $confirmActivate,
                            titleVisibility: .visible) {
            Button("Passer dans Home Assistant") { Task { await activate() } }
        } message: {
            Text("Une dernière synchro Google, puis toutes les tâches de cet appareil sont envoyées à Home Assistant.")
        }
        .confirmationDialog("Revenir à Google Tasks ?", isPresented: $confirmDeactivate, titleVisibility: .visible) {
            Button("Revenir à Google Tasks", role: .destructive) { Task { await deactivate() } }
        } message: {
            Text("Les tâches de cet appareil sont renvoyées dans Google Tasks. Celles de Home Assistant y restent.")
        }
    }

    private func saveAndTest() async {
        working = true
        defer { working = false }
        guard let url = HAConfig.normalizedURL(urlText) else {
            message = "Adresse non reconnue."
            return
        }
        let token = tokenText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty {
            guard HAConfig.saveToken(token) else {
                message = "Le jeton n'a pas pu être rangé dans le trousseau."
                return
            }
            tokenText = ""
            hasToken = true
        }
        HAConfig.url = url
        urlText = url.absoluteString
        store.resetHA()
        guard let saved = HAConfig.token else { return }
        do {
            let reponse = try await HAClient(url: url, jeton: saved).changements(espace: HAConfig.espace, depuisSeq: 0)
            message = "Connexion réussie : \(reponse.enregistrements.filter { !$0.supprime }.count) tâche(s) dans Home Assistant."
        } catch {
            message = "Échec : \(Self.describe(error))"
        }
    }

    private func activate() async {
        working = true
        defer { working = false }
        message = await store.activateHA() ?? "Tâches passées dans Home Assistant."
        isActive = HAConfig.isActive
    }

    private func deactivate() async {
        working = true
        defer { working = false }
        message = await store.deactivateHA() ?? "Retour à Google Tasks fait."
        isActive = HAConfig.isActive
    }

    private static func describe(_ error: Error) -> String {
        switch error as? ErreurHA {
        case .nonAutorise?: "jeton refusé par Home Assistant."
        case .injoignable(let detail)?: "Home Assistant ne répond pas (\(detail))."
        case .refuse(let detail)?: "refusé par Home Assistant : \(detail)"
        default: "\(error)"
        }
    }
}
