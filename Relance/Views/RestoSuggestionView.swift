import MapKit
import SwiftData
import SwiftUI

/// « Un resto près de… » (P9-S4) : autour de ma position ou d'un lieu choisi, mes restos favoris puis à tester
/// (les plus proches d'abord), puis les restaurants, cafés et bars de Plans autour, à garder en un geste.
/// Ouvert depuis Envies (filtre Restos ou Favoris), la carte, Siri et le lien `relance://resto`.
struct RestoSuggestionView: View {
    @Environment(TaskStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Query(filter: #Predicate<TaskItem> { !$0.isCompleted && !$0.isTrashed })
    private var active: [TaskItem]

    struct Origin: Equatable {
        var name: String
        var latitude: Double
        var longitude: Double
        var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    }

    @State private var origin: Origin?
    @State private var locating = false
    @State private var message: String?
    @State private var choosingPlace = false
    @State private var around: [MKMapItem] = []
    @State private var loadingAround = false
    @State private var editing: TaskItem?
    /// Lieux de Plans gardés depuis cet écran (ils passent dans « Mes restos » à la synchro suivante de la liste).
    @State private var kept: Set<String> = []

    private var mine: [RestoSuggestions.Place] {
        active.compactMap { item in
            guard let kind = item.toSee?.kind, kind.isRestaurant,
                  let c = PlaceLocator.shared.coordinate(for: item) else { return nil }
            return .init(id: item.localID, kind: kind, latitude: c.latitude, longitude: c.longitude)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    #if os(iOS)
                    Button { Task { await locate() } } label: {
                        HStack {
                            Label("Ma position", systemImage: "location.fill")
                            Spacer()
                            if locating { ProgressView().controlSize(.small) }
                        }
                    }
                    .disabled(locating)
                    #endif
                    Button { choosingPlace = true } label: { Label("Près d'un autre lieu…", systemImage: "mappin.and.ellipse") }
                } header: {
                    Text(origin.map { "Près de : \($0.name)" } ?? "Près de…")
                } footer: {
                    if let message { Text(message) }
                }
                if let origin { results(origin) }
            }
            .navigationTitle("Un resto près de…")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } }
            }
            .task {
                guard origin == nil else { return }
                #if os(iOS)
                await locate()
                #else
                if let maison = MesLieux.cached().domicile {
                    origin = Origin(name: maison.nom, latitude: maison.lat, longitude: maison.lon)
                }
                #endif
            }
            .task(id: origin) { await loadAround() }
            .sheet(isPresented: $choosingPlace) {
                PlaceSearchView { contact in Task { await useContact(contact) } }
            }
            .sheet(item: $editing) { TaskEditor(item: $0) }
        }
        #if os(macOS)
        .frame(width: 460, height: 560)
        #endif
    }

    @ViewBuilder private func results(_ origin: Origin) -> some View {
        let found = RestoSuggestions.nearest(mine, from: origin.coordinate)
        let items = found.hits.compactMap { hit in active.first { $0.localID == hit.id }.map { ($0, hit) } }
        Section {
            ForEach(items, id: \.0.localID) { item, hit in mineRow(item, hit) }
        } header: {
            Text("Mes restos à moins de \(RestoSuggestions.distanceText(found.radius))")
        } footer: {
            if items.isEmpty { Text("Aucun de tes restos à tester ou favoris par ici.") }
        }
        Section {
            if loadingAround && around.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            }
            ForEach(around, id: \.self) { aroundRow($0, origin: origin) }
        } header: {
            Text("Autour, d'après Plans")
        } footer: {
            if !loadingAround && around.isEmpty { Text("Plans ne propose rien ici.") }
        }
    }

    private func mineRow(_ item: TaskItem, _ hit: RestoSuggestions.Hit) -> some View {
        let contact = TaskContact(notes: item.notes)
        let sorte = item.toSee?.note
        return HStack(spacing: 12) {
            Image(systemName: hit.kind.symbol)
                .foregroundStyle(hit.kind.mapColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).foregroundStyle(.primary)
                Text([hit.kind == .favorite ? "Favori" : "À tester", sorte, RestoSuggestions.distanceText(hit.distance)]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if let url = contact?.mapsURL {
                Button("Itinéraire", systemImage: "arrow.triangle.turn.up.right.circle") { openURL(url) }
                    .labelStyle(.iconOnly).font(.title3).buttonStyle(.borderless)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { editing = item }
        .accessibilityAction(named: "Ouvrir la fiche") { editing = item }
    }

    private func aroundRow(_ item: MKMapItem, origin: Origin) -> some View {
        let name = item.name ?? "Sans nom"
        let label = SharedPlace.envie(forCategory: item.pointOfInterestCategory?.rawValue)?.label
        let c = Self.coordinate(of: item)
        let distance = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
            .distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
        return HStack(spacing: 12) {
            Image(systemName: "sparkle.magnifyingglass").foregroundStyle(Color.accentColor).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).foregroundStyle(.primary)
                Text([label, RestoSuggestions.distanceText(distance), PlaceSearchView.address(of: item)]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            if kept.contains(name) {
                Image(systemName: "checkmark").foregroundStyle(.secondary).accessibilityLabel("Gardé")
            } else {
                Menu {
                    Button("À tester", systemImage: ToSee.Kind.restaurant.symbol) { keep(item, as: .restaurant) }
                    Button("Favori", systemImage: ToSee.Kind.favorite.symbol) { keep(item, as: .favorite) }
                    Button("Itinéraire", systemImage: "map") { openURL(Self.contact(of: item).mapsURL ?? URL(string: "https://maps.apple.com")!) }
                } label: {
                    Text("Garder").fontWeight(.semibold)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }

    // MARK: - Actions

    #if os(iOS)
    /// Ma position, une fois (10 s au plus).
    private func locate() async {
        locating = true
        defer { locating = false }
        let manager = CLLocationManager()
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        let found = await withTaskGroup(of: CLLocation?.self) { group in
            group.addTask {
                do {
                    for try await update in CLLocationUpdate.liveUpdates() {
                        if let location = update.location { return location }
                    }
                } catch {}
                return nil
            }
            group.addTask { try? await Task.sleep(for: .seconds(10)); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        if let found {
            origin = Origin(name: "Ma position", latitude: found.coordinate.latitude, longitude: found.coordinate.longitude)
            message = nil
        } else {
            message = "Position introuvable. Autorise la localisation pour Aiguillage, ou choisis un lieu."
        }
    }
    #endif

    /// Lieu choisi : ses coordonnées (lien Plans, Mes lieux), sinon son adresse cherchée dans Plans.
    private func useContact(_ contact: TaskContact) async {
        if let c = contact.coordinate {
            origin = Origin(name: contact.name, latitude: c.latitude, longitude: c.longitude)
            return
        }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = contact.address ?? contact.name
        if let item = try? await MKLocalSearch(request: request).start().mapItems.first {
            let c = Self.coordinate(of: item)
            origin = Origin(name: contact.name, latitude: c.latitude, longitude: c.longitude)
        } else {
            message = "Lieu introuvable dans Plans."
        }
    }

    /// Restaurants, cafés, boulangeries et bars de Plans autour du point (2 km), sans ceux que j'ai déjà.
    private func loadAround() async {
        guard let origin else { return }
        loadingAround = true
        defer { loadingAround = false }
        let request = MKLocalPointsOfInterestRequest(center: origin.coordinate, radius: 2_000)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.restaurant, .cafe, .bakery, .nightlife, .brewery])
        let items = (try? await MKLocalSearch(request: request).start().mapItems) ?? []
        let mineNames = active.filter { $0.toSee?.kind.isRestaurant == true }.map(\.title)
        let here = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        around = items
            .filter { item in !mineNames.contains { RestoSuggestions.sameName($0, item.name ?? "") } }
            .sorted {
                let (a, b) = (Self.coordinate(of: $0), Self.coordinate(of: $1))
                return here.distance(from: CLLocation(latitude: a.latitude, longitude: a.longitude))
                    < here.distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
            }
            .prefix(20).map { $0 }
    }

    /// Un lieu de Plans devient une envie, avec son lieu (point exact) et sa sorte (« bar ») ; le tri le range.
    private func keep(_ item: MKMapItem, as kind: ToSee.Kind) {
        let contact = Self.contact(of: item)
        let label = SharedPlace.envie(forCategory: item.pointOfInterestCategory?.rawValue)?.label
        let notes = ToSee.notes(TaskContact.notes("", setting: contact), setting: ToSee(kind, note: label))
        store.add(title: contact.name, day: nil, minutes: nil, notes: notes)
        kept.insert(item.name ?? contact.name)
    }

    static func contact(of item: MKMapItem) -> TaskContact {
        let c = coordinate(of: item)
        let name = item.name ?? "Sans nom"
        return TaskContact(name: name, address: PlaceSearchView.address(of: item), phone: item.phoneNumber,
                           link: TaskContact.mapsLink(name: name, latitude: c.latitude, longitude: c.longitude))
    }

    static func coordinate(of item: MKMapItem) -> CLLocationCoordinate2D {
        if #available(iOS 26, macOS 26, *) { return item.location.coordinate }
        return item.placemark.coordinate
    }
}

extension View {
    /// Présente « Un resto près de… » demandé par Siri ou le lien `relance://resto` (`TaskStore.restoDemande`).
    func restoDemandeSheet(_ store: TaskStore) -> some View {
        sheet(isPresented: Binding(get: { store.restoDemande }, set: { store.restoDemande = $0 })) {
            RestoSuggestionView()
        }
    }
}
