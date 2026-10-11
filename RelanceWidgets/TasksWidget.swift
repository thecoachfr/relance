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
        default: list(limit: family == .systemLarge ? 7 : 3)
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
        VStack(alignment: .leading, spacing: 6) {
            if entry.tasks.isEmpty {
                Image(systemName: "checkmark.circle.fill").font(.title).foregroundStyle(.green)
                Spacer()
                Text("Rien d'urgent").font(.headline)
            } else {
                Text("\(entry.overdue.count)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(entry.overdue.isEmpty ? Color.primary : .red)
                Text("en retard").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                if let next = entry.ordered.first {
                    Text(next.title).font(.footnote.weight(.semibold)).lineLimit(2)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func list(limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(headline).font(.headline)
                .foregroundStyle(entry.overdue.isEmpty ? Color.primary : .red)
            if entry.tasks.isEmpty {
                Spacer()
                Label("Rien d'urgent", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(entry.ordered.prefix(limit)) { task in
                    HStack(spacing: 10) {
                        Button(intent: CompleteTaskIntent(taskID: task.id)) {
                            Image(systemName: "circle").font(.title3)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(task.due < entry.date ? .red : .secondary)
                        .accessibilityLabel("Marquer « \(task.title) » comme faite")

                        VStack(alignment: .leading, spacing: 0) {
                            Text(task.title).font(.subheadline).lineLimit(1)
                            Text(status(task)).font(.caption)
                                .foregroundStyle(task.due < entry.date ? .red : .secondary)
                        }
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
        case (0, 0): return "Rien d'urgent"
        case (0, _): return "\(today) aujourd'hui"
        case (_, 0): return "\(overdue) en retard"
        default: return "\(overdue) en retard · \(today) aujourd'hui"
        }
    }

    private func status(_ task: WidgetTask) -> String {
        let calendar = Calendar.current
        if task.due < entry.date {
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: task.due),
                                               to: calendar.startOfDay(for: entry.date)).day ?? 0
            return days >= 1 ? "En retard · \(days) j" : "En retard"
        }
        let time = task.hasTime ? " à " + task.due.formatted(date: .omitted, time: .shortened) : ""
        if calendar.isDate(task.due, inSameDayAs: entry.date) { return "Aujourd'hui" + time }
        if calendar.isDateInTomorrow(task.due) { return "Demain" + time }
        return task.due.formatted(.dateTime.weekday(.abbreviated).day()) + time
    }
}
