import SwiftData
import SwiftUI

struct DoneView: View {
    @Environment(TaskStore.self) private var store
    @Query(filter: #Predicate<TaskItem> { $0.isCompleted && !$0.isTrashed },
           sort: \TaskItem.completedAt, order: .reverse)
    private var items: [TaskItem]
    @State private var width: CGFloat = 0

    var body: some View {
        NavigationStack {
            List(items.prefix(100)) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).strikethrough().foregroundStyle(.secondary)
                    if let date = item.completedAt {
                        Text(date, format: .relative(presentation: .named))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
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
        }
    }
}
