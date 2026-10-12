import SwiftData
import SwiftUI

/// Tri une tâche à la fois : lui donner une date, une heure, la cocher ou la jeter.
struct InboxView: View {
    @Environment(TaskStore.self) private var store
    @Query(filter: #Predicate<TaskItem> { !$0.isCompleted && !$0.isTrashed && ($0.dueDay == nil || $0.dueMinutes == nil) },
           sort: \TaskItem.updatedAt)
    private var items: [TaskItem]
    /// Tâches passées pour l'instant : elles reviennent en fin de file.
    @State private var skipped: [UUID] = []
    @State private var editing: TaskItem?

    private var queue: [TaskItem] {
        items.sorted { (skipped.firstIndex(of: $0.localID) ?? -1) < (skipped.firstIndex(of: $1.localID) ?? -1) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let current = queue.first {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            card(for: current)
                            if queue.count > 1 { upNext(Array(queue.dropFirst())) }
                        }
                        .padding()
                        .frame(maxWidth: 600)
                        .frame(maxWidth: .infinity)
                    }
                    .animation(.default, value: current.localID)
                } else {
                    ContentUnavailableView("Rien à trier", systemImage: "tray",
                                           description: Text("Les tâches sans date ou sans heure arrivent ici."))
                }
            }
            .navigationTitle("À trier")
            .refreshable { await store.sync() }
            .sheet(item: $editing) { TaskEditor(item: $0) }
        }
    }

    // MARK: - Carte de la tâche en cours

    private func card(for item: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.dueDay == nil ? "Quand faut-il le faire ?" : "À quelle heure ?")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(item.title.isEmpty ? "Sans titre" : item.title)
                    .font(.title2.bold())
                if !item.notes.isEmpty {
                    Text(item.notes).font(.body).foregroundStyle(.secondary).lineLimit(3)
                }
                if let day = item.dueDay {
                    Label(dayText(day), systemImage: "calendar")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }

            if item.dueDay == nil {
                choiceGrid([
                    ("Aujourd'hui", "sun.max", { setDay(item, offset: 0) }),
                    ("Demain", "sunrise", { setDay(item, offset: 1) }),
                    ("Dans une semaine", "calendar", { setDay(item, offset: 7) }),
                    ("Choisir…", "calendar.badge.plus", { editing = item }),
                ])
            } else {
                choiceGrid(timeChoices(for: item).map { choice in
                    (choice.label, "clock", { store.setTime(item, minutes: choice.minutes) })
                } + [("Autre heure…", "clock.badge", { editing = item })])
            }

            Divider()

            HStack {
                Button("Fait", systemImage: "checkmark") { store.complete(item) }
                Spacer()
                Button("Passer", systemImage: "arrow.uturn.down") { skip(item) }
                Spacer()
                Button("Supprimer", systemImage: "trash", role: .destructive) { store.delete(item) }
            }
            .buttonStyle(.borderless)
            .font(.subheadline)
        }
        .padding(20)
        .background(.background.secondary, in: .rect(cornerRadius: 20))
    }

    private func choiceGrid(_ choices: [(String, String, () -> Void)]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
            ForEach(choices.indices, id: \.self) { i in
                Button(action: choices[i].2) {
                    Label(choices[i].0, systemImage: choices[i].1)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - File d'attente

    private func upNext(_ rest: [TaskItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ensuite · \(rest.count)").font(.headline)
            ForEach(rest) { item in
                Button {
                    skipped = queueOrder(bringingToFront: item)
                } label: {
                    HStack {
                        Text(item.title).lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.up").foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 6)
                .accessibilityHint("Trier cette tâche maintenant")
            }
        }
    }

    /// Ordre de la file où `item` passe devant toutes les autres.
    private func queueOrder(bringingToFront item: TaskItem) -> [UUID] {
        [item.localID] + queue.map(\.localID).filter { $0 != item.localID }
    }

    private func skip(_ item: TaskItem) {
        var order = queue.map(\.localID)
        order.removeAll { $0 == item.localID }
        skipped = order + [item.localID]
    }

    /// Pour aujourd'hui, seulement les heures encore à venir, plus « Dans 1 h ».
    private func timeChoices(for item: TaskItem, now: Date = .now) -> [(label: String, minutes: Int)] {
        let fixed = ReminderScheduler.askTimeChoices.map { (ReminderPlanner.formatTime($0), $0) }
        guard let day = item.dueDay, Calendar.current.isDateInToday(day) else { return fixed }
        let c = Calendar.current.dateComponents([.hour, .minute], from: now)
        let nowMinutes = c.hour! * 60 + c.minute!
        let inOneHour = (nowMinutes + 60 + 4) / 5 * 5
        var choices = fixed.filter { $0.1 > inOneHour }
        if inOneHour < 24 * 60 { choices.insert(("Dans 1 h", inOneHour), at: 0) }
        return choices
    }

    private func dayText(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Aujourd'hui" }
        if calendar.isDateInTomorrow(day) { return "Demain" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    private func setDay(_ item: TaskItem, offset: Int) {
        let today = Calendar.current.startOfDay(for: .now)
        store.update(item, title: item.title, notes: item.notes,
                     day: Calendar.current.date(byAdding: .day, value: offset, to: today), minutes: nil)
    }
}
