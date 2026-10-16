import DonneesHA
import Foundation
import SwiftData

/// Tâches rangées dans Home Assistant (`donnees_apps`, espace `aiguillage`) par le paquet `DonneesHA`.
///
/// SwiftData reste la copie que lisent les écrans ; la base `DonneesHA` (App Group) porte les
/// enregistrements reçus de HA et l'outbox. Hors ligne, `DonneesHA` dépose un instantané dans iCloud.
extension TaskStore {
    /// Clé HA d'une tâche : son identifiant local.
    static func haKey(_ item: TaskItem) -> String { item.localID.uuidString.lowercased() }

    /// Les tâches de cet appareil sont dans HA (réglage de l'appareil, ou forçage des tests).
    var isHAActive: Bool { haActiveOverride ?? HAConfig.isActive }

    private func setHAActive(_ active: Bool) {
        if haActiveOverride != nil { haActiveOverride = active } else { HAConfig.isActive = active }
    }

    /// État lisible de la synchro HA (réglages, barre d'état).
    var haStatus: String? {
        guard isHAActive else { return nil }
        switch synchro?.etat {
        case nil, .jamaisSynchronise?: return "Pas encore synchronisé"
        case .enCours?: return "Synchronisation…"
        case .aJour?: return "À jour"
        case .horsLigne(let n)?: return n == 0 ? "Hors ligne" : "Hors ligne, \(n) en attente (copie dans iCloud)"
        case .erreur(let message)?: return "Erreur : \(message)"
        }
    }

    /// Le synchroniseur, créé une fois ; `nil` si l'URL ou le jeton manque.
    func haSynchroniser() async -> Synchroniseur? {
        if let synchro { return synchro }
        synchro = await makeSynchroniser()
        return synchro
    }

    /// À appeler quand l'URL ou le jeton change.
    func resetHA() {
        synchro = nil
    }

    func performHASync() async {
        guard let synchro = await haSynchroniser() else {
            lastError = "Home Assistant : URL ou jeton manquant (Réglages)."
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        let firstSync = ((try? synchro.base.dernierSeq) ?? 0) == 0
        do {
            try haPush(synchro)
            await synchro.synchroniser()
            try haPull(synchro, firstSync: firstSync)
            if spawnedDuringPull {
                spawnedDuringPull = false
                try haPush(synchro)
                await synchro.synchroniser()
            }
            if case .erreur(let message) = synchro.etat {
                lastError = "Home Assistant : \(message)"
            } else {
                lastError = nil
            }
        } catch {
            lastError = error.localizedDescription
        }
        try? context.save()
    }

    /// Mes abonnements : sur l'appareil tout de suite, puis dans HA (partagés avec les autres appareils et la vigie).
    func setSubscriptions(_ codes: [String]) {
        subscriptions = codes
        Subscriptions.cache(codes)
        guard let synchro else { return }
        try? synchro.ecrire(Subscriptions.haKey, .objet(["plateformes": .liste(codes.map { .texte($0) })]))
        Task { await sync() }
    }

    /// Les modifications locales passent dans la base `DonneesHA` (et son outbox).
    private func haPush(_ synchro: Synchroniseur) throws {
        insertPendingShares()
        let dirty = try context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.isDirty }))
        for item in dirty {
            if item.isTrashed {
                try synchro.supprimer(Self.haKey(item))
                context.delete(item)
            } else {
                try synchro.ecrire(Self.haKey(item), try TacheHA(item).valeur())
                item.isDirty = false
            }
        }
        try context.save()
    }

    /// La base `DonneesHA` (à jour de HA après la synchro) recopiée dans SwiftData.
    private func haPull(_ synchro: Synchroniseur, firstSync: Bool) throws {
        let records = try synchro.base.tous(inclureSupprimes: true)
        if let config = records.first(where: { $0.cle == Subscriptions.haKey && !$0.supprime }),
           case .objet(let o) = config.valeur, case .liste(let list)? = o["plateformes"] {
            let codes = list.compactMap { if case .texte(let s) = $0 { s } else { nil } }
            if codes != subscriptions {
                subscriptions = codes
                Subscriptions.cache(codes)
            }
        }
        let all = try context.fetch(FetchDescriptor<TaskItem>())
        var byKey = Dictionary(all.map { (Self.haKey($0), $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()

        for record in records {
            // Clés écrites par d'autres que l'app (essais…) : ignorées.
            guard let id = UUID(uuidString: record.cle) else { continue }
            seen.insert(record.cle)
            let local = byKey[record.cle]
            if local?.isDirty == true { continue }
            if record.supprime {
                if let local { context.delete(local) }
                continue
            }
            guard let tache = try? TacheHA(valeur: record.valeur) else { continue }
            let wasDone = local?.isCompleted ?? true
            let item = local ?? {
                let new = TaskItem(title: tache.titre)
                new.localID = id
                context.insert(new)
                byKey[record.cle] = new
                return new
            }()
            tache.apply(to: item)
            item.updatedAt = Horodatage.date(record.modifieLe) ?? item.updatedAt
            // Cochée ailleurs (montre, autre appareil) : seul l'appareil qui relance crée la suivante.
            if !wasDone, item.isCompleted, ReminderScheduler.isEnabledOnThisDevice, spawnNext(of: item) != nil {
                spawnedDuringPull = true
            }
            // Arrivée d'ailleurs (dictée Google Home relayée par la vigie, autre appareil) datée sans heure.
            if local == nil, !firstSync, !item.isCompleted, item.dueDay != nil, item.dueMinutes == nil {
                needTimeNow.append(item.localID)
            }
        }

        // Absente de HA après une synchro réussie : supprimée ailleurs (et sa tombstone purgée).
        if synchro.etat == .aJour {
            for item in all where !item.isDirty && !seen.contains(Self.haKey(item)) {
                context.delete(item)
            }
        }
        try context.save()
    }

    // MARK: - Passage de Google Tasks à Home Assistant

    /// Bascule cet appareil sur HA : une dernière synchro Google (pour ne rien perdre), puis une
    /// lecture de HA. Une tâche Google déjà migrée par un autre appareil (même `google_id`) reprend sa
    /// clé et la version de HA ; les autres partent avec une clé dérivée de leur identifiant Google
    /// (la même sur chaque appareil et dans la vigie) : pas de doublon, même si deux appareils migrent
    /// en même temps. Renvoie un message d'erreur, ou `nil`.
    func activateHA() async -> String? {
        guard !isHAActive else { return nil }
        if auth.isSignedIn {
            await sync()
            if let lastError { return "Synchro Google impossible, rien n'a changé : \(lastError)" }
        }
        resetHA()
        guard let synchro = await haSynchroniser() else { return "Home Assistant : URL ou jeton manquant." }
        await synchro.synchroniser()
        guard synchro.etat == .aJour else {
            resetHA()
            return "Home Assistant injoignable, rien n'a changé (\(haStatus ?? "?"))."
        }
        var keyForGoogleID: [String: UUID] = [:]
        for record in (try? synchro.base.tous()) ?? [] {
            guard let id = UUID(uuidString: record.cle), let googleID = (try? TacheHA(valeur: record.valeur))?.googleID,
                  keyForGoogleID[googleID] == nil else { continue }
            keyForGoogleID[googleID] = id
        }
        let items = (try? context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { !$0.isTrashed }))) ?? []
        var adopted = 0
        for item in items {
            if let googleID = item.googleID, let id = keyForGoogleID[googleID] {
                // Déjà dans HA : la copie de HA sera recopiée ici à la synchro.
                item.localID = id
                item.isDirty = false
                adopted += 1
            } else {
                if let googleID = item.googleID { item.localID = TacheHA.key(googleID: googleID) }
                item.isDirty = true
            }
        }
        try? context.save()
        setHAActive(true)
        SyncLog.add("Tâches passées dans Home Assistant (\(items.count - adopted) envoyées, \(adopted) déjà présentes)")
        await sync()
        return nil
    }

    /// Retour à Google Tasks sur cet appareil (en cas de souci) : les tâches locales y sont renvoyées ;
    /// celles que Google n'a plus (importées puis retirées par la vigie) y sont recréées.
    func deactivateHA() async -> String? {
        guard isHAActive else { return nil }
        guard auth.isSignedIn else { return "Connecte d'abord le compte Google." }
        let remoteIDs: Set<String>
        do {
            remoteIDs = Set(try await api.fetch(updatedMin: nil).compactMap { $0.deleted == true ? nil : $0.id })
        } catch {
            return "Google Tasks injoignable, rien n'a changé : \(error.localizedDescription)"
        }
        let items = (try? context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { !$0.isTrashed }))) ?? []
        for item in items {
            if let id = item.googleID, !remoteIDs.contains(id) { item.googleID = nil }
            item.isDirty = true
        }
        try? context.save()
        setHAActive(false)
        resetHA()
        lastSync = nil
        SyncLog.add("Retour à Google Tasks (\(items.count) tâches)")
        await sync()
        return nil
    }
}
