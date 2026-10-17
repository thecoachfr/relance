import CoreLocation
import SwiftUI

/// Réglages › Mes lieux (P9-H2) : mes lieux habituels rangés en groupes. Une tâche rattachée à un groupe (« Me le
/// rappeler près de… », ou automatiquement une liste d'achats pour Supermarchés) me prévient près de l'un d'eux.
struct MesLieuxView: View {
    @Environment(TaskStore.self) private var store
    @State private var ajoutDans: String?
    @State private var nouveauGroupe = false
    @State private var nomDuGroupe = ""
    @State private var erreur: String?

    var body: some View {
        Form {
            ForEach(store.mesLieux.groupes) { groupe in
                Section {
                    ForEach(groupe.lieux) { lieu in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lieu.nom)
                            if let adresse = lieu.adresse, adresse != lieu.nom {
                                Text(adresse).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    .onDelete { offsets in modifier(groupe.id) { $0.lieux.remove(atOffsets: offsets) } }
                    Button("Ajouter un lieu", systemImage: "plus.circle") { ajoutDans = groupe.id }
                } header: {
                    Text(groupe.nom)
                } footer: {
                    if groupe.id == MesLieux.supermarches {
                        Text("Une liste d'achats pas finie (catégorie Achats) te prévient à 150 m de l'un de ces lieux, au plus une fois toutes les 2 heures.")
                    }
                }
            }
            Section {
                Button("Nouveau groupe", systemImage: "folder.badge.plus") { nouveauGroupe = true }
                if let erreur { Text(erreur).font(.footnote).foregroundStyle(.red) }
            } footer: {
                Text("Pour une autre tâche : section Actions › Me le rappeler près de… Les lieux sont partagés avec tes autres appareils. iOS surveille 20 zones au plus : les plus proches de toi.")
            }
        }
        .navigationTitle("Mes lieux")
        .inlineNavigationTitle()
        .sheet(item: Binding(get: { ajoutDans.map(Identite.init) }, set: { ajoutDans = $0?.id })) { cible in
            PlaceSearchView { contact in ajouter(contact, dans: cible.id) }
        }
        .alert("Nouveau groupe", isPresented: $nouveauGroupe) {
            TextField("Pharmacies", text: $nomDuGroupe)
            Button("Créer") { creerGroupe() }
            Button("Annuler", role: .cancel) { nomDuGroupe = "" }
        }
        .onAppear(perform: ProximityReminders.shared.requestAuthorization)
    }

    private struct Identite: Identifiable { let id: String }

    private func modifier(_ groupe: String, _ change: (inout MesLieux.Groupe) -> Void) {
        var lieux = store.mesLieux
        guard let i = lieux.groupes.firstIndex(where: { $0.id == groupe }) else { return }
        change(&lieux.groupes[i])
        store.setMesLieux(lieux)
    }

    private func creerGroupe() {
        let nom = nomDuGroupe.trimmingCharacters(in: .whitespaces)
        nomDuGroupe = ""
        guard !nom.isEmpty else { return }
        var lieux = store.mesLieux
        lieux.groupes.append(.init(id: UUID().uuidString.lowercased(), nom: nom))
        store.setMesLieux(lieux)
    }

    /// Le lieu choisi, avec ses coordonnées (lien Plans du point, sinon l'adresse cherchée par Plans).
    private func ajouter(_ contact: TaskContact, dans groupe: String) {
        Task {
            var point = contact.coordinate
            if point == nil, let adresse = contact.address,
               let place = try? await CLGeocoder().geocodeAddressString(adresse).first?.location {
                point = (place.coordinate.latitude, place.coordinate.longitude)
            }
            guard let point else {
                erreur = "Pas de position pour « \(contact.name) » : choisis-le sur la carte."
                return
            }
            erreur = nil
            modifier(groupe) {
                $0.lieux.append(.init(nom: contact.name, adresse: contact.address, lat: point.latitude, lon: point.longitude))
            }
        }
    }
}
