import SwiftUI

/// Mémoire de l'app montre pendant qu'elle est à l'écran, et arrêts inattendus (C1 des bonnes pratiques).
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

    func ouvrir() {
        guard !journal.estOuverte else { return }
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

/// Réglages › Diagnostic de la montre : pic de mémoire, arrêts inattendus et erreurs récentes de la montre
/// (la montre a son propre stockage : l'écran Erreurs récentes de l'iPhone ne les voit pas).
struct WatchDiagnosticView: View {
    @State private var actuelMo = Empreinte.megaoctets()
    @State private var journal = JournalSessions()
    @State private var erreurs: [Journal.Entree] = []

    var body: some View {
        let maintenant = Date.now
        let jour = journal.bilan(depuis: Calendar.current.startOfDay(for: maintenant))
        let semaine = journal.bilan(depuis: maintenant.addingTimeInterval(-7 * 86_400))
        List {
            Section("Mémoire") {
                ligne("Maintenant", mo(actuelMo))
                ligne("Pic du jour", mo(jour.picMo))
                ligne("Pic 7 jours", mo(semaine.picMo))
                ligne("À l'écran 7 j", SessionEcran.texteDuree(semaine.tempsEcran))
            }
            Section("Arrêts à l'écran (7 j)") {
                let arrets = journal.arrets(depuis: maintenant.addingTimeInterval(-7 * 86_400))
                if arrets.isEmpty {
                    Text("Aucun").foregroundStyle(.secondary)
                }
                ForEach(arrets.prefix(5), id: \.debut) { s in
                    VStack(alignment: .leading) {
                        Text(s.debut, format: .dateTime.day().month().hour().minute())
                        Text("pic \(mo(s.picMo)), \(SessionEcran.texteDuree(s.duree))")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Erreurs récentes") {
                if erreurs.isEmpty {
                    Text("Aucune").foregroundStyle(.secondary)
                }
                ForEach(erreurs.prefix(10), id: \.self) { e in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.texte).font(.footnote)
                        Text("\(e.date, format: .dateTime.day().month().hour().minute())\(e.fois > 1 ? " · \(e.fois) fois" : "")")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Diagnostic")
        .onAppear {
            SuiviEcran.shared.mesurer()
            actuelMo = Empreinte.megaoctets()
            journal = SuiviEcran.shared.journal
            erreurs = Journal.recentes()
        }
    }

    private func ligne(_ titre: String, _ valeur: String) -> some View {
        LabeledContent(titre, value: valeur)
    }

    private func mo(_ valeur: Double) -> String { valeur > 0 ? "\(Int(valeur.rounded())) Mo" : "—" }
}
