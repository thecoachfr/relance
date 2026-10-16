import SwiftUI

/// Bouton « Retrier avec Claude » d'une tâche.
struct RetriageSection: View {
    @Environment(TaskStore.self) private var store
    let item: TaskItem
    @State private var state: TriageState = .idle

    var body: some View {
        Section {
            Button {
                Task {
                    state = .sending
                    state = await TriageRequest.retriage([item], store: store) ? .sent : .failed
                }
            } label: {
                HStack {
                    Label("Retrier avec Claude", systemImage: "sparkles")
                    if state == .sending { Spacer(); ProgressView() }
                }
            }
            .disabled(state == .sending)
            NavigationLink {
                MemoEditor(entry: nil, fromTask: item.title,
                           draft: MemoMerge.draft(title: item.title, notes: item.notes,
                                                  category: item.category, tags: item.tags))
            } label: {
                Label("Envoyer au mémo…", systemImage: "text.book.closed")
            }
        } footer: {
            Text(state.footer(single: true))
        }
    }
}

/// Tâche annoncée par le message partagé et proposée par la routine de tri (ligne « ➕ ») : créée d'un toucher.
struct ProposalSection: View {
    @Environment(TaskStore.self) private var store
    let item: TaskItem
    @Binding var notes: String

    var body: some View {
        if let proposal = TaskProposal(notes: notes) {
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text(proposal.title)
                    let summary = proposal.summary()
                    if !summary.isEmpty {
                        Text(summary).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                Button("Créer cette tâche", systemImage: "plus.circle") { resolve(create: true) }
                Button("Ignorer", systemImage: "xmark.circle") { resolve(create: false) }
            } header: {
                Text("Tâche proposée")
            } footer: {
                Text("Repérée par le tri dans le message. Elle est créée dans la même catégorie.")
            }
        }
    }

    private func resolve(create: Bool) {
        withAnimation {
            store.resolveProposal(of: item, create: create)
            notes = TaskProposal.removing(from: notes)
        }
    }
}

enum TriageState: Equatable {
    case idle, sending, sent, failed

    func footer(single: Bool) -> String {
        switch self {
        case .idle, .sending:
            single ? "La routine reclasse la catégorie et les tags avec ton mémo. Priorité, relances et contact ne bougent pas."
                   : "Catégories et tags de toutes les tâches à faire sont recalculés par la routine, avec ton mémo."
        case .sent: "C'est demandé : le nouveau classement arrive d'ici une à deux minutes."
        case .failed: "Home Assistant ne répond pas. La catégorie a été retirée : la routine la reclassera au prochain tri (6 h 45 ou nouvelle tâche)."
        }
    }
}
