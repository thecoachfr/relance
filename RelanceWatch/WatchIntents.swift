import AppIntents
import Foundation

/// « Dis Siri, nouvelle Relance » au poignet, même sans l'iPhone (eSIM) : Siri garde l'heure,
/// contrairement à Google Home. Même dialogue que sur l'iPhone (voir `SiriCapture`).
struct WatchAddTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Ajouter une tâche"
    static let description = IntentDescription("Ajoute une tâche, avec ou sans échéance.")

    @Parameter(title: "Tâche", requestValueDialog: "Qu'est-ce que tu dois faire ?")
    var text: String

    /// Demandée seulement si la phrase ne contient pas déjà une date.
    @Parameter(title: "Échéance")
    var when: String?

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        if when == nil, SiriCapture.needsWhen(text) {
            when = try await $when.requestValue(IntentDialog(stringLiteral: SiriCapture.whenDialog))
        }
        let r = SiriCapture.parse(text: text, when: when)
        // La montre attend l'instant précis quand l'heure est connue, sinon le début du jour.
        let due = r.day.map { day in
            r.minutes.flatMap { Calendar.current.date(byAdding: .minute, value: $0, to: day) } ?? day
        }
        await WatchStore.shared.insert(title: r.title, due: due, hasTime: r.minutes != nil, priority: r.priority)
        return .result(dialog: IntentDialog(stringLiteral: SiriCapture.confirmation(r)))
    }
}

/// Mêmes phrases que sur l'iPhone. Apple impose le nom de l'app dans chaque phrase.
struct RelanceWatchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WatchAddTaskIntent(),
            phrases: [
                "Nouvelle \(.applicationName)",
                "Note dans \(.applicationName)",
                "Ajoute à \(.applicationName)",
                "Ajoute une tâche dans \(.applicationName)",
                "\(.applicationName) nouvelle tâche",
                "Nouvelle tâche dans \(.applicationName)",
            ],
            shortTitle: "Ajouter une tâche",
            systemImageName: "plus.circle")
    }
}
