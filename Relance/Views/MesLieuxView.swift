import CoreLocation
import SwiftUI

/// Réglages › Mes lieux (P9-H2) : mes lieux habituels rangés en groupes. Une tâche rattachée à un groupe (« Me le
/// rappeler près de… », ou automatiquement une liste d'achats pour Supermarchés) me prévient près de l'un d'eux.
struct MesLieuxView: View {
    @Environment(TaskStore.self) private var store
    @State private var ajoutDans: String?
    @State private var choixDomicile = false
    @State private var nouveauGroupe = false
    @State private var nomDuGroupe = ""
    @State private var renommage: String?
    @State private var edition: Edition?
    @State private var erreur: String?

    var body: some View {
        Form {
            Section {
                if let maison = store.mesLieux.domicile {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(maison.nom)
                            if let adresse = maison.adresse { Text(adresse).font(.subheadline).foregroundStyle(.secondary) }
                        }
                    } icon: { Image(systemName: "house.fill") }
                    .swipeActions { Button("Retirer", role: .destructive) { changerDomicile(nil) } }
                    Button("Changer", systemImage: "arrow.triangle.2.circlepath") { choixDomicile = true }
                } else {
                    Button("Définir mon domicile", systemImage: "house") { choixDomicile = true }
                }
            } header: {
                Text("Domicile")
            } footer: {
                Text("Proposé en tête de la recherche de lieu d'une tâche (« Maison »). Pour un rappel en rentrant, préfère « Me le rappeler à la maison », détecté par Home Assistant.")
            }
            ForEach(store.mesLieux.groupes) { groupe in
                Section {
                    ForEach(groupe.lieux) { lieu in
                        Button { edition = Edition(groupe: groupe, lieu: lieu) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(lieu.nom)
                                if let adresse = lieu.adresse, adresse != lieu.nom {
                                    Text(adresse).font(.subheadline).foregroundStyle(.secondary)
                                }
                                Text(Self.horaires(de: lieu)).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .tint(.primary)
                        .accessibilityElement(children: .combine)
                    }
                    .onDelete { offsets in modifier(groupe.id) { $0.lieux.remove(atOffsets: offsets) } }
                    Button("Ajouter un lieu", systemImage: "plus.circle") { ajoutDans = groupe.id }
                    // Domicile et Travail sont reconnus par leur nom (`groupesMagasins`, lieu de travail).
                    if store.mesLieux.groupesMagasins.contains(where: { $0.id == groupe.id }) {
                        Button("Renommer le groupe", systemImage: "pencil") {
                            nomDuGroupe = groupe.nom
                            renommage = groupe.id
                        }
                    }
                } header: {
                    Text(groupe.nom)
                } footer: {
                    if groupe.id == MesLieux.supermarches {
                        Text("Un article à prendre te prévient à 150 m de l'un de ces lieux, une fois par jour et seulement pendant ses horaires d'ouverture. Touche un lieu pour le renommer ou saisir ses horaires.")
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
        .sheet(isPresented: $choixDomicile) {
            PlaceSearchView { contact in
                Task {
                    guard let point = await Self.position(contact) else {
                        erreur = "Pas de position pour « \(contact.name) » : choisis-le sur la carte."
                        return
                    }
                    changerDomicile(.init(nom: "Maison", adresse: contact.address ?? contact.name,
                                          lat: point.latitude, lon: point.longitude))
                }
            }
        }
        .sheet(item: $edition) { edition in
            LieuEditionView(lieu: edition.lieu, autres: edition.groupe.lieux.count - 1) { lieu, partout in
                enregistrer(lieu, dans: edition.groupe.id, partout: partout)
            }
        }
        .alert("Renommer le groupe", isPresented: Binding(get: { renommage != nil }, set: { if !$0 { renommage = nil } })) {
            TextField("Nom", text: $nomDuGroupe)
            Button("Renommer") { renommer() }
            Button("Annuler", role: .cancel) { nomDuGroupe = "" }
        } message: {
            Text("Les articles et les tâches rattachés à ce groupe le gardent.")
        }
        .alert("Nouveau groupe", isPresented: $nouveauGroupe) {
            TextField("Pharmacies", text: $nomDuGroupe)
            Button("Créer") { creerGroupe() }
            Button("Annuler", role: .cancel) { nomDuGroupe = "" }
        }
        .onAppear(perform: ProximityReminders.shared.requestAuthorization)
    }

    private struct Identite: Identifiable { let id: String }

    private struct Edition: Identifiable {
        let groupe: MesLieux.Groupe
        let lieu: MesLieux.Lieu
        var id: String { lieu.id }
    }

    private static func horaires(de lieu: MesLieux.Lieu) -> String {
        guard let horaires = lieu.horaires else { return "Horaires non renseignés" }
        return "Aujourd'hui : " + horaires.texte(jour: MesLieux.Horaires.jour(de: .now))
    }

    private func modifier(_ groupe: String, _ change: (inout MesLieux.Groupe) -> Void) {
        var lieux = store.mesLieux
        guard let i = lieux.groupes.firstIndex(where: { $0.id == groupe }) else { return }
        change(&lieux.groupes[i])
        store.setMesLieux(lieux)
    }

    private func changerDomicile(_ lieu: MesLieux.Lieu?) {
        var lieux = store.mesLieux
        lieux.domicile = lieu
        store.setMesLieux(lieux)
    }

    /// Coordonnées du lieu choisi : lien Plans du point, sinon l'adresse cherchée par Plans.
    static func position(_ contact: TaskContact) async -> (latitude: Double, longitude: Double)? {
        if let point = contact.coordinate { return point }
        guard let adresse = contact.address,
              let place = try? await CLGeocoder().geocodeAddressString(adresse).first?.location else { return nil }
        return (place.coordinate.latitude, place.coordinate.longitude)
    }

    private func creerGroupe() {
        let nom = nomDuGroupe.trimmingCharacters(in: .whitespaces)
        nomDuGroupe = ""
        guard !nom.isEmpty else { return }
        var lieux = store.mesLieux
        lieux.groupes.append(.init(id: UUID().uuidString.lowercased(), nom: nom))
        store.setMesLieux(lieux)
    }

    private func renommer() {
        let nom = nomDuGroupe.trimmingCharacters(in: .whitespaces)
        nomDuGroupe = ""
        guard !nom.isEmpty, let renommage else { return }
        modifier(renommage) { $0.nom = nom }
    }

    private func enregistrer(_ lieu: MesLieux.Lieu, dans groupe: String, partout: Bool) {
        modifier(groupe) { g in
            if let i = g.lieux.firstIndex(where: { $0.id == lieu.id }) { g.lieux[i] = lieu }
            if partout { for i in g.lieux.indices { g.lieux[i].horaires = lieu.horaires } }
        }
    }

    /// Le lieu choisi, avec ses coordonnées (lien Plans du point, sinon l'adresse cherchée par Plans).
    private func ajouter(_ contact: TaskContact, dans groupe: String) {
        Task {
            guard let point = await Self.position(contact) else {
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

/// Nom et horaires d'un lieu. Enregistrés d'un coup, pour ne pas écrire dans HA à chaque lettre.
private struct LieuEditionView: View {
    private typealias Horaires = MesLieux.Horaires
    private typealias Creneau = MesLieux.Horaires.Creneau
    private static let noms = ["Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi", "Dimanche"]

    let lieu: MesLieux.Lieu
    /// Autres lieux du groupe, auxquels on peut donner les mêmes horaires.
    let autres: Int
    let enregistrer: (MesLieux.Lieu, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var nom = ""
    @State private var connus = false
    @State private var horaires = Horaires.courants
    @State private var partout = false

    /// Minuit choisi en fin de créneau : la fin de la journée.
    private var saisis: Horaires {
        Horaires(jours: horaires.jours.map { $0.map { Creneau(debut: $0.debut, fin: $0.fin == 0 ? 1440 : $0.fin) } })
    }
    private var valides: Bool { saisis.jours.allSatisfy { $0.allSatisfy { $0.debut < $0.fin } } }
    private var nomSaisi: String { nom.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nom") { TextField("Nom du magasin", text: $nom) }
                Section {
                    Toggle("Horaires d'ouverture", isOn: $connus)
                } footer: {
                    Text(connus ? "Ce lieu ne te prévient que pendant ces horaires. Les jours fériés ne sont pas connus."
                                : "Sans horaires, ce lieu te prévient à toute heure.")
                }
                if connus {
                    ForEach(Self.noms.indices, id: \.self) { jour in
                        Section(Self.noms[jour]) { lignes(jour) }
                    }
                    if !valides { Text("Une heure de fin précède son heure de début.").font(.footnote).foregroundStyle(.red) }
                    if autres > 0 {
                        Toggle("Mêmes horaires pour les autres lieux du groupe (\(autres))", isOn: $partout)
                    }
                }
            }
            .navigationTitle(lieu.nom)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        var modifie = lieu
                        modifie.nom = nomSaisi
                        modifie.horaires = connus ? saisis : nil
                        enregistrer(modifie, connus && partout)
                        dismiss()
                    }
                    .disabled(nomSaisi.isEmpty || (connus && !valides))
                }
            }
            .onAppear {
                nom = lieu.nom
                connus = lieu.horaires != nil
                if let actuels = lieu.horaires { horaires = actuels }
            }
        }
    }

    @ViewBuilder private func lignes(_ jour: Int) -> some View {
        let creneaux = horaires.jours[jour]
        Toggle("Ouvert", isOn: Binding(get: { !horaires.jours[jour].isEmpty }, set: { ouvert in
            horaires.jours[jour] = ouvert ? [Creneau(debut: 9 * 60, fin: 20 * 60)] : []
        }))
        ForEach(creneaux.indices, id: \.self) { i in
            HStack {
                DatePicker("Ouverture", selection: heure(jour, i, \.debut), displayedComponents: .hourAndMinute)
                    .labelsHidden()
                Text("à")
                DatePicker("Fermeture", selection: heure(jour, i, \.fin), displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
        }
        if creneaux.count == 1 {
            Button("Ajouter une coupure", systemImage: "plus.circle") {
                horaires.jours[jour][0].fin = 12 * 60 + 30
                horaires.jours[jour].append(Creneau(debut: 14 * 60 + 30, fin: 19 * 60))
            }
        } else if creneaux.count > 1 {
            Button("Retirer la coupure", systemImage: "minus.circle") {
                horaires.jours[jour][0].fin = horaires.jours[jour][1].fin
                horaires.jours[jour].removeLast()
            }
        }
        if jour == 0 {
            Button("Copier sur tous les jours", systemImage: "doc.on.doc") {
                horaires.jours = Array(repeating: horaires.jours[0], count: 7)
            }
        }
    }

    private func heure(_ jour: Int, _ i: Int, _ champ: WritableKeyPath<Creneau, Int>) -> Binding<Date> {
        Binding(get: {
            guard horaires.jours[jour].indices.contains(i) else { return .now }
            let minutes = horaires.jours[jour][i][keyPath: champ]
            return Calendar.current.date(bySettingHour: minutes / 60 % 24, minute: minutes % 60, second: 0, of: .now) ?? .now
        }, set: { date in
            guard horaires.jours[jour].indices.contains(i) else { return }
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            horaires.jours[jour][i][keyPath: champ] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        })
    }
}
