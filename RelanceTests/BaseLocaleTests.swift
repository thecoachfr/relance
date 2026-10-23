import Foundation
import Testing
@testable import Relance

/// Base locale illisible : mise de côté (jamais supprimée) avec ses fichiers annexes.
struct BaseLocaleTests {
    @Test func baseEtAnnexesMisesDeCote() throws {
        let dossier = FileManager.default.temporaryDirectory.appending(path: "base-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dossier) }
        let base = dossier.appending(path: "default.store")
        for annexe in ["", "-wal", "-shm"] { try Data("abîmée".utf8).write(to: URL(fileURLWithPath: base.path + annexe)) }

        let nom = try #require(AppGroup.mettreDeCote(base))
        #expect(nom.hasPrefix("default.store.abimee-"))
        let restants = try FileManager.default.contentsOfDirectory(atPath: dossier.path).sorted()
        #expect(restants.count == 3)
        #expect(restants.allSatisfy { $0.contains(".abimee-") })
        #expect(!FileManager.default.fileExists(atPath: base.path))
    }

    @Test func rienAMettreDeCote() {
        let absente = FileManager.default.temporaryDirectory.appending(path: "absente-\(UUID().uuidString).store")
        #expect(AppGroup.mettreDeCote(absente) == nil)
    }
}
