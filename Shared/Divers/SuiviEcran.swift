import SwiftUI

/// Mémoire de l'app pendant qu'elle est à l'écran, et arrêts inattendus (C1 des bonnes pratiques). Montre depuis
/// le 23/10, iPhone et iPad depuis le 03/11 (revue batterie : rien n'était mesuré hors de la montre).
/// Une session = le temps passé en `.active` ; les réveils en arrière-plan (rafraîchissement, complications) n'en
/// ouvrent pas. Une mesure toutes les 10 s, seulement à l'écran ; écriture si le pic monte de 1 Mo ou toutes les 30 s.
@MainActor
final class SuiviEcran {
    static let shared = SuiviEcran()
    static let periode: Duration = .seconds(10)

    private let registre: RegistreSessions
    private(set) var journal: JournalSessions
    private var cadence = CadenceEcriture()

    init(registre: RegistreSessions = .partage) {
        self.registre = registre
        self.journal = registre.charger()
    }

    /// Hôte des tests : chaque arrêt du lanceur de tests compterait comme un arrêt inattendu.
    private static let enTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    func ouvrir() {
        guard !Self.enTests, !journal.estOuverte else { return }
        let maintenant = Date.now, mo = Empreinte.megaoctets()
        if let arretee = journal.ouvrir(a: maintenant, mo: mo) {
            Journal.echec(.systeme, arretee.messageArret)
        }
        cadence.reinitialiser()
        cadence.ecrit(a: maintenant, pic: mo)
        registre.enregistrer(journal)
    }

    func mesurer() {
        guard journal.estOuverte else { return }
        let maintenant = Date.now
        journal.mesurer(a: maintenant, mo: Empreinte.megaoctets())
        if cadence.doitEcrire(a: maintenant, pic: journal.picSessionOuverte ?? 0) { registre.enregistrer(journal) }
    }

    func fermer() {
        guard journal.estOuverte else { return }
        journal.fermer(a: .now, mo: Empreinte.megaoctets())
        registre.enregistrer(journal)
    }
}

/// Suit la phase de la scène : session ouverte à l'arrivée en `.active`, fermée dès qu'on en sort.
/// La boucle est annulée au changement de phase : rien ne tourne quand l'app n'est pas à l'écran.
struct SuiviEcranModifier: ViewModifier {
    @Environment(\.scenePhase) private var phase

    func body(content: Content) -> some View {
        content.task(id: phase) {
            let suivi = SuiviEcran.shared
            guard phase == .active else { suivi.fermer(); return }
            suivi.ouvrir()
            while !Task.isCancelled {
                try? await Task.sleep(for: SuiviEcran.periode)
                guard !Task.isCancelled else { break }
                suivi.mesurer()
            }
        }
    }
}

extension View {
    func suiviEcran() -> some View { modifier(SuiviEcranModifier()) }
}
