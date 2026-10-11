import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

typealias ActivityItem = TaskActivityAttributes.ContentState.Item

/// Une tâche : vue détaillée avec deux grands boutons.
/// Plusieurs : liste de 3 au plus, chacune avec son rond « Fait » et son bouton « 1 h ».
/// (Apple limite la hauteur à 160 pt sur l'écran verrouillé.)
struct TaskLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TaskActivityAttributes.self) { context in
            Group {
                if context.state.items.count == 1, let item = context.state.items.first {
                    SingleTaskView(item: item)
                } else {
                    TaskListView(state: context.state, maxRows: 3)
                }
            }
            .padding(12)
            .activityBackgroundTint(nil)
        } dynamicIsland: { context in
            let state = context.state
            let late = state.items.filter { isLate($0) }.count
            return DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    if state.items.count == 1, let item = state.items.first {
                        SingleTaskView(item: item)
                    } else {
                        TaskListView(state: state, maxRows: 2)
                    }
                }
            } compactLeading: {
                Image(systemName: late > 0 ? "exclamationmark.circle.fill" : "clock")
                    .foregroundStyle(late > 0 ? .red : .orange)
            } compactTrailing: {
                // Un nombre se lit d'un coup d'œil ; un titre tronqué à 60 pt, non.
                Text("\(state.total)").font(.body.bold().monospacedDigit())
                    .foregroundStyle(late > 0 ? .red : .orange)
                    .accessibilityLabel("\(state.total) tâches urgentes")
            } minimal: {
                Text("\(state.total)").font(.body.bold().monospacedDigit())
                    .foregroundStyle(late > 0 ? .red : .orange)
            }
        }
    }
}

private func isLate(_ item: ActivityItem, now: Date = .now) -> Bool {
    DueText.isLate(due: item.due, now: now) && !item.isSnoozed(at: now)
}

private func statusText(_ item: ActivityItem, long: Bool, now: Date = .now) -> String {
    if let snoozed = item.snoozedUntil, snoozed > now {
        return (long ? "Reportée, relance à " : "relance ") + DueText.clock(snoozed)
    }
    return long ? DueText.long(due: item.due, hasTime: item.hasTime, now: now)
                : DueText.short(due: item.due, hasTime: item.hasTime, now: now)
}

// MARK: - Une seule tâche

private struct SingleTaskView: View {
    let item: ActivityItem

    var body: some View {
        let late = isLate(item)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: late ? "exclamationmark.circle.fill" : "clock")
                    .foregroundStyle(late ? .red : .orange)
                Text(item.title).font(.headline).lineLimit(2)
            }
            Text(statusText(item, long: true))
                .font(.subheadline)
                .foregroundStyle(late ? .red : .secondary)
            HStack {
                Button(intent: CompleteTaskIntent(taskID: item.id)) {
                    Label("Fait", systemImage: "checkmark").frame(maxWidth: .infinity)
                }
                .tint(.green)
                Button(intent: SnoozeTaskIntent(taskID: item.id)) {
                    Label("Dans 1 h", systemImage: "clock").frame(maxWidth: .infinity)
                }
                .tint(.orange)
            }
            .buttonStyle(.borderedProminent)
            .font(.subheadline.weight(.semibold))
        }
    }
}

// MARK: - Plusieurs tâches

private struct TaskListView: View {
    let state: TaskActivityAttributes.ContentState
    let maxRows: Int

    var body: some View {
        let rows = Array(state.items.prefix(maxRows))
        let late = state.items.filter { isLate($0) }.count
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(late > 0 ? "\(late) en retard" : "\(state.total) à faire bientôt")
                    .font(.subheadline.bold())
                    .foregroundStyle(late > 0 ? .red : .orange)
                Spacer()
                if state.total > rows.count {
                    Text("+\(state.total - rows.count) autres").font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(rows) { item in
                TaskLine(item: item)
            }
        }
    }
}

private struct TaskLine: View {
    let item: ActivityItem

    var body: some View {
        let late = isLate(item)
        HStack(spacing: 10) {
            Button(intent: CompleteTaskIntent(taskID: item.id)) {
                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundStyle(late ? .red : .secondary)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Marquer « \(item.title) » comme faite")

            Text(item.title).font(.subheadline).lineLimit(1)
            Spacer(minLength: 6)
            Text(statusText(item, long: false))
                .font(.caption.monospacedDigit())
                .foregroundStyle(late ? .red : .secondary)
                .lineLimit(1)

            Button(intent: SnoozeTaskIntent(taskID: item.id)) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.subheadline)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.orange)
            .accessibilityLabel("Reporter « \(item.title) » d'une heure")
        }
        .frame(height: 34)
    }
}
