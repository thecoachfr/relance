import SwiftUI
import WidgetKit

/// Complication : nombre de tâches en retard et la prochaine, lus dans la copie locale de la montre.
struct ComplicationEntry: TimelineEntry {
    var date: Date
    var tasks: [WatchTask]

    var late: [WatchTask] {
        tasks.filter { $0.isLate(at: date) && ($0.snoozedUntil ?? .distantPast) <= date }
    }
    var next: WatchTask? {
        tasks.filter { $0.due != nil }.sorted { $0.due! < $1.due! }.first
    }
}

struct ComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationEntry(date: .now, tasks: [
            WatchTask(id: "1", title: "Appeler le garage", due: .now.addingTimeInterval(-3600), hasTime: true),
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : ComplicationEntry(date: .now, tasks: load()))
    }

    /// Une entrée à chaque passage d'une tâche en retard, pour que le compteur change tout seul.
    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        let now = Date.now
        let tasks = load()
        let horizon = now.addingTimeInterval(24 * 3600)
        var dates = Set([now])
        for task in tasks {
            for date in [task.due, task.snoozedUntil].compactMap({ $0 }) where date > now && date < horizon {
                dates.insert(date)
            }
        }
        completion(Timeline(entries: dates.sorted().map { ComplicationEntry(date: $0, tasks: tasks) },
                            policy: .after(horizon)))
    }

    private func load() -> [WatchTask] {
        let defaults = UserDefaults(suiteName: "group.fr.alexandrefau.relance") ?? .standard
        return WatchLink.decode(defaults.data(forKey: "watchTasks"))
    }
}

struct RelanceComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "fr.alexandrefau.relance.complication", provider: ComplicationProvider()) { entry in
            ComplicationView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("En retard")
        .description("Le nombre de tâches en retard et la prochaine.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

struct ComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ComplicationEntry

    var body: some View {
        let late = entry.late.count
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: late > 0 ? "exclamationmark" : "checkmark").font(.caption2.bold())
                    Text("\(late)").font(.title3.bold().monospacedDigit())
                }
            }
            .widgetAccentable()
            .accessibilityLabel("\(late) en retard")
        case .accessoryCorner:
            Text("\(late)").font(.title2.bold().monospacedDigit())
                .widgetLabel(late > 0 ? "en retard" : "à jour")
        case .accessoryInline:
            if let next = entry.next {
                Text(late > 0 ? "\(late) en retard · \(next.title)" : next.title)
            } else {
                Text("Rien d'urgent")
            }
        default:
            VStack(alignment: .leading, spacing: 1) {
                Text(late > 0 ? "\(late) en retard" : "Relance").font(.headline).widgetAccentable()
                if let next = entry.next, let due = next.due {
                    Text(next.title).font(.caption).lineLimit(1)
                    Text(DueText.short(due: due, hasTime: next.hasTime, now: entry.date))
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("Rien d'urgent").font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

@main
struct RelanceWatchWidgets: WidgetBundle {
    var body: some Widget {
        RelanceComplication()
    }
}
