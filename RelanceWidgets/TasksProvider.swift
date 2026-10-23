import SwiftData
import WidgetKit

struct WidgetTask: Identifiable, Hashable {
    var id: String
    var title: String
    var due: Date
    var hasTime: Bool
    var isUrgent = false
    var category: String?
    /// Liste d'articles (P9-G) : « 3/12 », `nil` sans liste.
    var liste: String?
}

struct TasksEntry: TimelineEntry {
    var date: Date
    var tasks: [WidgetTask]

    var overdue: [WidgetTask] { tasks.filter { $0.due < date } }
    /// Pas encore en retard et prévues aujourd'hui (une tâche sans heure a pour échéance le minuit suivant).
    var today: [WidgetTask] {
        tasks.filter { task in
            let day = task.hasTime ? task.due : task.due.addingTimeInterval(-1)
            return task.due >= date && Calendar.current.isDate(day, inSameDayAs: date)
        }
    }
    /// Urgentes d'abord, puis par échéance.
    var ordered: [WidgetTask] { tasks.sorted { $0.isUrgent != $1.isUrgent ? $0.isUrgent : $0.due < $1.due } }

    static let placeholder = TasksEntry(date: .now, tasks: [
        WidgetTask(id: "1", title: "Appeler le garage", due: .now.addingTimeInterval(-3600), hasTime: true),
        WidgetTask(id: "2", title: "Payer la cantine", due: .now.addingTimeInterval(3 * 3600), hasTime: true),
    ])
}

/// Lit les tâches dans l'App Group. Une entrée à chaque passage d'une tâche en retard,
/// pour que le widget change sans attendre l'app.
struct TasksProvider: TimelineProvider {
    func placeholder(in context: Context) -> TasksEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (TasksEntry) -> Void) {
        completion(context.isPreview ? .placeholder : TasksEntry(date: .now, tasks: Self.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TasksEntry>) -> Void) {
        let now = Date.now
        let tasks = Self.load()
        let calendar = Calendar.current
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!

        var dates = Set([now, midnight])
        for task in tasks where task.due > now && task.due < midnight { dates.insert(task.due) }
        let entries = dates.sorted().map { TasksEntry(date: $0, tasks: tasks) }
        completion(Timeline(entries: entries, policy: .after(midnight)))
    }

    static func load() -> [WidgetTask] {
        let context = ModelContext(AppGroup.modelContainer())
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { !$0.isCompleted && !$0.isTrashed && $0.dueDay != nil })
        let items = Journal.essayer(.stockage, "Lecture des tâches (widget)") { try context.fetch(descriptor) } ?? []
        // Les tâches Basses restent dans l'app : le widget montre ce qui presse.
        return items.filter { $0.priority != .low }.compactMap { item in
            item.dueInstant().map {
                WidgetTask(id: item.localID.uuidString, title: item.title, due: $0, hasTime: item.dueMinutes != nil,
                           isUrgent: item.priority == .urgent, category: item.category,
                           liste: item.liste.flatMap { $0.articles.isEmpty ? nil : "\($0.cochés)/\($0.articles.count)" })
            }
        }
    }
}
