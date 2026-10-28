import DonneesHA
import Foundation

/// Lieu de travail (P9-N2, 24/10/2026) : lecture de `sensor.aiguillage_lieu_travail` et écriture des réglages
/// `config:lieu_travail` (semaine type, premier vendredi, exceptions) depuis l'écran « Lieu de travail ».
extension TaskStore {
    /// Relit le capteur, au plus une fois par quart d'heure sauf `force` (après une modification, ouverture de
    /// l'écran). Appelé à la fin de chaque synchro HA : aucun sondage à part. Une erreur garde le dernier état connu.
    func rafraichirLieuTravail(force: Bool = false) async {
        guard isHAActive, !isDemo, let url = HAConfig.url, let jeton = HAConfig.token, !jeton.isEmpty else { return }
        if !force, let lu = lieuTravailLuLe, Date.now.timeIntervalSince(lu) < LieuTravail.intervalle { return }
        guard let lecture = await Journal.essayer(.reseau, "Lecture du lieu de travail", {
            try await LieuTravail.lire(url: url, jeton: jeton) }) else { return }
        lieuTravailLuLe = .now
        let nouveau: LieuTravail? = if case .lu(let lieu) = lecture { lieu } else { nil }
        guard nouveau != lieuTravail else { return }
        lieuTravail = nouveau
        LieuTravail.cache(nouveau)
        // Le résumé du matin met en tête les tâches du contexte du jour : il est recalculé (seul le différentiel est
        // posé), puis la montre suit (libellé du jour ; envoi seulement si le contexte a changé). `reschedule` appelle
        // `onTasksChanged` quand l'appareil relance ; sinon on le fait ici.
        if schedulesReminders { await reschedule() } else { onTasksChanged?() }
    }

    /// Change un réglage : écrit tout de suite dans la base locale (puis HA, version attendue de la base), en partant
    /// de la valeur connue pour garder les champs inconnus ; le capteur est relu dès que HA l'a recalculé.
    func modifierLieuTravail(_ modification: ConfigLieuTravail.Modification) {
        guard let synchro else {
            lastError = "Home Assistant : pas encore synchronisé, réessaie dans un instant."
            return
        }
        let cle = ConfigLieuTravail.haKey
        let actuelle = Journal.essayer(.synchro, "Lecture des réglages du lieu de travail") { try synchro.valeur(cle) } ?? nil
        let nouvelle = ConfigLieuTravail.appliquer([modification], a: actuelle)
        modifsLieuTravail.append(modification)
        configLieuTravail = ConfigLieuTravail(valeur: nouvelle)
        Journal.essayer(.synchro, "Écriture des réglages du lieu de travail") { try synchro.ecrire(cle, nouvelle) }
        Task {
            await sync()
            if (try? synchro.base.operationEnAttente(cle)) == nil { modifsLieuTravail = [] }
            // `aiguillage_lieu_travail` recalcule à l'événement `donnees_apps_modifie` (moins d'une seconde mesurée le
            // 24/10) : une relecture un peu après suffit.
            try? await Task.sleep(for: .seconds(2))
            await rafraichirLieuTravail(force: true)
        }
    }
}
