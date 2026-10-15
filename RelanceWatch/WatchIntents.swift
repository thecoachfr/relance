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
        // La montre n'écrit pas les lignes des notes : une envie garde « à regarder » dans le titre,
        // et la routine de tri la range (règle N).
        let title = r.kind.map { "\(r.title) (\($0.title.lowercased()))" } ?? r.title
        await WatchStore.shared.insert(title: title, due: due, hasTime: r.minutes != nil, priority: r.priority)
        return .result(dialog: IntentDialog(stringLiteral: SiriCapture.confirmation(r)))
    }
}

/// « Ajoute au mémo dans Aiguillage » au poignet : la fiche part à l'iPhone (tâches dans Home Assistant),
/// ou s'écrit directement chez Google.
struct WatchAddMemoIntent: AppIntent {
    static let title: LocalizedStringResource = "Ajouter au mémo"
    static let description = IntentDescription("Ajoute une fiche au mémo de tri, ou complète celle qui porte le même sujet.")

    @Parameter(title: "Sujet", requestValueDialog: "Quel est le sujet de la fiche ?")
    var subject: String

    @Parameter(title: "Détails", requestValueDialog: "Qu'est-ce que je dois retenir ?")
    var details: String

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = WatchStore.shared
        if store.tasksInHA {
            switch await store.rememberViaPhone(title: subject, details: details) {
            case .some(let outcome):
                return .result(dialog: IntentDialog(stringLiteral: MemoMerge.confirmation(outcome, subject: subject)))
            case .none:
                return .result(dialog: "C'est noté : la fiche « \(subject) » partira vers le mémo dès que l'iPhone sera joignable.")
            }
        }
        guard store.google.isAvailable else {
            return .result(dialog: "Ouvre Aiguillage sur l'iPhone une fois pour connecter la montre à Google.")
        }
        let outcome = try? await store.remember(title: subject, details: details)
        return .result(dialog: IntentDialog(stringLiteral: MemoMerge.confirmation(outcome, subject: subject)))
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
        AppShortcut(
            intent: WatchAddMemoIntent(),
            phrases: [
                "Ajoute au mémo dans \(.applicationName)",
                "Ajoute au mémo d'\(.applicationName)",
                "Note dans le mémo d'\(.applicationName)",
                "Nouvelle fiche dans \(.applicationName)",
                "\(.applicationName) mémo",
            ],
            shortTitle: "Ajouter au mémo",
            systemImageName: "text.book.closed")
    }
}
