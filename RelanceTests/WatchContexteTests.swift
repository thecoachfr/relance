import Foundation
import Testing
@testable import Relance

/// Contexte envoyé à la montre (B6) : renvoyé seulement s'il a changé ; la comparaison ne dépend pas de l'ordre.
struct WatchContexteTests {
    let base: [String: Any] = [
        WatchLink.tasksKey: Data("[1,2]".utf8), WatchLink.tasksInHAKey: true,
        WatchLink.refreshTokenKey: "jeton", WatchLink.clientIDKey: "client",
        WatchLink.haURLKey: "https://ha.example", WatchLink.haTokenKey: "secret",
    ]

    @Test func memeContenuMemeEmpreinte() {
        let copie = base.reduce(into: [String: Any]()) { $0[$1.key] = $1.value }
        #expect(WatchContexte.empreinte(base) == WatchContexte.empreinte(copie))
        // Tel que WatchConnectivity le rend (types Objective-C) : même empreinte.
        let ponte = (base as NSDictionary) as! [String: Any]
        #expect(WatchContexte.empreinte(base) == WatchContexte.empreinte(ponte))
    }

    @Test func chaqueChangementCompte() {
        let reference = WatchContexte.empreinte(base)
        var deconnecte = base
        deconnecte[WatchLink.refreshTokenKey] = ""          // chaîne vide = déconnexion : doit partir
        #expect(WatchContexte.empreinte(deconnecte) != reference)
        var ha = base
        ha[WatchLink.tasksInHAKey] = false
        #expect(WatchContexte.empreinte(ha) != reference)
        var taches = base
        taches[WatchLink.tasksKey] = Data("[1]".utf8)
        #expect(WatchContexte.empreinte(taches) != reference)
        #expect(WatchContexte.empreinte([:]) != reference)  // premier envoi (rien d'envoyé encore)
    }

    @Test func morceauxNonConfondus() {
        #expect(WatchContexte.empreinte(["a": "bc"]) != WatchContexte.empreinte(["ab": "c"]))
        #expect(WatchContexte.empreinte(["a": "1"]) != WatchContexte.empreinte(["a": true]))
    }

    @Test func memeListeMemesOctets() {
        let tache = WatchTask(id: "1", title: "Pain", due: Date(timeIntervalSince1970: 1_800_000_000), hasTime: true,
                              snoozedUntil: nil, priority: .normal, category: nil, tags: ["courses"], articles: nil)
        #expect(WatchLink.encode([tache, tache]) == WatchLink.encode([tache, tache]))
        #expect(WatchLink.decode(WatchLink.encode([tache])).first?.title == "Pain")
    }
}
