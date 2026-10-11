import AppIntents

/// Phrases Siri. Apple impose le nom de l'app dans chaque phrase.
struct RelanceShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTaskIntent(),
            phrases: [
                "Ajoute une tâche dans \(.applicationName)",
                "Nouvelle tâche dans \(.applicationName)",
                "Rappelle-moi avec \(.applicationName)",
            ],
            shortTitle: "Ajouter une tâche",
            systemImageName: "plus.circle")
        AppShortcut(
            intent: OverdueTasksIntent(),
            phrases: [
                "Qu'est-ce qui est en retard dans \(.applicationName)",
                "Mes tâches en retard dans \(.applicationName)",
            ],
            shortTitle: "En retard",
            systemImageName: "exclamationmark.circle")
    }
}
