import AppIntents
import Foundation

// Ces intents sont compilés dans l'app et dans l'extension widgets.
// Les `LiveActivityIntent` s'exécutent toujours dans le processus de l'app,
// là où vivent le magasin, la synchro Google et les notifications.

/// Bouton « Fait » des widgets et de l'activité en direct.
struct CompleteTaskIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Marquer une tâche comme faite"
    static let isDiscoverable = false

    @Parameter(title: "Tâche") var taskID: String
    @Dependency private var store: TaskStore

    init() {}
    init(taskID: String) { self.taskID = taskID }

    @MainActor func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: taskID), let item = store.task(id) {
            store.complete(item)
            await store.sync()
        }
        return .result()
    }
}

/// Bouton « 1 h » de l'activité en direct.
struct SnoozeTaskIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Reporter une tâche d'une heure"
    static let isDiscoverable = false

    @Parameter(title: "Tâche") var taskID: String
    @Dependency private var store: TaskStore

    init() {}
    init(taskID: String) { self.taskID = taskID }

    @MainActor func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: taskID), let item = store.task(id) {
            store.snooze(item, until: .now.addingTimeInterval(3600))
        }
        return .result()
    }
}

/// « Dis Siri, ajoute une tâche dans Relance. »
struct AddTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Ajouter une tâche"
    static let description = IntentDescription("Ajoute une tâche avec son échéance. Relance te relancera jusqu'à ce qu'elle soit faite.")

    @Parameter(title: "Tâche", requestValueDialog: "Qu'est-ce que tu dois faire ?")
    var text: String

    @Parameter(title: "Échéance", kind: .dateTime, requestValueDialog: "Pour quand ?")
    var due: Date

    @Dependency private var store: TaskStore

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let calendar = Calendar.current
        let c = calendar.dateComponents([.hour, .minute], from: due)
        // Siri donne minuit quand on ne précise pas d'heure : on garde alors la date seule.
        let minutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        let item = store.add(title: text, day: calendar.startOfDay(for: due), minutes: minutes == 0 ? nil : minutes)
        await store.sync()

        var when = due.formatted(.dateTime.weekday(.wide).day().month(.wide))
        if let m = item.dueMinutes { when += " à " + ReminderPlanner.formatTime(m) }
        return .result(dialog: "C'est noté : \(text), \(when).")
    }
}

/// « Dis Siri, qu'est-ce qui est en retard dans Relance ? »
struct OverdueTasksIntent: AppIntent {
    static let title: LocalizedStringResource = "Tâches en retard"
    static let description = IntentDescription("Lit les tâches en retard.")

    @Dependency private var store: TaskStore

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let overdue = store.activeTasks()
            .filter { $0.isOverdue() }
            .sorted { ($0.dueInstant() ?? .distantPast) < ($1.dueInstant() ?? .distantPast) }
        switch overdue.count {
        case 0: return .result(dialog: "Rien n'est en retard.")
        case 1: return .result(dialog: "Une tâche en retard : \(overdue[0].title).")
        default:
            let names = overdue.prefix(3).map(\.title).joined(separator: ", ")
            let more = overdue.count > 3 ? ", et \(overdue.count - 3) autres" : ""
            return .result(dialog: "\(overdue.count) tâches en retard : \(names)\(more).")
        }
    }
}
