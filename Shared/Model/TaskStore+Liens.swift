import Foundation

/// Liens profonds `relance://` (28/10/2026) : voir `LienAiguillage`. iPhone et iPad ouvrent la fiche en feuille
/// (`MainTabs`), le Mac la sélectionne dans sa liste (`MacMainView`) ; une fiche du mémo s'ouvre en feuille partout.
extension TaskStore {
    /// Ouvre ce que désigne le lien ; `false` si ce n'est pas un lien d'Aiguillage (lien Google de connexion…).
    @discardableResult
    func ouvrir(_ url: URL) -> Bool {
        guard let lien = LienAiguillage(url: url) else { return false }
        SyncLog.add("Lien ouvert : \(url.host() ?? "")")
        switch lien {
        case .nouvelle:
            showQuickAdd = true
        case .memo(let id):
            memoDemande = id
        case .tache(let cle):
            if let item = tache(cle) {
                openedTaskID = item.localID
            } else {
                // Tâche créée ailleurs à l'instant (Courrier) : elle arrive avec la synchro, puis s'ouvre.
                Task {
                    await sync()
                    if let item = tache(cle) {
                        openedTaskID = item.localID
                    } else {
                        lastError = "Tâche introuvable : elle a peut-être été supprimée."
                    }
                }
            }
        }
        return true
    }

    private func tache(_ cle: String) -> TaskItem? {
        LienAiguillage.tache(cle, local: { task($0) }, google: { task(googleID: $0) })
            .flatMap { $0.isTrashed ? nil : $0 }
    }
}
