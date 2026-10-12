import SwiftUI

/// Mémo pour le tri : les fiches que la routine lit pour classer les tâches, trouver un contact, etc.
struct MemoListView: View {
    @Environment(TaskStore.self) private var store
    @State private var adding = false

    private var memo: MemoStore { store.memo }

    var body: some View {
        // Formulaire plutôt que liste : sur Mac, le texte sous la section y passe à la ligne au lieu d'être coupé.
        Form {
            #if os(macOS)
            // Dans la fenêtre Réglages, un bouton de barre d'outils irait se ranger parmi les onglets.
            Section {
                Button("Nouvelle fiche", systemImage: "plus") { adding = true }
            }
            #endif
            Section {
                ForEach(memo.entries) { entry in
                    NavigationLink {
                        MemoEditor(entry: entry)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title)
                            if !entry.details.isEmpty {
                                Text(entry.details).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                    .swipeActions {
                        Button("Retirer", systemImage: "trash", role: .destructive) { Task { await memo.remove(entry) } }
                    }
                    .contextMenu {
                        Button("Retirer", systemImage: "trash", role: .destructive) { Task { await memo.remove(entry) } }
                    }
                }
            } footer: {
                Text("Une fiche par personne, lieu, activité ou règle. La routine de tri les lit pour choisir la catégorie et les tags, et ajouter le lieu ou le contact d'une tâche. Elles sont rangées dans la liste Google Tasks « \(MemoStore.listTitle) », jamais ailleurs.")
            }
            if let error = memo.lastError {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .overlay {
            if memo.entries.isEmpty, !memo.isLoading, memo.lastError == nil {
                ContentUnavailableView("Mémo vide", systemImage: "text.book.closed",
                                       description: Text("Ajoute une fiche : « Dentiste », « Place 38 », « Syndic »…"))
            }
        }
        .navigationTitle("Mémo pour le tri")
        .inlineNavigationTitle()
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Nouvelle fiche", systemImage: "plus") { adding = true }
            }
        }
        #endif
        .navigationDestination(isPresented: $adding) { MemoEditor(entry: nil) }
        .task { await memo.load() }
        .refreshable { await memo.load() }
    }
}

/// Création ou modification d'une fiche.
struct MemoEditor: View {
    @Environment(TaskStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let entry: MemoEntry?
    /// Tâche d'où l'on vient (« Retenir pour le tri ») : rappelée en tête, pour s'en inspirer.
    var fromTask: String?

    @State private var title = ""
    @State private var details = ""
    @State private var saving = false

    var body: some View {
        Form {
            if let fromTask {
                Section {
                    Label(fromTask, systemImage: "checklist").foregroundStyle(.secondary)
                } footer: {
                    Text("Ce que la routine devrait savoir pour bien ranger ce genre de tâche.")
                }
            }
            Section {
                TextField("Sujet", text: $title, prompt: Text("Dentiste, Place 38, Syndic…"))
                TextField("Détails", text: $details, prompt: Text("Nom, adresse, téléphone, lien de rendez-vous, catégorie ou tag habituel…"), axis: .vertical)
                    .lineLimit(4...)
                    .formFieldWithoutLabel()
            } footer: {
                Text("Ex. « Place 38 » : « louée à M. Exemple via la SCI, tag SCI, catégorie Administratif ».")
            }
            if let entry {
                Section {
                    Button("Retirer la fiche", role: .destructive) {
                        Task {
                            await store.memo.remove(entry)
                            dismiss()
                        }
                    }
                }
            }
        }
        .navigationTitle(entry == nil ? "Nouvelle fiche" : "Fiche")
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Enregistrer") { save() }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || saving)
            }
        }
        .onAppear {
            title = entry?.title ?? ""
            details = entry?.details ?? ""
        }
    }

    private func save() {
        saving = true
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let details = details.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            if var entry {
                entry.title = title
                entry.details = details
                await store.memo.update(entry)
            } else {
                await store.memo.add(title: title, details: details)
            }
            saving = false
            if store.memo.lastError == nil { dismiss() }
        }
    }
}
