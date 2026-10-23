import Foundation
import os

/// Échecs qu'on ne veut plus avaler en silence (`try?`) : écrits dans le journal système (Console, `log collect`)
/// et gardés dans l'App Group pour les lire dans l'app (Réglages › Erreurs récentes), sans câble ni Console.
/// Ne jamais y mettre de contenu de tâche, de jeton ni d'adresse : seulement ce qui a échoué et l'erreur.
nonisolated enum Journal {
    enum Domaine: String, CaseIterable, Sendable {
        case synchro, stockage, reseau, notifications, montre, systeme
    }

    struct Entree: Codable, Hashable, Sendable {
        var date: Date
        var domaine: String
        var texte: String
        /// Répétitions consécutives du même échec (une synchro qui échoue toutes les 5 min ne remplit pas le journal).
        var fois: Int = 1
    }

    private static let sousSysteme = Bundle.main.bundleIdentifier ?? "fr.alexandrefau.relance"

    /// Où sont gardées les erreurs récentes : l'App Group pour l'app et ses extensions, un espace à part pour les tests.
    struct Registre: Sendable {
        let suite: String
        static let partage = Registre(suite: Groupes.app)
        static let maxEntrees = 30
        private static let cle = "journalErreurs"
        private static let verrou = OSAllocatedUnfairLock()

        private var defaults: UserDefaults { UserDefaults(suiteName: suite) ?? .standard }

        func recentes() -> [Entree] {
            guard let data = defaults.data(forKey: Self.cle) else { return [] }
            return (try? JSONDecoder().decode([Entree].self, from: data)) ?? []
        }

        func effacer() { defaults.removeObject(forKey: Self.cle) }

        func garder(_ domaine: Domaine, _ texte: String) {
            Self.verrou.withLock {
                var entrees = recentes()
                if var premiere = entrees.first, premiere.domaine == domaine.rawValue, premiere.texte == texte {
                    premiere.fois += 1
                    premiere.date = .now
                    entrees[0] = premiere
                } else {
                    entrees.insert(Entree(date: .now, domaine: domaine.rawValue, texte: texte), at: 0)
                }
                if let data = try? JSONEncoder().encode(Array(entrees.prefix(Self.maxEntrees))) {
                    defaults.set(data, forKey: Self.cle)
                }
            }
        }
    }

    static func logger(_ domaine: Domaine) -> Logger { Logger(subsystem: sousSysteme, category: domaine.rawValue) }

    /// Note un échec : `quoi` dit ce qui a raté (« Enregistrement des tâches »), l'erreur dit pourquoi.
    static func echec(_ domaine: Domaine, _ quoi: String, _ erreur: (any Error)? = nil, dans registre: Registre = .partage) {
        let texte = erreur.map { "\(quoi) : \(decrire($0))" } ?? quoi
        logger(domaine).error("\(texte, privacy: .public)")
        registre.garder(domaine, texte)
    }

    /// `try?` qui laisse une trace : renvoie nil en cas d'erreur, comme `try?`, mais la note.
    @discardableResult
    static func essayer<T>(_ domaine: Domaine, _ quoi: @autoclosure () -> String, dans registre: Registre = .partage,
                           _ action: () throws -> T) -> T? {
        do { return try action() } catch is CancellationError { return nil } catch {
            echec(domaine, quoi(), error, dans: registre); return nil
        }
    }

    @discardableResult
    static func essayer<T>(_ domaine: Domaine, _ quoi: @autoclosure () -> String, dans registre: Registre = .partage,
                           _ action: () async throws -> T) async -> T? {
        do { return try await action() } catch is CancellationError { return nil } catch {
            echec(domaine, quoi(), error, dans: registre); return nil
        }
    }

    /// Réponse HTTP 2xx ; sinon note « quoi : HTTP 401 » et renvoie false.
    static func reponseOK(_ reponse: URLResponse?, _ domaine: Domaine, _ quoi: String,
                          dans registre: Registre = .partage) -> Bool {
        let code = (reponse as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { echec(domaine, "\(quoi) : HTTP \(code)", dans: registre); return false }
        return true
    }

    static func recentes() -> [Entree] { Registre.partage.recentes() }

    static func effacer() { Registre.partage.effacer() }

    /// « NSURLErrorDomain -1001 : La requête a expiré. » : le code sert à chercher, le texte à comprendre.
    static func decrire(_ erreur: any Error) -> String {
        let ns = erreur as NSError
        return "\(ns.domain) \(ns.code) : \(ns.localizedDescription)"
    }
}
