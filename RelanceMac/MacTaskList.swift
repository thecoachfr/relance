import SwiftData
import SwiftUI

/// Colonne du milieu : les tâches de la liste choisie, regroupées par échéance.
struct MacTaskList: View {
    @Environment(TaskStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    @Query(filter: #Predicate<TaskItem> { !$0.isTrashed }, sort: \TaskItem.updatedAt, order: .reverse)
    private var all: [TaskItem]

    let section: MacSection
    let search: String
    @Binding var selection: UUID?

    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = context.date
            let items = filtered
            List(selection: $selection) {
                if section == .done {
                    ForEach(items.prefix(200)) { doneRow($0) }
                } else {
                    // Bureau ou télétravail (P9-N2), en tête de « À faire ».
                    if section == .todo { LieuTravailBandeau() }
                    let groups = Self.group(items, now: now)
                    ForEach(groups, id: \.title) { group in
                        Section {
                            ForEach(group.items) { item in
                                TaskRow(item: item, now: now, isSelected: selection == item.localID, onDone: complete)
                                    // Le Mac ajoute de l'air au-dessus de la première ligne d'une section :
                                    // on le retire, pour le même écart qu'entre deux tâches.
                                    .padding(.top, item.localID == group.items.first?.localID ? -8 : 0)
                                    .tag(item.localID)
                                    .macTaskMenu(item, onDone: complete)
                            }
                        } header: {
                            Text(group.title)
                        }
                    }
                }
            }
            .listStyle(.inset)
            // Pastille du lieu à côté de la date de chaque tâche (P9-N2 : jours travaillés, mode HA seulement).
            .environment(\.lieuTravailDesJours, store.isHAActive && section != .done ? store.lieuTravail : nil)
            .overlay { if items.isEmpty { empty } }
            .navigationTitle(section.title)
            .navigationSubtitle(subtitle(items, now: now))
        }
    }

    // MARK: - Contenu

    private var filtered: [TaskItem] {
        let query = search.trimmingCharacters(in: .whitespaces)
        let base: [TaskItem] = switch section {
        case .todo: all.filter { !$0.isCompleted && $0.dueDay != nil }
        case .inbox: all.filter { !$0.isCompleted && $0.needsTriage }
        case .map, .toSee: []
        case .done: all.filter(\.isCompleted).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        case .category(let name): all.filter { !$0.isCompleted && $0.category == name }
        case .tag(let tag): all.filter { !$0.isCompleted && $0.matches(categoryFilter: "#" + tag) }
        }
        guard !query.isEmpty else { return base }
        return base.filter { $0.title.localizedStandardContains(query) || $0.notes.localizedStandardContains(query) }
    }

    /// En retard, Aujourd'hui, Bientôt, Sans date ; dans chaque groupe les urgentes d'abord, puis par échéance.
    static func group(_ items: [TaskItem], now: Date) -> [(title: String, items: [TaskItem])] {
        let calendar = Calendar.current
        let sorted = items.sorted { a, b in
            if a.priority.rank != b.priority.rank { return a.priority.rank < b.priority.rank }
            return (a.dueInstant() ?? .distantFuture) < (b.dueInstant() ?? .distantFuture)
        }
        // Rappels « pour info » (P9-P) : ceux du jour à part, en tête ; ceux à venir dans « Bientôt » (pour les
        // retrouver) ; une info passée pas encore avancée nulle part.
        let infos = sorted.filter { $0.pourInfoDuJour(now: now) }
        let today = calendar.startOfDay(for: now)
        let taches = sorted.filter { !$0.estPourInfo || (!$0.pourInfoDuJour(now: now) && ($0.dueDay ?? today) > today) }
        let overdue = taches.filter { $0.isOverdue(now: now) }
        let dated = taches.filter { $0.dueDay != nil && !$0.isOverdue(now: now) }
        return [
            ("Pour info", infos),
            ("En retard", overdue),
            ("Aujourd'hui", dated.filter { calendar.isDateInToday($0.dueDay!) }),
            ("Bientôt", dated.filter { !calendar.isDateInToday($0.dueDay!) }),
            ("Sans date", taches.filter { $0.dueDay == nil }),
        ].filter { !$0.1.isEmpty }
    }

    private func subtitle(_ items: [TaskItem], now: Date) -> String {
        if section == .done { return "" }
        let late = items.filter { $0.isOverdue(now: now) }.count
        let count = items.count == 1 ? "1 tâche" : "\(items.count) tâches"
        return late > 0 ? "\(count), \(late) en retard" : count
    }

    @ViewBuilder private var empty: some View {
        if !search.trimmingCharacters(in: .whitespaces).isEmpty {
            ContentUnavailableView.search(text: search)
        } else {
            switch section {
            case .todo: ContentUnavailableView("Rien d'urgent", systemImage: "checkmark.circle",
                                               description: Text("Les tâches avec une date apparaissent ici."))
            case .inbox: ContentUnavailableView("Rien à trier", systemImage: "tray",
                                                description: Text("Les tâches sans date ou sans heure arrivent ici."))
            case .done: ContentUnavailableView("Rien de fait pour l'instant", systemImage: "checkmark.circle")
            default: ContentUnavailableView("Aucune tâche en « \(section.title) »", systemImage: "line.3.horizontal.decrease.circle")
            }
        }
    }

    private func doneRow(_ item: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.title).strikethrough().foregroundStyle(.secondary)
            if let date = item.completedAt {
                Text(date, format: .relative(presentation: .named))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .tag(item.localID)
        .contextMenu {
            Button("Remettre à faire", systemImage: "arrow.uturn.backward") { store.reopen(item) }
        }
    }

    // MARK: - Actions

    /// Cocher se défait avec ⌘Z, comme partout sur Mac.
    private func complete(_ item: TaskItem) {
        withAnimation { store.complete(item) }
        undoManager?.registerUndo(withTarget: store) { store in
            MainActor.assumeIsolated { withAnimation { store.reopen(item) } }
        }
        undoManager?.setActionName("Marquer fait")
    }
}

/// Clic droit sur une tâche ; balayage au trackpad comme sur iPhone.
private struct MacTaskMenu: ViewModifier {
    @Environment(TaskStore.self) private var store
    @Environment(\.deleteTask) private var deleteTask
    let item: TaskItem
    let onDone: (TaskItem) -> Void

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button("Marquer fait", systemImage: "checkmark") { onDone(item) }
                Button("Dans 1 h", systemImage: "clock") { store.snooze(item, until: .now.addingTimeInterval(3600)) }
                Button("Demain matin", systemImage: "sunrise") { store.moveToTomorrow(item) }
                Picker("Priorité", systemImage: "exclamationmark.circle",
                       selection: Binding(get: { item.priority }, set: { store.setPriority(item, $0) })) {
                    ForEach(TaskPriority.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
                }
                Divider()
                Button("Supprimer", systemImage: "trash", role: .destructive) {
                    if let deleteTask { deleteTask(item) } else { store.delete(item) }
                }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button("Fait", systemImage: "checkmark") { onDone(item) }.tint(.green)
            }
            .swipeActions(edge: .trailing) {
                Button("Demain", systemImage: "sunrise") { store.moveToTomorrow(item) }.tint(.indigo)
                Button("1 h", systemImage: "clock") { store.snooze(item, until: .now.addingTimeInterval(3600)) }.tint(.orange)
            }
    }
}

private extension View {
    func macTaskMenu(_ item: TaskItem, onDone: @escaping (TaskItem) -> Void) -> some View {
        modifier(MacTaskMenu(item: item, onDone: onDone))
    }
}

extension EnvironmentValues {
    /// Même action que `FocusedValues.deleteTask`, pour le clic droit dans la liste.
    @Entry var deleteTask: ((TaskItem) -> Void)?
}
