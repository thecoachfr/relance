import SwiftData
import SwiftUI

/// Historique de ce qui est fait, ouvert depuis le bas de « À faire » (feuille).
struct DoneView: View {
    @Environment(TaskStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<TaskItem> { $0.isCompleted && !$0.isTrashed },
           sort: \TaskItem.completedAt, order: .reverse)
    private var items: [TaskItem]
    @State private var width: CGFloat = 0
    @State private var editing: TaskItem?

    var body: some View {
        NavigationStack {
            List(items.prefix(100)) { item in
                // Toucher la ligne ouvre le détail : notes, lieu, catégorie… et « Marquer à faire ».
                Button { editing = item } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title).strikethrough().foregroundStyle(.secondary)
                        if let date = item.completedAt {
                            Text(date, format: .relative(presentation: .named))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Ouvre le détail de la tâche")
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button("Remettre à faire", systemImage: "arrow.uturn.backward") { store.reopen(item) }
                        .tint(.blue)
                }
                .accessibilityAction(named: "Remettre à faire") { store.reopen(item) }
                // Le balayage ne marche pas au trackpad : clic droit / appui long.
                .contextMenu {
                    Button("Remettre à faire", systemImage: "arrow.uturn.backward") { store.reopen(item) }
                }
            }
            // Largeur de lecture sur grand écran, sans casser le fond de la liste.
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .contentMargins(.horizontal, max(0, (width - 700) / 2), for: .scrollContent)
            .overlay {
                if items.isEmpty {
                    ContentUnavailableView("Rien de fait pour l'instant", systemImage: "checkmark.circle")
                }
            }
            .navigationTitle("Fait")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } }
            }
            .sheet(item: $editing) { TaskEditor(item: $0) }
        }
    }
}
