import AppIntents
import Foundation

/// Complication « + » et commande (Centre de contrôle, bouton Action) : ouvrent la montre sur la saisie.
nonisolated enum WatchQuickAdd {
    static let url = URL(string: "relance://add")!
    /// Widgets « Aujourd'hui » et « En retard » : ouvrent la liste, jamais la saisie.
    static let listURL = URL(string: "relance://list")!
    static let pendingKey = "watchPendingAdd"
    static let notification = Notification.Name("WatchQuickAdd")

    static var defaults: UserDefaults { Groupes.defaults }
}

struct WatchNewTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Nouvelle tâche"
    static let description = IntentDescription("Ouvre Aiguillage sur la saisie d'une nouvelle tâche.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        // Horodatée : une demande non consommée ne doit pas rouvrir la saisie plus tard.
        WatchQuickAdd.defaults.set(Date.now.timeIntervalSince1970, forKey: WatchQuickAdd.pendingKey)
        // L'app est peut-être déjà au premier plan : on la prévient directement.
        NotificationCenter.default.post(name: WatchQuickAdd.notification, object: nil)
        return .result()
    }
}
