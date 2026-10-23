import Foundation
import SwiftData

/// Espace partagé entre l'app, les widgets et l'activité en direct.
nonisolated enum AppGroup {
    static let id = "group.fr.alexandrefau.relance"

    static var defaults: UserDefaults { UserDefaults(suiteName: id) ?? .standard }

    /// Widgets et extensions : jamais de réparation (l'app s'en charge) ; base vide en mémoire si elle est illisible.
    static func modelContainer(inMemory: Bool = false) -> ModelContainer {
        ouvrirBase(inMemory: inMemory, reparer: false).container
    }

    /// Ouvre la base locale. Elle n'est qu'une copie (la vérité est dans Home Assistant ou Google) : si elle est illisible
    /// (migration ratée, fichier abîmé), l'app ne doit pas planter à chaque lancement comme avec l'ancien `try!`.
    /// - `reparer` (l'app seulement) : la base abîmée est **mise de côté** (jamais supprimée, au cas où des modifications
    ///   locales n'auraient pas été envoyées), une base neuve est créée et sera remplie à la synchro.
    /// - En dernier recours, une base en mémoire : l'app démarre, vide, et le dit dans Erreurs récentes.
    /// `neuve` : la base repart de zéro ; la synchro doit alors tout relire (voir `TaskStore.init`).
    static func ouvrirBase(inMemory: Bool = false, reparer: Bool) -> (container: ModelContainer, neuve: Bool) {
        // Sans `cloudKitDatabase: .none`, SwiftData active seul la synchro CloudKit dès que l'app a la
        // capacité iCloud (fallback de DonneesHA), et refuse alors le modèle : plantage au lancement.
        let enMemoire = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let configuration = inMemory ? enMemoire : ModelConfiguration(groupContainer: .identifier(id), cloudKitDatabase: .none)
        do {
            return (try ModelContainer(for: TaskItem.self, configurations: configuration), false)
        } catch {
            Journal.echec(.stockage, "Ouverture de la base locale", error)
        }
        if reparer, !inMemory, let copie = mettreDeCote(configuration.url) {
            Journal.echec(.stockage, "Base locale illisible, mise de côté (\(copie)) : tout est relu depuis Home Assistant ou Google")
            if let neuve = Journal.essayer(.stockage, "Création d'une base locale neuve", {
                try ModelContainer(for: TaskItem.self, configurations: configuration) }) {
                return (neuve, true)
            }
        }
        Journal.echec(.stockage, "Base locale en mémoire seulement (rien n'est gardé entre deux lancements)")
        // Une base en mémoire ne peut pas être illisible : seul `try!` restant, sans risque.
        return (try! ModelContainer(for: TaskItem.self, configurations: enMemoire), true)
    }

    /// Renomme la base et ses fichiers annexes (`-wal`, `-shm`) en `….abimee-<date>` ; renvoie le nouveau nom.
    static func mettreDeCote(_ base: URL) -> String? {
        let suffixe = "abimee-\(Int(Date.now.timeIntervalSince1970))"
        var deplace = false
        for annexe in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: base.path + annexe)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            let cible = URL(fileURLWithPath: base.path + annexe + "." + suffixe)
            if Journal.essayer(.stockage, "Mise de côté de \(source.lastPathComponent)", {
                try FileManager.default.moveItem(at: source, to: cible) }) != nil, annexe.isEmpty {
                deplace = true
            }
        }
        return deplace ? base.lastPathComponent + "." + suffixe : nil
    }
}

/// Ce dont le magasin a besoin du compte Google, sans dépendre du SDK (absent des widgets).
protocol AccountProvider: AnyObject, Sendable {
    var isSignedIn: Bool { get }
    func accessToken() async throws -> String
    func signOut()
    /// Pour la montre : jeton de renouvellement et identifiant client OAuth (nil si déconnecté).
    var watchCredentials: (refreshToken: String, clientID: String)? { get }
}
