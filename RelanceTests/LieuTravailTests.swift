import DonneesHA
import Foundation
import Testing
@testable import Relance

/// Lieu de travail dans Aiguillage (P9-N2, 24/10/2026) : capteur, contexte des tâches, réglages écrits dans HA.
struct LieuTravailTests {
    static let paris: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        return c
    }()

    static func jour(_ date: String, _ lieu: String, certitude: String = "sur", source: String = "semaine") -> [String: Any] {
        let libelles = ["bureau": "🏢 Bureau", "lab": "🧪 Le Lab", "teletravail": "🏠 Télétravail", "off": "Repos",
                        "ferie": "Férié"]
        return ["date": date, "jour": "x", "lieu": lieu, "certitude": certitude, "source": source,
                "libelle": libelles[lieu]! + (certitude == "probable" ? " ?" : "")]
    }

    /// Réponse de `GET /api/states/sensor.aiguillage_lieu_travail`, comme le 24/10 (samedi).
    static let reponse: Data = {
        let jours = [jour("2026-10-24", "off"), jour("2026-10-25", "off"), jour("2026-10-26", "bureau"),
                     jour("2026-10-27", "teletravail"), jour("2026-10-28", "bureau", certitude: "probable"),
                     jour("2026-10-29", "lab", source: "exception"), jour("2026-11-01", "ferie", source: "ferie")]
        let objet: [String: Any] = ["entity_id": "sensor.aiguillage_lieu_travail", "state": "off",
                                    "attributes": ["phrase": "Pas de Barrière aujourd'hui · lundi 🏢 Bureau", "jours": jours,
                                                   "aujourdhui": jours[0], "suggestion": NSNull(),
                                                   "maj": "2026-10-24T11:57:29+02:00", "stats": [:]]]
        return try! JSONSerialization.data(withJSONObject: objet)
    }()

    static func date(_ texte: String) -> Date { LieuTravail.date(texte, calendar: paris)! }

    // MARK: - Capteur

    @Test func decodesTheSensor() throws {
        let lieu = try #require(LieuTravail(etatHA: Self.reponse))
        #expect(lieu.etat == "off" && lieu.phrase == "Pas de Barrière aujourd'hui · lundi 🏢 Bureau")
        #expect(lieu.jours.count == 7 && lieu.suggestion == nil && lieu.maj == "2026-10-24T11:57:29+02:00")
        #expect(lieu.jours[4].libelle == "🏢 Bureau ?" && lieu.jours[5].estTravaille && !lieu.jours[0].estTravaille)
        #expect(lieu.jour(Self.date("2026-10-27"), calendar: Self.paris)?.lieu == "teletravail")
        #expect(lieu.bandeau == lieu.phrase)
        #expect(ConfigLieuTravail.libelle("off") == "Repos")
        // Jour non travaillé : `phrase` nulle ou vide, bandeau caché, mais les jours restent lisibles (écran, fiche).
        for phrase in ["null", #""""#, #"" ""#] {
            let brut = #"{"state":"off","attributes":{"phrase":\#(phrase),"jours":[{"date":"2026-10-24","jour":"samedi","lieu":"off","certitude":"sur","source":"semaine","libelle":"Repos"}]}}"#
            let repos = try #require(LieuTravail(etatHA: Data(brut.utf8)))
            #expect(repos.bandeau == nil && repos.jours.count == 1)
        }
        // Indisponible, vide ou illisible : rien.
        for brut in [#"{"state":"unavailable","attributes":{}}"#, #"{"state":"off","attributes":{"phrase":null}}"#, "x"] {
            #expect(LieuTravail(etatHA: Data(brut.utf8)) == nil)
        }
    }

    @Test func nextMatchingDay() throws {
        let lieu = try #require(LieuTravail(etatHA: Self.reponse))
        let samedi = Self.date("2026-10-24").addingTimeInterval(15 * 3600)
        #expect(lieu.prochainJour(pour: .bureau, aPartirDe: samedi, calendar: Self.paris) == Self.date("2026-10-26"))
        // Maison : télétravail, ou jour sans Barrière, aujourd'hui compris.
        #expect(lieu.prochainJour(pour: .maison, aPartirDe: samedi, calendar: Self.paris) == Self.date("2026-10-24"))
        let lundi = Self.date("2026-10-26")
        #expect(lieu.prochainJour(pour: .maison, aPartirDe: lundi, calendar: Self.paris) == Self.date("2026-10-27"))
        // Le Lab n'est pas « au bureau » ; rien après le 28 : pas de date.
        #expect(lieu.prochainJour(pour: .bureau, aPartirDe: Self.date("2026-10-29"), calendar: Self.paris) == nil)
    }

    @Test func proposedDateOnlyForATaskWithoutDate() throws {
        let lieu = try #require(LieuTravail(etatHA: Self.reponse))
        let samedi = Self.date("2026-10-24")
        #expect(ContexteRow.dateProposee(.bureau, aDejaUneDate: false, lieu: lieu, maintenant: samedi,
                                         calendar: Self.paris) == Self.date("2026-10-26"))
        #expect(ContexteRow.dateProposee(.bureau, aDejaUneDate: true, lieu: lieu, maintenant: samedi, calendar: Self.paris) == nil)
        #expect(ContexteRow.dateProposee(.bureau, aDejaUneDate: false, lieu: nil, maintenant: samedi, calendar: Self.paris) == nil)
        #expect(ContexteRow.dateProposee(nil, aDejaUneDate: false, lieu: lieu, maintenant: samedi, calendar: Self.paris) == nil)
    }

    @Test func watchGetsWorkedDaysOnly() throws {
        let lieu = try #require(LieuTravail(etatHA: Self.reponse))
        let lieux = WatchLink.decodeLieux(lieu.pourLaMontre)
        #expect(lieux == ["2026-10-26": "🏢 Bureau", "2026-10-27": "🏠 Télétravail", "2026-10-28": "🏢 Bureau ?",
                          "2026-10-29": "🧪 Le Lab"])
        #expect(lieu.pourLaMontre == lieu.pourLaMontre)   // octets stables
        #expect(WatchLink.libelleDuJour(lieux, date: Self.date("2026-10-27"), calendar: Self.paris) == "🏠 Télétravail")
        #expect(WatchLink.libelleDuJour(lieux, date: Self.date("2026-10-24"), calendar: Self.paris) == nil)
    }

    // MARK: - Contexte des tâches

    @Test func contextLineIsACopyOfTheField() throws {
        let item = TaskItem(title: "Rendre le badge", notes: "Au 3e")
        item.notes = ContexteTache.notes(item.notes, setting: .bureau)
        #expect(item.notes == "Au 3e\n🏢 Au bureau" && item.contexte == .bureau)
        #expect(NoteLines.visible(item.notes) == "Au 3e")

        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(TacheHA(item))) as! [String: Any]
        #expect(json["contexte"] as? String == "bureau" && json["v"] as? Int == 2)

        // Reçue de HA : le champ fait foi, la ligne est réécrite (ici : maison au lieu de bureau).
        var tache = TacheHA(item)
        tache.contexte = "maison"
        let copie = TaskItem(title: "")
        tache.apply(to: copie)
        #expect(copie.notes == "Au 3e\n🏠 À la maison" && copie.contexte == .maison)
        // Sans contexte : ligne retirée, champ absent.
        copie.notes = ContexteTache.notes(copie.notes, setting: nil)
        #expect(copie.notes == "Au 3e" && TacheHA(copie).contexte == nil)
    }

    @Test func contextCompatibility() throws {
        // Ancienne tâche ou mode Google : la ligne seule (avec sélecteur de variante) donne le contexte.
        let item = TaskItem(title: "Arroser", notes: "🏠\u{FE0F} À la maison")
        #expect(item.contexte == .maison && TacheHA(item).contexte == "maison")
        // Valeur inconnue écrite par un autre : ignorée, la tâche reste lisible.
        let tache = try JSONDecoder().decode(TacheHA.self, from: Data(#"{"titre":"X","contexte":"lune"}"#.utf8))
        #expect(tache.contexte == nil && tache.titre == "X")
        // Rien à changer : notes identiques à l'octet près.
        #expect(ContexteTache.notes("A\n🏢 Au bureau", setting: .bureau) == "A\n🏢 Au bureau")
        #expect(ContexteTache.notes("A", setting: nil) == "A")
        #expect(ContexteTache.notes("", setting: .maison) == "🏠 À la maison")
    }

    // MARK: - Réglages `config:lieu_travail`

    static let brut: JSONValeur = .objet([
        "v": .entier(1), "futur": .texte("garde-moi"),
        "semaine": .objet(["lundi": .objet(["lieu": .texte("bureau"), "certitude": .texte("sur"), "note": .texte("n")]),
                           "mercredi": .objet(["lieu": .texte("bureau"), "certitude": .texte("probable")])]),
        "premier_vendredi": .objet(["lieu": .texte("bureau"), "certitude": .texte("sur")]),
        "exceptions": .objet(["2026-10-29": .texte("lab"), "2026-08-01": .texte("off"), "abc": .texte("bureau")]),
    ])

    @Test func readsTheSettings() {
        let config = ConfigLieuTravail(valeur: Self.brut)
        #expect(config.semaine["mercredi"] == .init(lieu: "bureau", probable: true))
        #expect(config.semaine["mardi"] == .init(lieu: "teletravail", probable: false))   // défaut
        #expect(config.premierVendredi == .init(lieu: "bureau", probable: false))
        #expect(config.exceptions == ["2026-10-29": "lab", "2026-08-01": "off"])
        #expect(ConfigLieuTravail(valeur: nil) == .parDefaut)
        #expect(ConfigLieuTravail(valeur: .objet(["premier_vendredi": .null])).premierVendredi == nil)
    }

    @Test func modificationsKeepUnknownFields() throws {
        let aujourdhui = Self.date("2026-10-24")
        let valeur = ConfigLieuTravail.appliquer([
            .semaine(jour: "lundi", .init(lieu: "teletravail", probable: true)),
            .exception(date: "2026-10-27", lieu: "bureau"),
            .exception(date: "2026-10-29", lieu: nil),
            .premierVendredi(nil),
        ], a: Self.brut, aujourdhui: aujourdhui, calendar: Self.paris)
        guard case .objet(let o) = valeur, case .objet(let semaine)? = o["semaine"],
              case .objet(let lundi)? = semaine["lundi"], case .objet(let exc)? = o["exceptions"] else {
            Issue.record("format")
            return
        }
        #expect(o["futur"] == .texte("garde-moi") && o["v"] == .entier(1))
        #expect(lundi == ["lieu": .texte("teletravail"), "certitude": .texte("probable"), "note": .texte("n")])
        #expect(semaine["mercredi"] == Self.brut.objet?["semaine"]?.objet?["mercredi"])
        #expect(o["premier_vendredi"] == .null)
        // Exception ajoutée, « Comme prévu » retirée, celle de plus de 30 jours élaguée ; la clé inconnue reste.
        #expect(exc == ["2026-10-27": .texte("bureau"), "abc": .texte("bureau")])
        // Enregistrement absent : on part des défauts de HA.
        let neuf = ConfigLieuTravail(valeur: ConfigLieuTravail.appliquer([.exception(date: "2026-10-30", lieu: "lab")], a: nil,
                                                                         aujourdhui: aujourdhui, calendar: Self.paris))
        #expect(neuf.semaine == ConfigLieuTravail.parDefaut.semaine && neuf.exceptions == ["2026-10-30": "lab"])
    }
}

/// L'écran « Lieu de travail » écrit `config:lieu_travail` par la synchro, version attendue ; une consigne Signal
/// écrite en même temps (conflit) n'est pas perdue : la valeur de HA reçoit la modification de l'appareil.
@MainActor
@Suite(.serialized)
struct LieuTravailSyncTests {
    @Test(.timeLimit(.minutes(1)))
    func writeSurvivesAConcurrentSignalInstruction() async throws {
        let server = FakeHA()
        let cle = ConfigLieuTravail.haKey
        await server.serverWrite(cle, LieuTravailTests.brut)
        let store = TaskStore(auth: SlowAccount(), inMemory: true)
        store.haActiveOverride = true
        store.schedulesReminders = false
        let dossier = FileManager.default.temporaryDirectory.appending(path: "LieuTravail-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        let synchro = Synchroniseur(espace: HAConfig.espace, appareil: "iphone-test",
                                    base: try BaseLocale(fichier: dossier.appending(path: "base.sqlite")), serveur: server,
                                    fallback: DossierFallback(racine: dossier), horloge: TestClock().now,
                                    antiRebond: .seconds(3600))
        store.makeSynchroniser = { synchro }
        await store.sync()
        #expect(store.configLieuTravail?.exceptions["2026-10-29"] == "lab")

        // Pendant ce temps, Signal (« lundi télétravail ») écrit une autre exception dans HA.
        guard case .objet(var signal) = LieuTravailTests.brut, case .objet(var exc)? = signal["exceptions"] else { return }
        exc["2026-11-02"] = .texte("teletravail")
        signal["exceptions"] = .objet(exc)
        await server.serverWrite(cle, .objet(signal))

        store.modifierLieuTravail(.exception(date: "2026-10-27", lieu: "bureau"))
        #expect(store.configLieuTravail?.exceptions["2026-10-27"] == "bureau")   // affichage immédiat
        await store.sync()

        let enHA = try #require(await server.record(cle))
        let config = ConfigLieuTravail(valeur: enHA.valeur)
        #expect(config.exceptions["2026-10-27"] == "bureau" && config.exceptions["2026-11-02"] == "teletravail")
        #expect(enHA.valeur.objet?["futur"] == .texte("garde-moi") && enHA.modifiePar == "iphone-test")
        #expect(store.configLieuTravail == config)
    }
}

private extension JSONValeur {
    var objet: [String: JSONValeur]? { if case .objet(let o) = self { o } else { nil } }
}
