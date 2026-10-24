import SwiftUI

/// Bandeau en tête de « À faire » (P9-N2, 24/10/2026) : la `phrase` de `sensor.aiguillage_lieu_travail`, telle quelle
/// (« 🏢 Bureau aujourd'hui · demain 🏠 Télétravail »). Caché en mode Google Tasks ou si le capteur manque.
/// Le toucher ouvre l'écran « Lieu de travail ».
struct LieuTravailBandeau: View {
    @Environment(TaskStore.self) private var store
    @State private var ouvert = false

    var body: some View {
        if store.isHAActive, let lieu = store.lieuTravail {
            Section {
                Button { ouvert = true } label: {
                    HStack(spacing: 8) {
                        Text(lieu.phrase)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Ouvre le réglage du lieu de travail")
            }
            .selectionDisabled()
            .sheet(isPresented: $ouvert) {
                NavigationStack {
                    LieuTravailView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) { Button("OK") { ouvert = false } }
                        }
                }
                #if os(macOS)
                .frame(minWidth: 480, minHeight: 600)
                #endif
            }
        }
    }
}

/// Réglages › Lieu de travail (P9-N2, « réglable facilement », demande d'Alexandre du 24/10) : les 14 prochains jours,
/// chacun changé d'un toucher (exception), puis la semaine type et le premier vendredi du mois. Tout s'écrit dans
/// `config:lieu_travail` ; l'affichage vient du capteur, recalculé par HA en quelques secondes.
struct LieuTravailView: View {
    @Environment(TaskStore.self) private var store
    /// Choix envoyés dont le capteur n'a pas encore tenu compte (date → lieu, `nil` = comme prévu).
    @State private var enAttente: [String: String?] = [:]

    private static let choix: [(lieu: String, nom: String)] =
        [("bureau", "🏢 Bureau"), ("lab", "🧪 Le Lab"), ("teletravail", "🏠 Télétravail"), ("off", "Pas Barrière")]

    var body: some View {
        Form {
            if !store.isHAActive {
                Section {
                    Text("Le lieu de travail est rangé dans Home Assistant : active d'abord Home Assistant dans les réglages.")
                        .foregroundStyle(.secondary)
                }
            } else {
                if let suggestion = store.lieuTravail?.suggestion {
                    Section { Label(suggestion, systemImage: "lightbulb") }
                }
                prochainsJours
                semaineType
            }
        }
        .navigationTitle("Lieu de travail")
        .inlineNavigationTitle()
        .task { await store.rafraichirLieuTravail(force: (store.lieuTravailLuLe.map { Date.now.timeIntervalSince($0) } ?? 999) > 60) }
        .refreshable { await store.rafraichirLieuTravail(force: true) }
        .onChange(of: store.lieuTravail) { enAttente = [:] }
    }

    // MARK: - Les 14 prochains jours

    @ViewBuilder
    private var prochainsJours: some View {
        Section {
            if let jours = store.lieuTravail?.jours, !jours.isEmpty {
                ForEach(Array(jours.enumerated()), id: \.element.id) { index, jour in
                    ligne(jour, index: index)
                }
            } else {
                Text("Lieu de travail indisponible pour l'instant (capteur de Home Assistant).")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Les 14 prochains jours")
        } footer: {
            Text("Touche un jour pour le changer. « Comme prévu » retire le changement. Aussi par Signal, « Note à moi-même » : « jeudi au Lab », « demain télétravail ».")
        }
    }

    private func ligne(_ jour: LieuTravail.Jour, index: Int) -> some View {
        let attendu = enAttente[jour.date]
        return Menu {
            ForEach(Self.choix, id: \.lieu) { choix in
                Button {
                    changer(jour, lieu: choix.lieu)
                } label: {
                    if choix.lieu == jour.lieu && jour.source == "exception" {
                        Label(choix.nom, systemImage: "checkmark")
                    } else {
                        Text(choix.nom)
                    }
                }
            }
            if jour.source == "exception" || store.configLieuTravail?.exceptions[jour.date] != nil {
                Divider()
                Button("Comme prévu", systemImage: "arrow.uturn.backward") { changer(jour, lieu: nil) }
            }
        } label: {
            HStack {
                Text(Self.quand(jour, index: index))
                    .foregroundStyle(.primary)
                Spacer()
                if attendu != nil {
                    ProgressView().controlSize(.small)
                    Text(attendu!.map(ConfigLieuTravail.libelle) ?? "Comme prévu").foregroundStyle(.secondary)
                } else {
                    Text(jour.libelle)
                        .foregroundStyle(jour.estTravaille ? .primary : .secondary)
                    if jour.source == "exception" {
                        Image(systemName: "pencil.circle").foregroundStyle(.secondary)
                            .accessibilityLabel("changé")
                    } else if jour.source == "position" {
                        Image(systemName: "location").foregroundStyle(.secondary)
                            .accessibilityLabel("constaté par la position")
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(Self.quand(jour, index: index)) : \(jour.libelle)")
        .accessibilityHint("Changer le lieu de ce jour")
    }

    private func changer(_ jour: LieuTravail.Jour, lieu: String?) {
        enAttente[jour.date] = .some(lieu)
        store.modifierLieuTravail(.exception(date: jour.date, lieu: lieu))
    }

    /// « Aujourd'hui », « Demain », puis « Mardi 27/10 ».
    static func quand(_ jour: LieuTravail.Jour, index: Int) -> String {
        if index == 0 { return "Aujourd'hui" }
        if index == 1 { return "Demain" }
        let parts = jour.date.split(separator: "-")
        let date = parts.count == 3 ? " \(parts[2])/\(parts[1])" : ""
        return jour.jour.prefix(1).uppercased() + jour.jour.dropFirst() + date
    }

    // MARK: - Semaine type

    @ViewBuilder
    private var semaineType: some View {
        let config = store.configLieuTravail ?? .parDefaut
        Section {
            ForEach(ConfigLieuTravail.jours, id: \.self) { nom in
                regle(nom.prefix(1).uppercased() + nom.dropFirst(), config.semaine[nom]) { store.modifierLieuTravail(.semaine(jour: nom, $0)) }
            }
        } header: {
            Text("Semaine type")
        } footer: {
            Text("« Probable » : le jour s'affiche « 🏢 Bureau ? ». La position de l'iPhone l'emporte sur le prévu.")
        }
        Section {
            Picker("Premier vendredi", selection: Binding<String>(
                get: { config.premierVendredi?.lieu ?? "" },
                set: { lieu in
                    store.modifierLieuTravail(.premierVendredi(lieu.isEmpty ? nil : ConfigLieuTravail.Regle(
                        lieu: lieu, probable: config.premierVendredi?.probable ?? false)))
                })) {
                Text("Comme la semaine type").tag("")
                ForEach(Self.choix, id: \.lieu) { Text($0.nom).tag($0.lieu) }
            }
            if let pv = config.premierVendredi, LieuTravail.travailles.contains(pv.lieu) {
                Toggle("Probable", isOn: Binding(get: { pv.probable }, set: {
                    store.modifierLieuTravail(.premierVendredi(ConfigLieuTravail.Regle(lieu: pv.lieu, probable: $0)))
                }))
            }
        } header: {
            Text("Premier vendredi du mois")
        }
    }

    @ViewBuilder
    private func regle(_ titre: String, _ regle: ConfigLieuTravail.Regle?,
                       ecrire: @escaping (ConfigLieuTravail.Regle) -> Void) -> some View {
        let actuelle = regle ?? ConfigLieuTravail.Regle(lieu: "off", probable: false)
        Picker(titre, selection: Binding(get: { actuelle.lieu }, set: {
            ecrire(ConfigLieuTravail.Regle(lieu: $0, probable: LieuTravail.travailles.contains($0) && actuelle.probable))
        })) {
            ForEach(Self.choix, id: \.lieu) { Text($0.nom).tag($0.lieu) }
        }
        if LieuTravail.travailles.contains(actuelle.lieu) {
            Toggle(isOn: Binding(get: { actuelle.probable }, set: {
                ecrire(ConfigLieuTravail.Regle(lieu: actuelle.lieu, probable: $0))
            })) {
                Text("Probable").foregroundStyle(.secondary)
            }
            .padding(.leading, 16)
            .accessibilityLabel("\(titre) probable")
        }
    }
}
