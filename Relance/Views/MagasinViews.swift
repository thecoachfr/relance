import MapKit
import SwiftUI

/// Ligne « Magasin » d'une liste d'achats (P9-Q) : où elle me prévient. Automatique (groupe nommé dans le titre, sinon
/// Supermarchés), ou choisi (action « Me le rappeler près de… »). Une enseigne connue sans groupe : création du groupe
/// par une recherche Plans de ses magasins.
struct MagasinSection: View {
    @Environment(TaskStore.self) private var store
    let item: TaskItem
    @State private var creation: Enseigne?

    private struct Enseigne: Identifiable { let id: String }

    var body: some View {
        let lieux = store.mesLieux
        let magasin = lieux.magasin(titre: item.title, actions: item.actions)
        Section {
            Menu {
                Button("Automatique (d'après le titre)", systemImage: "wand.and.stars") { automatique() }
                Divider()
                ForEach(lieux.groupes) { groupe in
                    Button(groupe.nom) { choisir(groupe) }
                }
                if case .enseigneSansGroupe(let enseigne) = magasin {
                    Divider()
                    Button("Créer « \(enseigne) »…", systemImage: "plus") { creation = Enseigne(id: enseigne) }
                }
            } label: {
                LabeledContent {
                    Text(texte(magasin, lieux)).multilineTextAlignment(.trailing)
                } label: {
                    Label("Magasin", systemImage: "storefront")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if case .enseigneSansGroupe(let enseigne) = magasin {
                Button("Chercher les magasins \(enseigne)", systemImage: "magnifyingglass") { creation = Enseigne(id: enseigne) }
            }
        } footer: {
            Text(pied(magasin, lieux))
        }
        .sheet(item: $creation) { EnseigneSearchView(enseigne: $0.id) }
    }

    private func texte(_ magasin: MesLieux.Magasin, _ lieux: MesLieux) -> String {
        switch magasin {
        case .choisi(let ids): ids.compactMap { lieux.groupe($0)?.nom }.joined(separator: ", ")
        case .nomme(let id): (lieux.groupe(id)?.nom ?? "?") + " (auto)"
        case .enseigneSansGroupe(let e): e + " : aucun magasin"
        case .supermarches: "Supermarchés (auto)"
        }
    }

    private func pied(_ magasin: MesLieux.Magasin, _ lieux: MesLieux) -> String {
        if case .enseigneSansGroupe(let e) = magasin {
            return "Crée le groupe « \(e) » pour être prévenu près de ses magasins. D'ici là, pas de rappel en passant (pas aux supermarchés non plus)."
        }
        let ids: [String] = switch magasin {
        case .choisi(let ids): ids
        case .nomme(let id): [id]
        case .supermarches, .enseigneSansGroupe: [MesLieux.supermarches]
        }
        let n = ids.compactMap { lieux.groupe($0)?.lieux.count }.reduce(0, +)
        return n == 0 ? "Ajoute des lieux à ce groupe dans Réglages › Mes lieux pour être prévenu en passant devant."
            : "Rappel à 150 m de l'un de ces \(n) lieu\(n > 1 ? "x" : ""), tant que la liste n'est pas finie."
    }

    private func automatique() {
        for action in item.actions where action.type == TacheHA.Action.rappelGroupe {
            store.removeAction(id: action.id, from: item)
        }
    }

    private func choisir(_ groupe: MesLieux.Groupe) {
        automatique()
        store.addAction(.pres(groupe: groupe.id, nom: groupe.nom), to: item)
    }
}

/// Création d'un groupe d'enseigne (P9-Q) : les magasins de l'enseigne autour du domicile et des lieux de travail,
/// trouvés par Plans, les plus proches cochés d'office. Le groupe porte le nom de l'enseigne : la règle « nommé dans
/// le titre » le prend aussitôt.
struct EnseigneSearchView: View {
    @Environment(TaskStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let enseigne: String
    @State private var trouves: [Trouve] = []
    @State private var coches: Set<String> = []
    @State private var recherche = true

    struct Trouve: Identifiable, Equatable {
        var id: String { "\(lieu.lat),\(lieu.lon)" }
        let lieu: MesLieux.Lieu
        /// Distance au plus proche de mes lieux de départ (domicile, travail), en kilomètres.
        let km: Double
    }

    var body: some View {
        NavigationStack {
            List {
                if recherche {
                    HStack { ProgressView(); Text("Recherche des magasins \(enseigne)…").foregroundStyle(.secondary) }
                } else if trouves.isEmpty {
                    Text("Aucun magasin \(enseigne) trouvé près de chez toi ou du travail. Tu peux en ajouter un à la main dans Réglages › Mes lieux.")
                        .foregroundStyle(.secondary)
                }
                ForEach(trouves) { t in
                    Button {
                        if coches.contains(t.id) { coches.remove(t.id) } else { coches.insert(t.id) }
                    } label: {
                        HStack {
                            Image(systemName: coches.contains(t.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(coches.contains(t.id) ? Color.accentColor : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.lieu.nom)
                                if let adresse = t.lieu.adresse { Text(adresse).font(.subheadline).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Text(t.km < 1 ? "\(Int(t.km * 1000)) m" : String(format: "%.1f km", t.km))
                                .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(coches.contains(t.id) ? .isSelected : [])
                }
            }
            .navigationTitle(enseigne)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Créer") { creer() }.disabled(coches.isEmpty)
                }
            }
            .task { await chercher() }
        }
    }

    /// Mes lieux de départ : le domicile et les lieux d'un groupe « Travail ».
    private var departs: [CLLocationCoordinate2D] {
        let lieux = store.mesLieux
        let travail = lieux.groupes.filter { MesLieux.normaliser($0.nom) == "travail" }.flatMap(\.lieux)
        return ([lieux.domicile].compactMap { $0 } + travail).map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
    }

    private func chercher() async {
        defer { recherche = false }
        var resultats: [String: Trouve] = [:]
        let centres = departs
        for centre in centres.isEmpty ? [nil] : centres.map(Optional.some) {
            let requete = MKLocalSearch.Request()
            requete.naturalLanguageQuery = enseigne
            requete.resultTypes = .pointOfInterest
            if let centre { requete.region = MKCoordinateRegion(center: centre, latitudinalMeters: 30_000, longitudinalMeters: 30_000) }
            guard let items = try? await MKLocalSearch(request: requete).start().mapItems else { continue }
            for item in items {
                let nom = item.name ?? enseigne
                // Seulement l'enseigne (Plans propose aussi des magasins voisins ou concurrents).
                guard MesLieux.nomme(enseigne, dans: nom) else { continue }
                let c = item.placemark.coordinate
                let km = centres.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude)
                    .distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude)) / 1000 }.min() ?? 0
                let lieu = MesLieux.Lieu(nom: nom, adresse: PlaceSearchView.address(of: item), lat: c.latitude, lon: c.longitude)
                let t = Trouve(lieu: lieu, km: km)
                if resultats[t.id] == nil { resultats[t.id] = t }
            }
        }
        trouves = resultats.values.sorted { $0.km < $1.km }
        // Les plus proches cochés d'office : à moins de 8 km, 4 au plus.
        coches = Set(trouves.filter { $0.km <= 8 }.prefix(4).map(\.id))
    }

    private func creer() {
        var lieux = store.mesLieux
        let choisis = trouves.filter { coches.contains($0.id) }.map(\.lieu)
        if let i = lieux.groupes.firstIndex(where: { MesLieux.normaliser($0.nom) == MesLieux.normaliser(enseigne) }) {
            lieux.groupes[i].lieux += choisis.filter { c in !lieux.groupes[i].lieux.contains { $0.lat == c.lat && $0.lon == c.lon } }
        } else {
            lieux.groupes.append(.init(id: UUID().uuidString.lowercased(), nom: enseigne, lieux: choisis))
        }
        store.setMesLieux(lieux)
        dismiss()
    }
}
