import SwiftUI

/// Ligne « Durée » de la fiche (P9-H1), sous l'heure : l'événement d'agenda dure autant, la liste montre la plage.
/// Seulement en mode Home Assistant (le champ n'existe pas dans Google Tasks).
struct DureeRow: View {
    @Environment(TaskStore.self) private var store
    let item: TaskItem
    @State private var autre = false

    static let choix = [15, 30, 45, 60, 90, 120, 180]

    var body: some View {
        if HAConfig.isActive {
            let duree = item.dureeMinutes
            Picker("Durée", systemImage: "hourglass", selection: Binding<Int>(
                get: { duree.map { Self.choix.contains($0) && !autre ? $0 : -1 } ?? (autre ? -1 : 0) },
                set: { valeur in
                    autre = valeur == -1
                    if valeur >= 0 { store.setDuree(valeur == 0 ? nil : valeur, of: item) }
                    else if duree == nil || Self.choix.contains(duree!) { store.setDuree(240, of: item) }
                })) {
                Text("Aucune").tag(0)
                ForEach(Self.choix, id: \.self) { Text(Self.texte($0)).tag($0) }
                Text(duree.map { Self.choix.contains($0) ? "Autre…" : "Autre (\(Self.texte($0)))" } ?? "Autre…").tag(-1)
            }
            if autre || (duree.map { !Self.choix.contains($0) } ?? false) {
                Stepper(value: Binding(get: { duree ?? 240 }, set: { store.setDuree($0, of: item) }),
                        in: 15...720, step: 15) {
                    Text(Self.texte(duree ?? 240)).monospacedDigit()
                }
                .accessibilityLabel("Durée \(Self.texte(duree ?? 240))")
            }
        }
    }

    /// 45 → « 45 min », 90 → « 1 h 30 », 120 → « 2 h ».
    static func texte(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) h" : "\(h) h \(String(format: "%02d", m))"
    }
}
