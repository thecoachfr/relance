import AppIntents
import SwiftUI
import WidgetKit

/// Complication : nombre de tâches en retard et la prochaine, lus dans la copie locale de la montre.
struct ComplicationEntry: TimelineEntry {
    var date: Date
    var tasks: [WatchTask]
    /// Libellés des jours travaillés reçus de l'iPhone (P9-N2), par date `AAAA-MM-JJ`.
    var lieux: [String: String] = [:]

    /// « 🏢 Bureau », « 🏠 Télétravail »… le jour de l'entrée s'il est travaillé ; `nil` sinon (rien d'affiché).
    var lieu: String? { WatchLink.libelleDuJour(lieux, date: date) }

    var late: [WatchTask] {
        tasks.filter { $0.isLate(at: date) && ($0.snoozedUntil ?? .distantPast) <= date }
    }
    var next: WatchTask? {
        tasks.filter { $0.due != nil }.sorted { $0.due! < $1.due! }.first
    }

    /// En retard (hors reports en cours) puis à faire aujourd'hui ; l'urgent d'abord.
    var today: [WatchTask] {
        let calendar = Calendar.current
        return tasks.filter { task in
            guard let due = task.due, (task.snoozedUntil ?? .distantPast) <= date else { return false }
            let day = task.hasTime ? due : due.addingTimeInterval(-1)
            return task.isLate(at: date) || calendar.isDate(day, inSameDayAs: date)
        }
        .sorted { a, b in
            let lateA = a.isLate(at: date), lateB = b.isLate(at: date)
            if lateA != lateB { return lateA }
            if a.isUrgent != b.isUrgent { return a.isUrgent }
            return a.due! < b.due!
        }
    }

    /// Place du widget dans la pile intelligente : en tête quand une tâche est en retard
    /// ou arrive dans l'heure, discret quand tout est à jour.
    var relevance: TimelineEntryRelevance? {
        if !late.isEmpty { return TimelineEntryRelevance(score: 100) }
        let soon = tasks.compactMap { task -> Date? in
            guard task.hasTime, let due = task.due, due > date, due.timeIntervalSince(date) <= 3600 else { return nil }
            return due
        }.min()
        if let soon { return TimelineEntryRelevance(score: 80, duration: soon.timeIntervalSince(date)) }
        return TimelineEntryRelevance(score: today.isEmpty ? 0 : 20)
    }
}

struct ComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationEntry(date: .now, tasks: [
            WatchTask(id: "1", title: "Appeler le garage", due: .now.addingTimeInterval(-3600), hasTime: true),
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : ComplicationEntry(date: .now, tasks: load(), lieux: loadLieux()))
    }

    /// Une entrée à chaque passage d'une tâche en retard, pour que le compteur change tout seul.
    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        let now = Date.now
        let tasks = load()
        let lieux = loadLieux()
        let horizon = now.addingTimeInterval(24 * 3600)
        var dates = Set([now])
        // Le libellé du lieu de travail change à minuit (calculé d'avance, sans rechargement : budget B6).
        if !lieux.isEmpty { dates.formUnion(WatchLink.minuits(apres: now, jusqua: horizon)) }
        for task in tasks {
            // Une heure avant une tâche avec heure, le widget remonte dans la pile intelligente.
            let early = task.hasTime ? task.due?.addingTimeInterval(-3600) : nil
            for date in [task.due, task.snoozedUntil, early].compactMap({ $0 }) where date > now && date < horizon {
                dates.insert(date)
            }
        }
        completion(Timeline(entries: dates.sorted().map { ComplicationEntry(date: $0, tasks: tasks, lieux: lieux) },
                            policy: .after(horizon)))
    }

    private func load() -> [WatchTask] {
        let defaults = Groupes.defaults
        return WatchLink.decode(defaults.data(forKey: "watchTasks"))
    }

    /// Copie de la montre, écrite à chaque envoi de l'iPhone (jours travaillés seulement : l'iPhone filtre).
    private func loadLieux() -> [String: String] {
        WatchLink.decodeLieux(Groupes.defaults.data(forKey: WatchLink.lieuTravailStoreKey))
    }
}

struct RelanceComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "fr.alexandrefau.relance.complication", provider: ComplicationProvider()) { entry in
            ComplicationView(entry: entry)
                .containerBackground(.background, for: .widget)
                .widgetURL(WatchQuickAdd.listURL)
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
            // Lieu de travail du jour en tête (jours travaillés seulement), puis le reste.
            let lieu = entry.lieu.map { $0 + " · " } ?? ""
            if let next = entry.next {
                Text(lieu + (late > 0 ? "\(late) en retard · \(next.title)" : next.title))
            } else {
                Text(lieu + "Rien d'urgent")
            }
        default:
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(late > 0 ? "\(late) en retard" : "Aiguillage").font(.headline).widgetAccentable()
                    Spacer(minLength: 2)
                    if let lieu = entry.lieu {
                        Text(lieu).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            .accessibilityLabel("Aujourd'hui : \(lieu)")
                    }
                }
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

/// Les tâches du jour (3 au plus) : le widget qui remonte dans la pile intelligente.
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "fr.alexandrefau.relance.today", provider: ComplicationProvider()) { entry in
            TodayView(entry: entry)
                .containerBackground(.background, for: .widget)
                .widgetURL(WatchQuickAdd.listURL)
        }
        .configurationDisplayName("Aujourd'hui")
        .description("Les tâches en retard et celles du jour, l'urgent d'abord.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct TodayView: View {
    let entry: ComplicationEntry

    var body: some View {
        let tasks = entry.today
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text("Aujourd'hui").font(.headline)
                    .foregroundStyle(Color(red: 1, green: 0.478, blue: 0.314))  // orange de la charte (#FF7A50)
                    .widgetAccentable()
                Spacer(minLength: 4)
                // Lieu de travail du jour (P9-N2), jours travaillés seulement : discret, à droite du titre.
                if let lieu = entry.lieu {
                    Text(lieu).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        .accessibilityLabel("Aujourd'hui : \(lieu)")
                }
                if tasks.count > 3 {
                    Text("+\(tasks.count - 3)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            if tasks.isEmpty {
                Text("Rien d'autre aujourd'hui").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(tasks.prefix(3)) { task in
                let late = task.isLate(at: entry.date)
                HStack(spacing: 4) {
                    Circle()
                        .fill(late || task.isUrgent ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                        .frame(width: 5, height: 5)
                    Text(task.title).font(.caption).lineLimit(1)
                    Spacer(minLength: 2)
                    if late {
                        Text("retard").font(.system(size: 12)).foregroundStyle(.red).layoutPriority(1)
                    } else if task.hasTime, let due = task.due {
                        // Plus discrète que le titre : c'est la tâche qu'on doit lire d'abord.
                        Text(DueText.clock(due)).font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary)
                            .layoutPriority(1)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Complication « + » : ouvre directement la saisie d'une tâche.
struct AddComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "fr.alexandrefau.relance.add", provider: AddProvider()) { _ in
            AddView()
                .containerBackground(.background, for: .widget)
                .widgetURL(WatchQuickAdd.url)
        }
        .configurationDisplayName("Nouvelle tâche")
        .description("Ouvre la saisie d'une tâche.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
    }
}

struct AddProvider: TimelineProvider {
    struct Entry: TimelineEntry { var date: Date }
    func placeholder(in context: Context) -> Entry { Entry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(Entry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [Entry(date: .now)], policy: .never))
    }
}

struct AddView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCorner:
            Image(systemName: "plus").font(.title.bold())
                .widgetAccentable()
                .widgetLabel("Nouvelle tâche")
                .accessibilityLabel("Nouvelle tâche")
        default:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "plus").font(.title2.bold())
            }
            .widgetAccentable()
            .accessibilityLabel("Nouvelle tâche")
        }
    }
}

/// Centre de contrôle et bouton Action de la montre (watchOS 26).
@available(watchOS 26.0, *)
struct WatchNewTaskControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "fr.alexandrefau.relance.watch.newtask") {
            ControlWidgetButton(action: WatchNewTaskIntent()) {
                Label("Nouvelle tâche", systemImage: "plus.circle")
            }
        }
        .displayName("Nouvelle tâche")
        .description("Note une tâche dans Aiguillage.")
    }
}

@main
struct RelanceWatchWidgets: WidgetBundle {
    var body: some Widget {
        RelanceComplication()
        TodayWidget()
        AddComplication()
        if #available(watchOS 26.0, *) {
            WatchNewTaskControl()
        }
    }
}
