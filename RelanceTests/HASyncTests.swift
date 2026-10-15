import DonneesHA
import Foundation
import Testing
@testable import Relance

/// Format des tâches rangées dans Home Assistant.
struct TacheHATests {
    @Test func roundTripKeepsEveryField() throws {
        let calendar = Calendar.current
        let item = TaskItem(title: "Appeler le garage", notes: "📍 Garage · 1 rue X\nApporter la carte grise",
                            dueDay: calendar.date(from: DateComponents(year: 2026, month: 10, day: 16)), dueMinutes: 15 * 60)
        item.category = "Maison"
        item.priority = .urgent
        item.tags = ["SCI", "Travaux"]
        item.remindersRaw = "Prévenir 1 jour avant"
        item.googleID = "abc"

        let tache = TacheHA(item)
        #expect(tache.jour == "2026-10-16" && tache.heure == "15:00" && tache.priorite == "Urgente")

        let copy = TaskItem(title: "")
        try TacheHA(valeur: tache.valeur()).apply(to: copy)
        #expect(copy.title == item.title && copy.notes == item.notes)
        #expect(copy.dueDay == item.dueDay && copy.dueMinutes == 15 * 60)
        #expect(copy.category == "Maison" && copy.priority == .urgent && copy.tags == ["SCI", "Travaux"])
        #expect(copy.remindersRaw == "Prévenir 1 jour avant" && copy.googleID == "abc" && !copy.isDirty)
    }

    /// Même clé que la vigie (`uuid.uuid5(INBOX_NAMESPACE, "g1")` en Python).
    @Test func keyFromGoogleIDMatchesTheVigie() {
        #expect(TacheHA.key(googleID: "g1").uuidString.lowercased() == "071cad17-b943-5462-a98a-8d5fa1b7ca11")
    }

    /// Champs absents non écrits ; une tâche écrite par la vigie (sans `v` ni `fait`) se relit.
    @Test func compactJSONAndLenientDecoding() throws {
        let json = String(decoding: try JSONEncoder().encode(TacheHA(titre: "Pain")), as: UTF8.self)
        #expect(json.contains("\"titre\":\"Pain\"") && !json.contains("heure") && !json.contains("tags"))

        let fromVigie = try JSONDecoder().decode(TacheHA.self, from: Data(#"{"titre":"Pain","jour":"2026-10-20","google_id":"g1"}"#.utf8))
        #expect(fromVigie.fait == false && fromVigie.minutes == nil && fromVigie.googleID == "g1")
    }
}

/// `TaskStore` branché sur un faux Home Assistant : les deux critères de la migration.
@MainActor
@Suite(.serialized)
struct TaskStoreHATests {
    @Test(.timeLimit(.minutes(1)))
    func offlineWriteGoesToICloudThenToHA() async throws {
        let server = FakeHA()
        let folder = temporaryFolder()
        let store = haStore()
        store.synchro = try makeSynchro(device: "iphone-test", server: server, fallback: folder)

        await server.setOnline(false)
        let item = store.add(title: "Écrite hors ligne", day: nil, minutes: nil)
        await store.sync()
        #expect(store.synchro?.etat == .horsLigne(enAttente: 1))
        let snapshot = try #require(try await DossierFallback(racine: folder).lireTous(espace: HAConfig.espace).first)
        #expect(snapshot.outbox.map(\.cle) == [TaskStore.haKey(item)])

        await server.setOnline(true)
        await store.sync()
        #expect(store.synchro?.etat == .aJour)
        let stored = try #require(await server.record(TaskStore.haKey(item)))
        #expect(try TacheHA(valeur: stored.valeur).titre == "Écrite hors ligne")
        #expect(await server.appliedWrites == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func mostRecentEditWinsAcrossDevices() async throws {
        let server = FakeHA()
        let folder = temporaryFolder()
        let clock = TestClock()
        let phone = haStore()
        let pad = haStore()
        phone.synchro = try makeSynchro(device: "iphone-test", server: server, fallback: folder, clock: clock)
        pad.synchro = try makeSynchro(device: "ipad-test", server: server, fallback: folder, clock: clock)

        let item = phone.add(title: "Départ", day: nil, minutes: nil)
        await phone.sync()
        await pad.sync()
        let onPad = try #require(pad.task(item.localID))

        clock.advance(10)
        pad.update(onPad, title: "Modifiée sur l'iPad", notes: "", day: nil, minutes: nil)
        clock.advance(10)
        phone.update(item, title: "Modifiée sur l'iPhone, plus tard", notes: "", day: nil, minutes: nil)
        await pad.sync()      // l'iPad passe en premier…
        await phone.sync()    // …mais l'iPhone a modifié plus tard : il gagne le conflit
        await pad.sync()

        #expect(item.title == "Modifiée sur l'iPhone, plus tard")
        #expect(pad.task(item.localID)?.title == "Modifiée sur l'iPhone, plus tard")
        #expect(phone.synchro?.dernierConflit != nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func deletionReachesTheOtherDevice() async throws {
        let server = FakeHA()
        let folder = temporaryFolder()
        let phone = haStore()
        let pad = haStore()
        phone.synchro = try makeSynchro(device: "iphone-test", server: server, fallback: folder)
        pad.synchro = try makeSynchro(device: "ipad-test", server: server, fallback: folder)

        let item = phone.add(title: "À supprimer", day: nil, minutes: nil)
        await phone.sync()
        await pad.sync()
        #expect(pad.task(item.localID) != nil)
        phone.delete(item)
        await phone.sync()
        await pad.sync()
        #expect(pad.task(item.localID) == nil)
    }

    /// L'iPhone et l'iPad migrent chacun leur copie des mêmes tâches Google (identifiants locaux
    /// différents) : une seule clé par tâche dans HA (constaté le 15/10 : 24 doublons avant correction).
    @Test(.timeLimit(.minutes(1)))
    func twoDevicesMigratingTheSameGoogleTasksMakeNoDuplicate() async throws {
        let server = FakeHA()
        let folder = temporaryFolder()
        func device(_ name: String) throws -> TaskStore {
            let store = TaskStore(auth: SignedOut(), inMemory: true)
            store.haActiveOverride = false
            let synchro = try makeSynchro(device: name, server: server, fallback: folder)
            store.makeSynchroniser = { synchro }
            for (googleID, title) in [("g1", "Garage"), ("g2", "Impôts")] {
                let item = store.add(title: title, day: nil, minutes: nil)
                item.googleID = googleID
                item.isDirty = false
            }
            return store
        }
        let phone = try device("iphone-test")
        let pad = try device("ipad-test")

        #expect(await phone.activateHA() == nil)
        #expect(await pad.activateHA() == nil)
        await phone.sync()

        let keys = await server.liveKeys()
        #expect(keys.count == 2)
        #expect(Set(keys) == Set(["g1", "g2"].map { TacheHA.key(googleID: $0).uuidString.lowercased() }))
        #expect(phone.activeTasks().count == 2 && pad.activeTasks().count == 2)
        #expect(Set(phone.activeTasks().map(\.localID)) == Set(pad.activeTasks().map(\.localID)))
    }

    // MARK: - Outils

    private func haStore() -> TaskStore {
        let store = TaskStore(auth: SlowAccount(), inMemory: true)
        store.haActiveOverride = true
        return store
    }

    private func makeSynchro(device: String, server: FakeHA, fallback: URL, clock: TestClock = TestClock()) throws -> Synchroniseur {
        let base = try BaseLocale(fichier: temporaryFolder().appending(path: "\(device).sqlite"))
        return Synchroniseur(espace: HAConfig.espace, appareil: device, base: base, serveur: server,
                             fallback: DossierFallback(racine: fallback), horloge: clock.now, antiRebond: .seconds(3600))
    }

    private func temporaryFolder() -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "HASyncTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// Sans compte Google (la migration saute alors la dernière synchro Google).
final class SignedOut: AccountProvider {
    var isSignedIn: Bool { false }
    func accessToken() async throws -> String { throw TasksAPIError.notSignedIn }
    func signOut() {}
    var watchCredentials: (refreshToken: String, clientID: String)? { nil }
}

/// Horloge des appareils, réglable (« la plus récente gagne » dépend de `modifie_le`).
nonisolated final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_791_000_000)
    func advance(_ seconds: TimeInterval) { lock.withLock { current += seconds } }
    var now: @Sendable () -> Date { { [self] in lock.withLock { current } } }
}

/// Faux `donnees_apps` : versions, `seq`, `op_id` rejoués, conflits.
actor FakeHA: ServeurDonnees {
    private var online = true
    private var seq = 0
    private var records: [String: Enregistrement] = [:]
    private var applied: [String: ResultatOperation] = [:]
    private(set) var appliedWrites = 0

    func setOnline(_ value: Bool) { online = value }
    func record(_ key: String) -> Enregistrement? { records[key] }
    func liveKeys() -> [String] { records.values.filter { !$0.supprime }.map(\.cle) }

    func changements(espace: String, depuisSeq: Int) async throws -> ReponseChangements {
        guard online else { throw ErreurHA.injoignable("coupé") }
        return ReponseChangements(enregistrements: records.values.filter { $0.seq > depuisSeq }.sorted { $0.seq < $1.seq },
                                  seqMax: seq, resynchroComplete: false)
    }

    func lot(espace: String, operations: [OperationDonnees]) async throws -> ReponseLot {
        guard online else { throw ErreurHA.injoignable("coupé") }
        return ReponseLot(resultats: operations.map(apply), seqMax: seq)
    }

    private func apply(_ op: OperationDonnees) -> ResultatOperation {
        if var done = applied[op.opId] {
            done.rejoue = true
            return done
        }
        let current = records[op.cle]
        let version = current?.version ?? 0
        if let expected = op.versionAttendue, expected != version {
            return ResultatOperation(statut: .conflit, cle: op.cle, version: version, serveur: current)
        }
        seq += 1
        appliedWrites += 1
        let deleted = op.type == .supprimer
        records[op.cle] = Enregistrement(cle: op.cle, valeur: deleted ? .null : (op.valeur ?? .null), version: version + 1,
                                         seq: seq, modifieLe: op.modifieLe, modifiePar: op.modifiePar, supprime: deleted)
        let result = ResultatOperation(statut: .ok, cle: op.cle, version: version + 1, seq: seq, supprime: deleted, rejoue: false)
        applied[op.opId] = result
        return result
    }
}
