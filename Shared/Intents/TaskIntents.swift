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

/// « Dis Siri, ajoute une tâche dans Relance. » (voir `SiriCapture`)
struct AddTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Ajouter une tâche"
    static let description = IntentDescription("Ajoute une tâche, avec ou sans échéance. Relance te relancera jusqu'à ce qu'elle soit faite.")

    @Parameter(title: "Tâche", requestValueDialog: "Qu'est-ce que tu dois faire ?")
    var text: String

    /// Demandée seulement si la phrase ne contient pas déjà une date.
    @Parameter(title: "Échéance")
    var when: String?

    @Dependency private var store: TaskStore

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        if when == nil, SiriCapture.needsWhen(text) {
            when = try await $when.requestValue(IntentDialog(stringLiteral: SiriCapture.whenDialog))
        }
        let r = SiriCapture.parse(text: text, when: when)
        _ = store.add(title: r.title, day: r.day, minutes: r.minutes, priority: r.priority)
        await store.sync()
        return .result(dialog: IntentDialog(stringLiteral: SiriCapture.confirmation(r)))
    }
}

/// « Dis Siri, qu'est-ce qui est en retard dans Relance ? »
struct OverdueTasksIntent: AppIntent {
    static let title: LocalizedStringResource = "Tâches en retard"
    static let description = IntentDescription("Lit les tâches en retard.")

    @Dependency private var store: TaskStore

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        // Une tâche cochée ailleurs il y a cinq minutes ne doit pas être annoncée : synchro d'abord,
        // mais Siri n'attend pas plus de 4 s (sans réseau, on lit la liste locale).
        await ReminderScheduler.withTimeout(seconds: 4) { @MainActor in await store.sync() }
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

/// Commande « Nouvelle tâche » (Centre de contrôle, bouton Action, écran verrouillé).
/// L'intent peut s'exécuter dans l'extension : il ne touche pas au magasin, il laisse une marque
/// dans l'App Group que l'app lit en passant au premier plan.
struct NewTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Nouvelle tâche"
    static let description = IntentDescription("Ouvre Relance sur la saisie d'une nouvelle tâche.")
    static let openAppWhenRun = true

    static let pendingKey = "pendingQuickAdd"

    func perform() async throws -> some IntentResult {
        AppGroup.defaults.set(true, forKey: Self.pendingKey)
        return .result()
    }
}
