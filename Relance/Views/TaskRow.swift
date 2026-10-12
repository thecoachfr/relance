import SwiftUI

struct TaskRow: View {
    let item: TaskItem
    var now: Date = .now
    /// Rond à cocher, comme dans Rappels : le geste de balayage seul ne se découvre pas.
    var onDone: ((TaskItem) -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if let onDone {
                Button { onDone(item) } label: {
                    PriorityCircle(priority: item.priority, late: item.isOverdue(now: now))
                        .font(.title2)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .hoverEffect(.highlight)
                .padding(.leading, -10)
                .accessibilityLabel("Marquer comme faite")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title.isEmpty ? "Sans titre" : item.title)
                    .font(.body)
                    .foregroundStyle(item.priority == .low ? .secondary : .primary)
                // Étiquette sous le statut, comme les tags dans Rappels : rien n'est jamais coupé.
                statusLabel
                if let category = item.category { CategoryChip(name: category) }
            }
            .accessibilityElement(children: .combine)
            // La priorité ne se voit qu'au rond : VoiceOver la dit en clair.
            .accessibilityValue(item.priority == .normal ? "" : "Priorité \(item.priority.rawValue)")
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var statusLabel: some View {
        if let status {
            // Pas de `Label` : dans une liste, il réserve une colonne d'icône trop large.
            HStack(spacing: 5) {
                Image(systemName: status.symbol).imageScale(.small)
                Text(status.text)
            }
            .font(.subheadline)
            .foregroundStyle(status.color)
        }
    }

    /// Même texte que dans les widgets et l'activité en direct (`DueText`).
    private var status: (text: String, symbol: String, color: Color)? {
        guard let due = item.dueInstant() else { return nil }
        let text = DueText.long(due: due, hasTime: item.dueMinutes != nil, now: now)
        if item.isOverdue(now: now) { return (text, "clock.fill", .red) }
        let symbol = Calendar.current.isDateInToday(item.dueDay!) ? "clock" : "calendar"
        return (text, symbol, .secondary)
    }
}

/// Actions communes aux listes : glisser à droite = Fait, à gauche = Reporter, appui long = menu.
struct TaskActions: ViewModifier {
    @Environment(TaskStore.self) private var store
    let item: TaskItem
    var onDone: (TaskItem) -> Void
    var onEdit: (TaskItem) -> Void

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture { onEdit(item) }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button("Fait", systemImage: "checkmark") { onDone(item) }
                    .tint(.green)
                if item.priority == .urgent {
                    Button("Normale", systemImage: "minus") { store.setPriority(item, .normal) }
                        .tint(.gray)
                } else {
                    Button("Urgente", systemImage: "exclamationmark") { store.setPriority(item, .urgent) }
                        .tint(.red)
                }
            }
            .swipeActions(edge: .trailing) {
                Button("Demain", systemImage: "sunrise") { store.moveToTomorrow(item) }
                    .tint(.indigo)
                Button("1 h", systemImage: "clock") { store.snooze(item, until: .now.addingTimeInterval(3600)) }
                    .tint(.orange)
            }
            .contextMenu {
                Button("Fait", systemImage: "checkmark") { onDone(item) }
                Button("Dans 1 h", systemImage: "clock") { store.snooze(item, until: .now.addingTimeInterval(3600)) }
                Button("Demain matin", systemImage: "sunrise") { store.moveToTomorrow(item) }
                Picker("Priorité", systemImage: "exclamationmark.circle",
                       selection: Binding(get: { item.priority }, set: { store.setPriority(item, $0) })) {
                    ForEach(TaskPriority.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
                }
                .pickerStyle(.menu)
                Button("Modifier", systemImage: "pencil") { onEdit(item) }
                Button("Supprimer", systemImage: "trash", role: .destructive) { store.delete(item) }
            }
            .accessibilityAction(named: "Fait") { onDone(item) }
            .accessibilityAction(named: "Reporter à demain") { store.moveToTomorrow(item) }
            .accessibilityAction(named: item.priority == .urgent ? "Priorité normale" : "Marquer urgente") {
                store.setPriority(item, item.priority == .urgent ? .normal : .urgent)
            }
    }
}

extension View {
    func taskActions(_ item: TaskItem, onDone: @escaping (TaskItem) -> Void, onEdit: @escaping (TaskItem) -> Void) -> some View {
        modifier(TaskActions(item: item, onDone: onDone, onEdit: onEdit))
    }
}
