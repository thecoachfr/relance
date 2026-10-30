import XCTest

/// Captures d'écran pour les revues d'ergonomie (28/10/2026) : l'app en mode démo, chaque écran ouvert par ses
/// arguments de lancement (`-reglages`, `-sousreglage`, `-fiche`), puis des captures en faisant défiler jusqu'en bas.
/// Les PNG vont dans /tmp/captures-relance (le simulateur écrit sur le disque du Mac).
/// Lancer : xcodebuild -scheme RelanceCaptures -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' test
nonisolated final class Captures: XCTestCase {
    private let dossier = URL(fileURLWithPath: "/tmp/captures-relance")

    override func setUp() {
        continueAfterFailure = true
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
    }

    @MainActor private func ouvrir(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-onboardingDone", "YES"] + arguments
        app.launch()
        sleep(3)
        return app
    }

    /// Captures successives en faisant défiler, jusqu'à ce que l'écran ne change plus (8 au plus).
    @MainActor private func defiler(_ app: XCUIApplication, _ nom: String) {
        var precedente: Data?
        for i in 1...8 {
            let png = XCUIScreen.main.screenshot().pngRepresentation
            if png == precedente { break }
            try? png.write(to: dossier.appendingPathComponent("\(nom)-\(i).png"))
            precedente = png
            let depart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
            depart.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)))
            sleep(1)
        }
    }

    @MainActor func testReglages() { defiler(ouvrir(["-reglages", "1"]), "reglages") }
    @MainActor func testRelances() { defiler(ouvrir(["-reglages", "1", "-sousreglage", "relances"]), "relances") }
    @MainActor func testFicheAvecLieu() { defiler(ouvrir(["-fiche", "Réserver le contrôle"]), "fiche-lieu") }
    @MainActor func testFicheSimple() { defiler(ouvrir(["-fiche", "Acheter un cadeau"]), "fiche-simple") }
    @MainActor func testFicheEnvie() { defiler(ouvrir(["-fiche", "Chez Janou"]), "fiche-envie") }
    /// iPad (deux colonnes) : lancer avec une destination iPad, `-only-testing:RelanceCaptures/Captures/testIPad`.
    @MainActor func testIPad() {
        let app = ouvrir(["-fiche", "Réserver le contrôle"])
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: dossier.appendingPathComponent("ipad-fiche.png"))
        _ = app
    }
    /// Vue Agenda d'À faire (30/10).
    @MainActor func testAgenda() {
        _ = ouvrir(["-todoAffichage", "agenda"])
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: dossier.appendingPathComponent("agenda.png"))
    }
    @MainActor func testEnvies() { defiler(ouvrir(["-reglages", "1", "-sousreglage", "envies"]), "envies") }
}
