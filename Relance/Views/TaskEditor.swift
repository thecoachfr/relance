import SwiftUI

/// Fiche d'une tâche en feuille (iPhone, et partout où une tâche s'ouvre par-dessus une liste) : la même fiche
/// que la colonne de l'iPad, enregistrée au fil de la saisie (P9-L3, 19/10 : plus d'Annuler / OK, qui ne
/// défaisait pas la liste, les pièces ni les actions, déjà enregistrées) ; « Fermer » en haut, Fait, Reporter
/// et ⋯ dans la barre du bas.
struct TaskEditor: View {
    @Environment(\.dismiss) private var dismiss
    let item: TaskItem

    var body: some View {
        NavigationStack {
            TaskDetailView(item: item, onClose: { dismiss() })
                .navigationTitle("Tâche")
                .inlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } }
                }
        }
    }
}
