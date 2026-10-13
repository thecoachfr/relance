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
                "Nouvelle tâche dans \(.applicationName)",
            ],
            shortTitle: "Ajouter une tâche",
            systemImageName: "plus.circle")
        AppShortcut(
            intent: CompleteTaskByNameIntent(),
            phrases: [
                "Marque \(\.$task) comme fait dans \(.applicationName)",
                "\(\.$task) est fait dans \(.applicationName)",
                "Coche \(\.$task) dans \(.applicationName)",
                "Marque une tâche comme faite dans \(.applicationName)",
            ],
            shortTitle: "Marquer comme faite",
            systemImageName: "checkmark.circle")
        AppShortcut(
            intent: PostponeTaskIntent(),
            phrases: [
                "Reporte \(\.$task) dans \(.applicationName)",
                "Décale \(\.$task) dans \(.applicationName)",
                "Reporte une tâche dans \(.applicationName)",
            ],
            shortTitle: "Reporter",
            systemImageName: "calendar.badge.clock")
        AppShortcut(
            intent: TodayTasksIntent(),
            phrases: [
                "Qu'est-ce que j'ai aujourd'hui dans \(.applicationName)",
                "Mes tâches du jour dans \(.applicationName)",
                "\(.applicationName) aujourd'hui",
            ],
            shortTitle: "Aujourd'hui",
            systemImageName: "sun.max")
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
