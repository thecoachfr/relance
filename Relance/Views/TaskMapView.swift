import MapKit
import SwiftData
import SwiftUI

/// Carte des tâches à faire qui ont un lieu (ligne 📍) : une épingle par tâche, couleur et symbole
/// de sa catégorie, rouge si elle est urgente.
struct TaskMapView: View {
    @Environment(TaskStore.self) private var store
    @Query(filter: #Predicate<TaskItem> { !$0.isCompleted && !$0.isTrashed })
    private var active: [TaskItem]
    /// Tâche choisie : carte en bas (iPhone, iPad) ou colonne de détail (Mac).
    @Binding var selection: UUID?
    /// Mac : le détail s'affiche à côté, pas de carte de résumé sur la carte.
    var showsSummary = true
    @State private var position: MapCameraPosition = .automatic
    @State private var editing: TaskItem?
    /// Zone affichée : sert à regrouper les épingles trop proches à cette échelle.
    @State private var region: MKCoordinateRegion?
    /// Tâches au même endroit : on les liste (aucun zoom ne les sépare).
    @State private var sameSpot: [UUID]?

    private var locator: PlaceLocator { .shared }

    private var placed: [(item: TaskItem, contact: TaskContact, coordinate: CLLocationCoordinate2D)] {
        active.compactMap { item in
            guard let contact = TaskContact(notes: item.notes), let address = contact.address,
                  let coordinate = locator.coordinates[address] else { return nil }
            return (item, contact, coordinate)
        }
    }

    private var addresses: [String] {
        active.compactMap { TaskContact(notes: $0.notes)?.address }
    }

    /// Le lieu commun quand toutes les tâches du groupe sont au même endroit (à 30 m près).
    static func samePlace(_ group: [Entry]) -> TaskContact? {
        let first = group[0].coordinate
        let close = group.allSatisfy { abs($0.coordinate.latitude - first.latitude) < 0.0003
            && abs($0.coordinate.longitude - first.longitude) < 0.0003 }
        return close ? group[0].contact : nil
    }

    private func zoom(on group: [Entry]) {
        let lats = group.map(\.coordinate.latitude), lons = group.map(\.coordinate.longitude)
        let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2, longitude: (lons.min()! + lons.max()!) / 2)
        // Assez près pour que les étiquettes ne se chevauchent plus (un seul toucher).
        // Échelle à laquelle l'écart dépasse la taille d'une étiquette sur l'un des deux axes, avec de la marge.
        let side = max((lats.max()! - lats.min()!) / Self.labelHeight, (lons.max()! - lons.min()!) / Self.labelWidth) / 1.5
        let span = MKCoordinateSpan(latitudeDelta: max(side, 0.0015), longitudeDelta: max(side, 0.0015))
        withAnimation { position = .region(MKCoordinateRegion(center: center, span: span)) }
    }

    /// « Demain à 9 h 30 », « En retard · depuis 2 j », « Jusqu'au 31 janv. » ; rien sans échéance.
    static func caption(_ item: TaskItem, now: Date = .now) -> String? {
        if let toSee = item.toSee, item.dueDay == nil {
            return toSee.start == nil && toSee.end == nil ? nil : toSee.text(now: now)
        }
        return item.dueInstant().map { DueText.long(due: $0, hasTime: item.dueMinutes != nil, now: now) }
    }

    typealias Entry = (item: TaskItem, contact: TaskContact, coordinate: CLLocationCoordinate2D)

    /// Part de l'écran occupée par une épingle et son étiquette (environ 120 × 60 pt sur 400 × 800).
    private static let labelWidth = 0.3, labelHeight = 0.08

    /// Épingles dont les étiquettes se chevaucheraient à l'échelle affichée, regroupées en une seule.
    private func clusters(_ entries: [Entry]) -> [[Entry]] {
        guard let region else { return entries.map { [$0] } }
        let dLon = region.span.longitudeDelta * Self.labelWidth, dLat = region.span.latitudeDelta * Self.labelHeight
        var groups: [[Entry]] = []
        for entry in entries.sorted(by: { $0.item.priority.rank < $1.item.priority.rank }) {
            if let i = groups.firstIndex(where: { group in
                abs(group[0].coordinate.latitude - entry.coordinate.latitude) < dLat
                    && abs(group[0].coordinate.longitude - entry.coordinate.longitude) < dLon
            }) {
                groups[i].append(entry)
            } else {
                groups.append([entry])
            }
        }
        return groups
    }

    var body: some View {
        Map(position: $position, selection: $selection) {
            ForEach(clusters(placed), id: \.first!.item.localID) { group in
                let entry = group[0]
                let category = TaskCategory(name: entry.item.category)
                let color: Color = entry.item.priority == .urgent ? .red : category?.color ?? .gray
                if group.count == 1 {
                    // Épingle dessinée : titre, puis l'échéance en plus petit (un Marker n'a qu'un style de texte).
                    Annotation(entry.item.title, coordinate: entry.coordinate, anchor: .top) {
                        MapTaskPin(title: entry.item.title, caption: Self.caption(entry.item),
                                   symbol: category?.symbol ?? "mappin", color: color,
                                   selected: selection == entry.item.localID)
                            .onTapGesture { selection = entry.item.localID }
                    }
                    .annotationTitles(.hidden)
                    .tag(entry.item.localID)
                } else {
                    // Groupe : le nombre, à la couleur de la plus urgente ; le toucher zoome dessus.
                    Annotation("\(group.count) tâches", coordinate: entry.coordinate, anchor: .top) {
                        MapClusterPin(count: group.count, color: color, place: Self.samePlace(group)?.name)
                            .onTapGesture {
                                if Self.samePlace(group) != nil { sameSpot = group.map(\.item.localID) } else { zoom(on: group) }
                            }
                    }
                    .annotationTitles(.hidden)
                }
            }
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            region = context.region
            // Cadrage automatique une seule fois : sinon il se refait à chaque regroupement, qui change
            // l'échelle, donc les groupes… (boucle sans fin, écran figé).
            if position == .automatic { position = .region(context.region) }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .overlay {
            if addresses.isEmpty {
                ContentUnavailableView("Aucune tâche avec un lieu", systemImage: "map",
                                       description: Text("Ajoute un lieu à une tâche (section Lieu du détail) pour la voir ici."))
                    .background(.regularMaterial)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if showsSummary, let id = selection, let entry = placed.first(where: { $0.item.localID == id }) {
                MapTaskCard(item: entry.item, contact: entry.contact, onOpen: { editing = entry.item }) {
                    selection = nil
                }
                .padding()
            }
        }
        .sheet(isPresented: Binding(get: { sameSpot != nil }, set: { if !$0 { sameSpot = nil } })) {
            let items = (sameSpot ?? []).compactMap { id in placed.first { $0.item.localID == id } }
            NavigationStack {
                List(items, id: \.item.localID) { entry in
                    Button {
                        sameSpot = nil
                        selection = entry.item.localID
                    } label: {
                        TaskRow(item: entry.item).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .navigationTitle(items.first?.contact.name ?? "Au même endroit")
                .inlineNavigationTitle()
            }
            .presentationDetents([.medium, .large])
            #if os(macOS)
            .frame(width: 420, height: 360)
            #endif
        }
        .navigationTitle("Carte")
        // iPhone, iPad : l'onglet porte déjà le nom ; un grand titre flottait sur le plan sans fond.
        .hiddenNavigationBar()
        .task(id: addresses) { await locator.locate(addresses) }
        .sheet(item: $editing) { TaskEditor(item: $0) }
    }
}

/// Rond coloré au symbole de la catégorie, titre en petit gras, échéance en plus petit dessous.
private struct MapTaskPin: View {
    let title: String
    let caption: String?
    let symbol: String
    let color: Color
    let selected: Bool

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: selected ? 17 : 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: selected ? 38 : 28, height: selected ? 38 : 28)
                .background(color, in: .circle)
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .shadow(radius: 2, y: 1)
            // Comme les noms de rues de Plans : un liseré autour des lettres plutôt qu'un fond.
            VStack(spacing: 0) {
                Text(title).font(.caption2.weight(.semibold)).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let caption {
                    Text(caption).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 120)
            .mapLabelHalo()
        }
        .animation(.snappy, value: selected)
        .accessibilityElement(children: .combine)
    }
}

/// Plusieurs tâches au même endroit à cette échelle.
private struct MapClusterPin: View {
    let count: Int
    let color: Color
    /// Nom du lieu quand toutes les tâches y sont.
    var place: String?

    var body: some View {
        VStack(spacing: 3) {
            Text("\(count)")
                .font(.system(size: 14, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(color, in: .circle)
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .shadow(radius: 2, y: 1)
            if let place {
                Text(place)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 120)
                    .mapLabelHalo()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(place.map { "\(count) tâches à \($0)" } ?? "\(count) tâches ici, toucher pour zoomer")
    }
}

/// Liseré de la couleur du fond de carte autour du texte, pour le lire sur n'importe quelle rue.
private struct MapLabelHalo: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let halo: Color = scheme == .dark ? .black : .white
        content
            .shadow(color: halo, radius: 0, x: 1, y: 0)
            .shadow(color: halo, radius: 0, x: -1, y: 0)
            .shadow(color: halo, radius: 0, x: 0, y: 1)
            .shadow(color: halo, radius: 0, x: 0, y: -1)
            .shadow(color: halo.opacity(0.8), radius: 2)
    }
}

private extension View {
    func mapLabelHalo() -> some View { modifier(MapLabelHalo()) }
}

/// Résumé de la tâche choisie sur la carte : échéance, Fait, Itinéraire, Détails.
private struct MapTaskCard: View {
    @Environment(TaskStore.self) private var store
    @Environment(\.openURL) private var openURL
    let item: TaskItem
    let contact: TaskContact
    let onOpen: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TaskRow(item: item)
            Text([contact.name, contact.address].compactMap { $0 }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
                .joined(separator: " · "))
                .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            HStack {
                Button("Fait", systemImage: "checkmark") {
                    withAnimation { store.complete(item) }
                    onDone()
                }
                .tint(.green)
                if let url = contact.address.flatMap({ TravelTimes.mapsURL(to: $0, settings: store.scheduler.settings.departure) }) {
                    Button("Itinéraire", systemImage: "map") { openURL(url) }
                }
                Button("Détails", systemImage: "info.circle", action: onOpen)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding()
        .frame(maxWidth: 520, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
    }
}
