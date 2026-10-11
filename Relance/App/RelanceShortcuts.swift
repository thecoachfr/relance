import AppIntents

/// Phrases Siri. Apple impose le nom de l'app dans chaque phrase.
struct RelanceShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTaskIntent(),
            // Éviter « rappelle-moi » et « ajoute une tâche » seuls : Siri les envoie à l'app Rappels.
            phrases: [
                "Nouvelle \(.applicationName)",
                "Note dans \(.applicationName)",
                "Ajoute à \(.applicationName)",
                "Ajoute une tâche dans \(.applicationName)",
                "\(.applicationName) nouvelle tâche",
            ],
            shortTitle: "Ajouter une tâche",
            systemImageName: "plus.circle")
        AppShortcut(
            intent: OverdueTasksIntent(),
            phrases: [
                "Qu'est-ce qui est en retard dans \(.applicationName)",
                "Mes tâches en retard dans \(.applicationName)",
                "\(.applicationName) en retard",
            ],
            shortTitle: "En retard",
            systemImageName: "exclamationmark.circle")
    }
}
