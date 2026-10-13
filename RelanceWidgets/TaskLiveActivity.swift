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
            ActivityContent(state: context.state)
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
        // Sans .small, la montre (Smart Stack) n'affiche que l'icône et le nombre de la Dynamic Island.
        .supplementalActivityFamilies([.small, .medium])
    }
}

/// Écran verrouillé (.medium) ou Apple Watch (.small).
private struct ActivityContent: View {
    let state: TaskActivityAttributes.ContentState
    @Environment(\.activityFamily) private var family

    var body: some View {
        switch family {
        case .small:
            Group {
                if state.items.count == 1, let item = state.items.first {
                    SmallSingleTaskView(item: item)
                } else {
                    SmallTaskListView(state: state)
                }
            }
            .padding(8)
        default:
            Group {
                if state.items.count == 1, let item = state.items.first {
                    SingleTaskView(item: item)
                } else {
                    TaskListView(state: state, maxRows: 3)
                }
            }
            .padding(12)
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
                if item.isUrgent { UrgentMark() }
            }
            Text(statusText(item, long: true))
                .font(.subheadline)
                .foregroundStyle(late ? .red : .secondary)
            HStack {
                Button(intent: CompleteTaskIntent(taskID: item.id)) {
                    Label("Fait", systemImage: "checkmark").frame(maxWidth: .infinity)
                }
                .tint(.green)
                SecondButton(item: item, short: false)
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
                PriorityCircle(priority: item.isUrgent ? .urgent : .normal, late: late)
                    .font(.title3)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Marquer « \(item.title) » comme faite\(item.isUrgent ? ", urgente" : "")")

            Text(item.title).font(.subheadline).lineLimit(1)
            Spacer(minLength: 6)
            Text(statusText(item, long: false))
                .font(.caption.monospacedDigit())
                .foregroundStyle(late ? .red : .secondary)
                .lineLimit(1)

            SecondIconButton(item: item)
        }
        .frame(height: 34)
    }
}


// MARK: - Apple Watch (Smart Stack)

/// Une tâche : titre, échéance et deux boutons assez grands pour le poignet.
private struct SmallSingleTaskView: View {
    let item: ActivityItem

    var body: some View {
        let late = isLate(item)
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if item.isUrgent { UrgentMark() }
                Text(item.title).font(.headline).lineLimit(2)
            }
            Text(statusText(item, long: false))
                .font(.caption.monospacedDigit())
                .foregroundStyle(late ? .red : .orange)
            HStack(spacing: 6) {
                Button(intent: CompleteTaskIntent(taskID: item.id)) {
                    Label("Fait", systemImage: "checkmark").frame(maxWidth: .infinity)
                }
                .tint(.green)
                SecondButton(item: item, short: true)
            }
            .buttonStyle(.borderedProminent)
            .font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Plusieurs tâches : le compte, puis les deux plus urgentes (titre et échéance).
private struct SmallTaskListView: View {
    let state: TaskActivityAttributes.ContentState

    var body: some View {
        let late = state.items.filter { isLate($0) }.count
        VStack(alignment: .leading, spacing: 3) {
            Label(late > 0 ? "\(late) en retard" : "\(state.total) à faire",
                  systemImage: late > 0 ? "exclamationmark.circle.fill" : "clock")
                .font(.caption.bold())
                .foregroundStyle(late > 0 ? .red : .orange)
            ForEach(state.items.prefix(2)) { item in
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if item.isUrgent { UrgentMark() }
                    Text(item.title).font(.footnote).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(statusText(item, long: false))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(isLate(item) ? .red : .secondary)
                        .lineLimit(1)
                }
            }
            if state.total > 2 {
                Text("+\(state.total - 2) autres").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// « ! » rouge des tâches urgentes, là où il n'y a pas de rond à cocher (vues à une tâche, montre).
private struct UrgentMark: View {
    var body: some View {
        Image(systemName: "exclamationmark")
            .font(.caption.weight(.heavy))
            .foregroundStyle(.red)
            .accessibilityLabel("Urgente")
    }
}

// MARK: - Second bouton, selon le moment

/// Avant l'heure : « Plus tard » (retire la tâche de l'activité) ou « Itinéraire » dans les 2 h s'il y a
/// une adresse. À l'heure ou en retard : « Dans 1 h ». (Avant l'heure, « Dans 1 h » ajoutait un rappel
/// sans rien décaler.)
private struct SecondButton: View {
    let item: ActivityItem
    let short: Bool

    var body: some View {
        switch item.secondAction(at: .now) {
        case .later:
            Button(intent: HideTaskIntent(taskID: item.id)) {
                Label("Plus tard", systemImage: "eye.slash").frame(maxWidth: .infinity)
            }
            .tint(.gray)
        case .route(let url):
            Button(intent: OpenURLIntent(url)) {
                Label(short ? "Trajet" : "Itinéraire", systemImage: "map").frame(maxWidth: .infinity)
            }
            .tint(.blue)
        case .snooze:
            Button(intent: SnoozeTaskIntent(taskID: item.id)) {
                Label(short ? "1 h" : "Dans 1 h", systemImage: "clock").frame(maxWidth: .infinity)
            }
            .tint(.orange)
        }
    }
}

/// Même choix en icône seule, pour les lignes de la liste.
private struct SecondIconButton: View {
    let item: ActivityItem

    var body: some View {
        switch item.secondAction(at: .now) {
        case .later:
            icon(intent: HideTaskIntent(taskID: item.id), symbol: "eye.slash", color: .secondary,
                 label: "Masquer « \(item.title) » jusqu'à plus tard")
        case .route(let url):
            icon(intent: OpenURLIntent(url), symbol: "map", color: .blue, label: "Itinéraire vers « \(item.title) »")
        case .snooze:
            icon(intent: SnoozeTaskIntent(taskID: item.id), symbol: "clock.arrow.circlepath", color: .orange,
                 label: "Reporter « \(item.title) » d'une heure")
        }
    }

    private func icon(intent: some AppIntent, symbol: String, color: Color, label: String) -> some View {
        Button(intent: intent) {
            Image(systemName: symbol)
                .font(.subheadline)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(color)
        .accessibilityLabel(label)
    }
}
