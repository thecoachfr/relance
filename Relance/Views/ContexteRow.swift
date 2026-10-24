import SwiftUI

/// Ligne « Où la faire » de la fiche (P9-N2, 24/10/2026) : au bureau ou à la maison. Une tâche sans date à qui l'on
/// donne un contexte prend la date du prochain jour qui correspond (jour de bureau ; télétravail ou repos pour la
/// maison, aujourd'hui compris), d'après `sensor.aiguillage_lieu_travail` ; rien dans les 14 jours : elle reste sans date.
/// Seulement en mode Home Assistant (le champ `contexte` n'existe pas dans Google Tasks).
struct ContexteRow: View {
    @Environment(TaskStore.self) private var store
    @Binding var notes: String
    @Binding var hasDay: Bool
    @Binding var day: Date

    var body: some View {
        if HAConfig.isActive {
            Picker("Où la faire", systemImage: "briefcase", selection: Binding<String>(
                get: { ContexteTache(notes: notes)?.rawValue ?? "" },
                set: { choisir(ContexteTache(rawValue: $0)) })) {
                Text("N'importe où").tag("")
                ForEach(ContexteTache.allCases) { Text($0.ligne).tag($0.rawValue) }
            }
        }
    }

    private func choisir(_ contexte: ContexteTache?) {
        notes = ContexteTache.notes(notes, setting: contexte)
        if let date = Self.dateProposee(contexte, aDejaUneDate: hasDay, lieu: store.lieuTravail) {
            day = date
            hasDay = true
        }
    }

    /// La date à donner : seulement à une tâche sans date, d'après les jours publiés par le capteur.
    static func dateProposee(_ contexte: ContexteTache?, aDejaUneDate: Bool, lieu: LieuTravail?,
                             maintenant: Date = .now, calendar: Calendar = .current) -> Date? {
        guard let contexte, !aDejaUneDate else { return nil }
        return lieu?.prochainJour(pour: contexte, aPartirDe: maintenant, calendar: calendar)
    }
}
