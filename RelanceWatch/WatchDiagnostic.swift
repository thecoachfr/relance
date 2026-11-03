import SwiftUI

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
