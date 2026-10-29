import CoreLocation
import SwiftUI

/// Réglages › Mes trajets (P9-M2) : relever ses arrêts pour l'historique gardé dans Home Assistant.
/// L'écran des trajets lui-même (carte d'une journée, « déjà venu ici ? ») : `TrajetsCarteView` (M3).
struct TrajetsView: View {
    @State private var actif = TrajetsRecorder.isOn
    @State private var enAttente = TrajetsRecorder.file.count
    @State private var dernierEnvoi = TrajetsRecorder.dernierEnvoi
    @State private var envoi = false
    @State private var trace = TraceRecorder.mode
    @State private var pointsEnAttente = TraceRecorder.file.count

    var body: some View {
        Form {
            if HAConfig.isConfigured {
                Section {
                    NavigationLink("Voir mes trajets") { TrajetsCarteView() }
                } footer: {
                    Text("Aussi depuis l'onglet Carte, sous le « + ».")
                }
            }
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
            // Tracé précis en mouvement (P9-M4, 29/10) : coupé par défaut.
            Section {
                Picker("Tracé précis", selection: Binding(get: { trace }, set: { mode in
                    trace = mode
                    TraceRecorder.shared.choisir(mode)
                    rafraichir()
                })) {
                    ForEach(TraceRecorder.Mode.allCases) { Text($0.titre).tag($0) }
                }
                if trace == .jour, let fin = TraceRecorder.fin {
                    LabeledContent("Jusqu'à", value: fin.formatted(.dateTime.weekday(.wide).hour().minute()))
                }
                if trace != .coupe {
                    LabeledContent("Points en attente", value: "\(pointsEnAttente)")
                    if TrajetsRecorder.shared.authorization != .authorizedAlways {
                        Text("Il faut la localisation « Toujours » : Réglages iOS › Aiguillage › Position.")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                }
            } footer: {
                Text("Un point tous les 50 m à pied, 100 m en voiture, seulement quand tu bouges : iOS coupe le GPS à l'arrêt. La flèche de localisation reste visible pendant le tracé. Quelques % de batterie par jour selon tes déplacements : à mesurer dans Diagnostic batterie. Les points partent vers ton Home Assistant et nulle part ailleurs.")
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
                        await TraceRecorder.shared.envoyer(force: true)
                        rafraichir()
                        envoi = false
                    }
                }
                .disabled(envoi || (enAttente == 0 && pointsEnAttente == 0))
            }
        }
        .navigationTitle("Mes trajets")
        .onAppear(perform: rafraichir)
    }

    private func rafraichir() {
        enAttente = TrajetsRecorder.file.count
        dernierEnvoi = TrajetsRecorder.dernierEnvoi
        trace = TraceRecorder.mode
        pointsEnAttente = TraceRecorder.file.count
    }
}
