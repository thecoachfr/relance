import SwiftData
import SwiftUI

/// Tâches sans date ou sans heure. Version simple (phase 1) : boutons rapides par ligne.
struct InboxView: View {
    @Environment(TaskStore.self) private var store
    @Query(filter: #Predicate<TaskItem> { !$0.isCompleted && !$0.isTrashed && ($0.dueDay == nil || $0.dueMinutes == nil) },
           sort: \TaskItem.updatedAt, order: .reverse)
    private var items: [TaskItem]
    @State private var editing: TaskItem?

    var body: some View {
        NavigationStack {
            List(items) { item in
                VStack(alignment: .leading, spacing: 10) {
                    TaskRow(item: item)
                    quickButtons(for: item)
                }
                .taskActions(item, onDone: { store.complete($0) }, onEdit: { editing = $0 })
            }
            .overlay {
                if items.isEmpty {
                    ContentUnavailableView("Rien à trier", systemImage: "tray",
                                           description: Text("Les tâches sans date ou sans heure arrivent ici."))
                }
            }
            .navigationTitle("À trier")
            .refreshable { await store.sync() }
            .sheet(item: $editing) { TaskEditor(item: $0) }
        }
    }

    @ViewBuilder
    private func quickButtons(for item: TaskItem) -> some View {
        if item.dueDay == nil {
            HStack {
                Button("Aujourd'hui") { setDay(item, offset: 0) }
                Button("Demain") { setDay(item, offset: 1) }
                Button("Autre…") { editing = item }
            }
            .buttonStyle(.bordered)
            .font(.subheadline)
        } else {
            HStack {
                ForEach(ReminderScheduler.askTimeChoices, id: \.self) { minutes in
                    Button(ReminderPlanner.formatTime(minutes)) { store.setTime(item, minutes: minutes) }
                }
            }
            .buttonStyle(.bordered)
            .font(.subheadline)
        }
    }

    private func setDay(_ item: TaskItem, offset: Int) {
        let today = Calendar.current.startOfDay(for: .now)
        store.update(item, title: item.title, notes: item.notes,
                     day: Calendar.current.date(byAdding: .day, value: offset, to: today), minutes: nil)
    }
}
