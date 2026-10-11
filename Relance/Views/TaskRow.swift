import SwiftUI

struct TaskRow: View {
    let item: TaskItem
    var now: Date = .now

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title.isEmpty ? "Sans titre" : item.title)
                .font(.body)
            if let status {
                Label(status.text, systemImage: status.symbol)
                    .font(.subheadline)
                    .foregroundStyle(status.color)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var status: (text: String, symbol: String, color: Color)? {
        guard let day = item.dueDay else { return nil }
        let calendar = Calendar.current
        let time = item.dueMinutes.map { " à " + ReminderPlanner.formatTime($0) } ?? ""

        if item.isOverdue(now: now) {
            let days = calendar.dateComponents([.day], from: day, to: calendar.startOfDay(for: now)).day ?? 0
            let text = switch days {
            case ..<1: "En retard · prévu\(time)"
            case 1: "En retard · depuis hier"
            default: "En retard · \(days) jours"
            }
            return (text, "exclamationmark.circle.fill", .red)
        }
        if calendar.isDateInToday(day) { return ("Aujourd'hui\(time)", "clock", .secondary) }
        if calendar.isDateInTomorrow(day) { return ("Demain\(time)", "calendar", .secondary) }
        return (day.formatted(.dateTime.weekday(.wide).day().month(.wide)) + time, "calendar", .secondary)
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
                Button("Modifier", systemImage: "pencil") { onEdit(item) }
                Button("Supprimer", systemImage: "trash", role: .destructive) { store.delete(item) }
            }
            .accessibilityAction(named: "Fait") { onDone(item) }
            .accessibilityAction(named: "Reporter à demain") { store.moveToTomorrow(item) }
    }
}

extension View {
    func taskActions(_ item: TaskItem, onDone: @escaping (TaskItem) -> Void, onEdit: @escaping (TaskItem) -> Void) -> some View {
        modifier(TaskActions(item: item, onDone: onDone, onEdit: onEdit))
    }
}
