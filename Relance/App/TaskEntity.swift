import AppIntents
import CoreSpotlight
import Foundation

/// Une tâche telle que Siri et Spotlight la connaissent : « Marque *garage* comme fait dans Relance ».
struct TaskEntity: AppEntity, IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Tâche"
    static let defaultQuery = TaskEntityQuery()

    /// `localID` de la tâche.
    var id: String
    var title: String
    var subtitle: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(subtitle)")
    }

    @MainActor init(_ item: TaskItem, now: Date = .now) {
        id = item.localID.uuidString
        title = item.title
        subtitle = item.dueInstant().map { DueText.long(due: $0, hasTime: item.dueMinutes != nil, now: now) } ?? "Sans date"
    }
}

struct TaskEntityQuery: EntityStringQuery {
    @Dependency private var store: TaskStore

    @MainActor func entities(for identifiers: [String]) async throws -> [TaskEntity] {
        identifiers.compactMap { UUID(uuidString: $0).flatMap(store.task) }.map { TaskEntity($0) }
    }

    /// « garage » trouve « Appeler le garage » ; accents et majuscules ignorés.
    @MainActor func entities(matching string: String) async throws -> [TaskEntity] {
        let words = string.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .split(separator: " ").filter { $0.count > 2 }
        return Self.sorted(store.activeTasks()).filter { item in
            let title = item.title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            return !words.isEmpty && words.allSatisfy { title.contains($0) }
        }
        .map { TaskEntity($0) }
    }

    /// Ce que Siri propose quand il ne sait pas laquelle : les plus proches de l'échéance.
    @MainActor func suggestedEntities() async throws -> [TaskEntity] {
        Self.sorted(store.activeTasks()).prefix(20).map { TaskEntity($0) }
    }

    @MainActor static func sorted(_ items: [TaskItem]) -> [TaskItem] {
        items.sorted { ($0.dueInstant() ?? .distantFuture) < ($1.dueInstant() ?? .distantFuture) }
    }
}

/// Toucher une tâche dans Spotlight ouvre sa fiche dans Relance.
struct OpenTaskIntent: OpenIntent {
    static let title: LocalizedStringResource = "Ouvrir une tâche"
    @Parameter(title: "Tâche") var target: TaskEntity
    @Dependency private var store: TaskStore

    @MainActor func perform() async throws -> some IntentResult {
        store.openedTaskID = UUID(uuidString: target.id)
        return .result()
    }
}

/// Garde Siri (noms des tâches) et Spotlight à jour après chaque changement.
enum TaskIndex {
    @MainActor static func update(_ items: [TaskItem]) {
        RelanceShortcuts.updateAppShortcutParameters()
        let entities = items.map { TaskEntity($0) }
        Task {
            let index = CSSearchableIndex.default()
            try? await index.deleteAppEntities(ofType: TaskEntity.self)
            try? await index.indexAppEntities(entities)
        }
    }
}

// MARK: - Commandes vocales

/// « Marque *garage* comme fait dans Relance. »
struct CompleteTaskByNameIntent: AppIntent {
    static let title: LocalizedStringResource = "Marquer une tâche comme faite"
    static let description = IntentDescription("Coche une tâche par son nom.")

    @Parameter(title: "Tâche", requestValueDialog: "Quelle tâche ?") var task: TaskEntity
    @Dependency private var store: TaskStore

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let id = UUID(uuidString: task.id), let item = store.task(id), !item.isCompleted else {
            return .result(dialog: "Je ne trouve plus cette tâche.")
        }
        store.complete(item)
        await store.sync()
        return .result(dialog: "C'est fait : \(item.title).")
    }
}

/// « Reporte *garage* dans Relance » → « À quand ? » → « demain à 10 h », « dans 2 heures », « vendredi ».
struct PostponeTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Reporter une tâche"
    static let description = IntentDescription("Change l'échéance d'une tâche par son nom.")

    @Parameter(title: "Tâche", requestValueDialog: "Quelle tâche ?") var task: TaskEntity
    @Parameter(title: "Quand") var when: String?
    @Dependency private var store: TaskStore

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let id = UUID(uuidString: task.id), let item = store.task(id), !item.isCompleted else {
            return .result(dialog: "Je ne trouve plus cette tâche.")
        }
        if when == nil {
            when = try await $when.requestValue("À quand ? Par exemple demain matin, vendredi à 10 h ou dans 2 heures.")
        }
        guard let answer = when, let match = DateDetection.firstMatch(in: answer) else {
            return .result(dialog: "Je n'ai pas compris la date. Rien n'a changé.")
        }
        let calendar = Calendar.current
        let c = calendar.dateComponents([.hour, .minute], from: match.date)
        // Sans heure dite, on garde l'heure de la tâche.
        let minutes = match.hasTime ? (c.hour ?? 0) * 60 + (c.minute ?? 0) : item.dueMinutes
        store.update(item, title: item.title, notes: item.notes, day: calendar.startOfDay(for: match.date), minutes: minutes)
        await store.sync()
        let due = item.dueInstant().map { DueText.long(due: $0, hasTime: item.dueMinutes != nil) } ?? ""
        return .result(dialog: "C'est reporté : \(item.title), \(due.prefix(1).lowercased() + due.dropFirst()).")
    }
}

/// « Qu'est-ce que j'ai aujourd'hui dans Relance ? »
struct TodayTasksIntent: AppIntent {
    static let title: LocalizedStringResource = "Tâches du jour"
    static let description = IntentDescription("Lit les tâches prévues aujourd'hui et le nombre en retard.")

    @Dependency private var store: TaskStore

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        await ReminderScheduler.withTimeout(seconds: 4) { @MainActor in await store.sync() }
        let calendar = Calendar.current
        let now = Date.now
        let active = TaskEntityQuery.sorted(store.activeTasks())
        let late = active.filter { $0.isOverdue(now: now) }.count
        let today = active.filter { item in
            guard let day = item.dueDay else { return false }
            return calendar.isDateInToday(day) && !item.isOverdue(now: now)
        }
        let lateText = switch late {
        case 0: ""
        case 1: " Et une tâche en retard."
        default: " Et \(late) tâches en retard."
        }
        guard !today.isEmpty else {
            return .result(dialog: IntentDialog(stringLiteral: "Rien d'autre de prévu aujourd'hui." + lateText))
        }
        let names = today.prefix(5).map { item in
            item.dueMinutes.map { "\(item.title) à \(ReminderPlanner.formatTime($0))" } ?? item.title
        }
        let more = today.count > 5 ? ", et \(today.count - 5) autres" : ""
        let head = today.count == 1 ? "Une tâche aujourd'hui : " : "\(today.count) tâches aujourd'hui : "
        return .result(dialog: IntentDialog(stringLiteral: head + names.joined(separator: ", ") + more + "." + lateText))
    }
}
