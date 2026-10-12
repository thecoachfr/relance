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
        } footer: {
            Text(state.footer(single: true))
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
