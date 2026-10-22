import CoreLocation
import SwiftUI

/// Réglages › Mes trajets (P9-M2) : relever ses arrêts pour l'historique gardé dans Home Assistant.
/// L'écran des trajets lui-même (carte d'une journée, « déjà venu ici ? ») viendra avec M3.
struct TrajetsView: View {
    @State private var actif = TrajetsRecorder.isOn
    @State private var enAttente = TrajetsRecorder.file.count
    @State private var dernierEnvoi = TrajetsRecorder.dernierEnvoi
    @State private var envoi = false

    var body: some View {
        Form {
            Section {
                Toggle("Relever mes arrêts", isOn: $actif)
                    .onChange(of: actif) { _, on in TrajetsRecorder.shared.activer(on) }
                if actif && TrajetsRecorder.shared.authorization != .authorizedAlways {
                    Text("Il faut la localisation « Toujours » : Réglages iOS › Aiguillage › Position.")
                        .font(.footnote).foregroundStyle(.orange)
                }
            } footer: {
                Text("iOS note où tu t'arrêtes (arrivée, départ, lieu) sans GPS continu : presque rien sur la batterie. Les arrêts partent par lots vers ton Home Assistant et nulle part ailleurs. Les positions de l'app Compagnon y sont aussi gardées.")
            }
            Section("Envoi") {
                LabeledContent("En attente", value: "\(enAttente) arrêt(s)")
                LabeledContent("Dernier envoi") {
                    if let dernierEnvoi {
                        Text(dernierEnvoi, format: .dateTime.day().month().hour().minute())
                    } else {
                        Text("—")
                    }
                }
                Button(envoi ? "Envoi…" : "Envoyer maintenant") {
                    Task {
                        envoi = true
                        await TrajetsRecorder.shared.envoyer(force: true)
                        rafraichir()
                        envoi = false
                    }
                }
                .disabled(envoi || enAttente == 0)
            }
        }
        .navigationTitle("Mes trajets")
        .onAppear(perform: rafraichir)
    }

    private func rafraichir() {
        enAttente = TrajetsRecorder.file.count
        dernierEnvoi = TrajetsRecorder.dernierEnvoi
    }
}
