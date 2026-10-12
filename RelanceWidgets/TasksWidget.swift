import AppIntents
import SwiftUI
import WidgetKit

struct TasksWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "fr.alexandrefau.relance.tasks", provider: TasksProvider()) { entry in
            TasksWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("À faire")
        .description("Tes tâches en retard et du jour, à cocher sans ouvrir l'app.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct TasksWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TasksEntry

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: inline
        case .systemSmall: small
        default: list(limit: family == .systemLarge ? 9 : 3)
        }
    }

    // MARK: - Écran verrouillé

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: entry.overdue.isEmpty ? "checkmark" : "exclamationmark")
                    .font(.caption.bold())
                Text("\(entry.overdue.count)").font(.title2.bold())
            }
        }
        .accessibilityLabel("\(entry.overdue.count) en retard")
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(headline).font(.headline).widgetAccentable()
            ForEach(entry.ordered.prefix(2)) { task in
                Text(task.title).font(.caption).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inline: some View {
        if let next = entry.ordered.first {
            Text("\(headline) · \(next.title)")
        } else {
            Text("Rien d'urgent")
        }
    }

    // MARK: - Écran d'accueil

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            if entry.tasks.isEmpty {
                Image(systemName: "checkmark.circle.fill").font(.title).foregroundStyle(.green)
                Spacer()
                Text("Rien d'urgent").font(.headline)
            } else {
                Text("\(entry.overdue.count)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(entry.overdue.isEmpty ? Color.primary : .red)
                Text("en retard").font(.subheadline).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if let next = entry.ordered.first {
                    Text(next.title).font(.footnote.weight(.semibold)).lineLimit(2)
                    HStack(spacing: 4) {
                        CategoryMark(name: next.category)
                        Text(DueText.short(due: next.due, hasTime: next.hasTime, now: entry.date))
                            .foregroundStyle(next.due < entry.date ? .red : .secondary)
                    }
                    .font(.caption2)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Une ligne par tâche (titre + échéance courte) : 3 tiennent dans le format moyen sans couper le titre.
    private func list(limit: Int) -> some View {
        let rows = Array(entry.ordered.prefix(limit))
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(headline).font(.subheadline.bold())
                    .foregroundStyle(entry.overdue.isEmpty ? Color.primary : .red)
                Spacer()
                if entry.tasks.count > rows.count {
                    Text("+\(entry.tasks.count - rows.count) autres").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 2)
            if entry.tasks.isEmpty {
                Spacer()
                Label("Rien d'urgent", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(rows) { task in
                    let late = task.due < entry.date
                    HStack(spacing: 8) {
                        Button(intent: CompleteTaskIntent(taskID: task.id)) {
                            PriorityCircle(priority: task.isUrgent ? .urgent : .normal, late: late)
                                .font(.body)
                                .frame(width: 28, height: 30)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Marquer « \(task.title) » comme faite\(task.isUrgent ? ", urgente" : "")")

                        Text(task.title).font(.subheadline).lineLimit(1)
                        Spacer(minLength: 4)
                        CategoryMark(name: task.category)
                        Text(DueText.short(due: task.due, hasTime: task.hasTime, now: entry.date))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(late ? .red : .secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Textes

    private var headline: String {
        let overdue = entry.overdue.count, today = entry.today.count
        switch (overdue, today) {
        case (0, 0): return entry.tasks.isEmpty ? "Rien d'urgent" : "\(entry.tasks.count) à venir"
        case (0, _): return "\(today) aujourd'hui"
        case (_, 0): return "\(overdue) en retard"
        default: return "\(overdue) en retard · \(today) aujourd'hui"
        }
    }
}

/// Catégorie réduite à son symbole coloré : une ligne de widget n'a pas la place pour le nom.
private struct CategoryMark: View {
    let name: String?

    var body: some View {
        if let name {
            let category = TaskCategory(name: name)
            Image(systemName: category?.symbol ?? "tag")
                .font(.caption2)
                .foregroundStyle(category?.color ?? .gray)
                .widgetAccentable()
                .accessibilityLabel("Catégorie \(name)")
        }
    }
}
