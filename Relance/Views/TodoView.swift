import SwiftData
import SwiftUI

struct TodoView: View {
    @Environment(TaskStore.self) private var store
    @Query(filter: #Predicate<TaskItem> { !$0.isCompleted && !$0.isTrashed && $0.dueDay != nil },
           sort: \TaskItem.dueDay)
    private var dated: [TaskItem]

    @State private var showAdd = false
    @State private var showSettings = false
    @State private var editing: TaskItem?
    @State private var justDone: TaskItem?

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { context in
                let now = context.date
                let groups = group(now: now)
                List {
                    section("En retard", groups.overdue, now: now)
                    section("Aujourd'hui", groups.today, now: now)
                    section("Bientôt", groups.later, now: now)
                }
                .overlay {
                    if dated.isEmpty {
                        ContentUnavailableView("Rien d'urgent", systemImage: "checkmark.circle",
                                               description: Text("Les tâches avec une date apparaissent ici."))
                    }
                }
            }
            .navigationTitle("À faire")
            .refreshable { await store.sync() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Réglages", systemImage: "gearshape") { showSettings = true }
                }
                // La barre d'onglets d'iOS 26 masque la barre d'outils du bas : l'ajout va en haut à droite.
                ToolbarItem(placement: .primaryAction) {
                    Button("Nouvelle tâche", systemImage: "plus") { showAdd = true }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut("n", modifiers: .command)
                }
            }
            .safeAreaInset(edge: .bottom) { undoBanner }
            .sheet(isPresented: $showAdd) { QuickAddSheet() }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(item: $editing) { TaskEditor(item: $0) }
            .sensoryFeedback(.success, trigger: justDone)
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [TaskItem], now: Date) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { item in
                    TaskRow(item: item, now: now, onDone: markDone)
                        .taskActions(item, onDone: markDone, onEdit: { editing = $0 })
                }
            }
        }
    }

    private func group(now: Date) -> (overdue: [TaskItem], today: [TaskItem], later: [TaskItem]) {
        let calendar = Calendar.current
        let sorted = dated.sorted { ($0.dueInstant() ?? .distantFuture) < ($1.dueInstant() ?? .distantFuture) }
        let overdue = sorted.filter { $0.isOverdue(now: now) }
        let rest = sorted.filter { !$0.isOverdue(now: now) }
        return (overdue,
                rest.filter { calendar.isDateInToday($0.dueDay!) },
                rest.filter { !calendar.isDateInToday($0.dueDay!) })
    }

    private func markDone(_ item: TaskItem) {
        withAnimation { store.complete(item) }
        justDone = item
        Task {
            try? await Task.sleep(for: .seconds(4))
            if justDone == item { withAnimation { justDone = nil } }
        }
    }

    /// Annuler plutôt que confirmer (HIG).
    @ViewBuilder
    private var undoBanner: some View {
        if let item = justDone {
            HStack {
                Text("« \(item.title) » fait").lineLimit(1)
                Spacer()
                Button("Annuler") {
                    withAnimation {
                        store.reopen(item)
                        justDone = nil
                    }
                }
                .bold()
            }
            .padding()
            .background(.regularMaterial, in: .rect(cornerRadius: 14))
            .padding(.horizontal)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
