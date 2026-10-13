import SwiftUI

/// Fiche du mémo depuis la feuille de partage : sujet et détails préremplis, à retoucher.
/// Un sujet qui existe déjà complète la fiche au lieu d'en créer une autre.
struct MemoShareView: View {
    let draft: (title: String, details: String)
    @Binding var mode: ShareMode
    let onDone: () -> Void
    let onCancel: () -> Void

    @State private var title = ""
    @State private var details = ""
    @State private var subjects: [String] = []
    @State private var sending = false
    @State private var failure: String?
    @FocusState private var subjectFocused: Bool

    private let session = GoogleRefreshSession.shared
    private var api: TasksAPI { TasksAPI(token: { [session] in try await session.validAccessToken() }) }

    var body: some View {
        NavigationStack {
            Form {
                if MemoShareDraft.isNotesLink(draft.details) {
                    Section {
                        Label("Notes n'a envoyé qu'un lien vers la note. Pour en récupérer le texte : Annuler, puis dans la feuille de partage de Notes, choisir « Envoyer une copie » au lieu de « Collaborer ».",
                              systemImage: "info.circle")
                            .font(.callout)
                    }
                }
                Section {
                    TextField("Sujet", text: $title, prompt: Text("Sujet : Dentiste, Résidence, Syndic…"), axis: .vertical)
                        .font(.headline)
                        .focused($subjectFocused)
                    TextField("Détails", text: $details, prompt: Text("Adresse, téléphone, lien, catégorie ou tag habituel…"), axis: .vertical)
                        .lineLimit(4...)
                } footer: {
                    Text(existing != nil
                         ? "La fiche « \(existing!) » existe : elle sera complétée."
                         : "La routine de tri lit le mémo pour ranger tes tâches. Si une fiche porte déjà ce sujet, elle est complétée.")
                }
                if !suggestions.isEmpty {
                    Section("Compléter une fiche") {
                        ForEach(suggestions, id: \.self) { subject in
                            Button(subject) { title = subject }
                        }
                    }
                }
                if !session.isAvailable {
                    Section {
                        Text("Ouvre Aiguillage une fois pour connecter le partage à Google.").foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Mémo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", action: onCancel)
                }
                ToolbarItem(placement: .principal) {
                    ShareModePicker(mode: $mode)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if sending {
                        ProgressView()
                    } else {
                        Button(existing != nil ? "Compléter" : "Ajouter") { Task { await save() } }
                            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || !session.isAvailable)
                    }
                }
            }
            .alert("Fiche non enregistrée", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(failure ?? "")
            }
            .onAppear {
                title = draft.title
                details = draft.details
                // Une adresse seule : le sujet est à taper, on y met le curseur.
                if title.isEmpty { subjectFocused = true }
            }
            .task {
                guard session.isAvailable else { return }
                subjects = (try? await api.memoSubjects()) ?? []
            }
        }
    }

    /// Fiche existante du même sujet.
    private var existing: String? {
        subjects.first { MemoMerge.sameSubject($0, title) }
    }

    /// Fiches dont le sujet contient un mot du sujet tapé (3 au plus), pour compléter plutôt que doubler.
    private var suggestions: [String] {
        let words = title.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init).filter { $0.count >= 3 }
        guard existing == nil, !words.isEmpty else { return [] }
        return Array(subjects.filter { subject in
            let s = subject.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            return words.contains { s.contains($0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)) }
        }.prefix(3))
    }

    private func save() async {
        sending = true
        defer { sending = false }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let details = details.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            _ = try await api.remember(title: title, details: details)
            onDone()
        } catch {
            // Rien n'est perdu : la feuille reste ouverte, on peut réessayer ou copier le texte.
            failure = "Google ne répond pas. Vérifie la connexion et réessaie."
        }
    }
}
