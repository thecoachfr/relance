import MapKit
import SwiftData
import SwiftUI

/// Carte des tâches à faire qui ont un lieu (ligne 📍) : une épingle ronde par tâche, couleur et symbole
/// de sa catégorie, rouge si elle est urgente ; une épingle carrée, couleur et symbole de son type, pour
/// une envie (À voir, resto, magasin, spot photo). Filtre en pastilles quand il y a plusieurs sortes de lieux.
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
    /// Taille de la carte en points : les groupes se calculent en points réels (iPhone, iPad, Mac).
    @State private var mapSize = CGSize(width: 400, height: 800)
    /// Tâches au même endroit : on les liste (aucun zoom ne les sépare).
    @State private var sameSpot: [UUID]?
    @State private var adding = false
    /// Filtre : vide = tout, « taches » = les tâches qui ne sont pas des envies, sinon un type d'envie.
    @AppStorage("mapFilter") private var filterRaw = ""

    private var locator: PlaceLocator { .shared }

    private static let tasksFilter = "taches"

    /// Type d'envie montré sur la carte avec son épingle propre (`nil` = tâche ordinaire).
    static func placeKind(_ item: TaskItem) -> ToSee.Kind? {
        item.toSee.map(\.kind).flatMap { $0.isPlace ? $0 : nil }
    }

    /// Pastilles : Tout, Tâches, puis les types d'envie présents ; rien s'il n'y a qu'une sorte de lieu.
    private var filterOptions: [FilterChips.Option] {
        let kinds = Set(allPlaced.map { Self.placeKind($0.item) })
        guard kinds.count > 1 else { return [] }
        var options = [FilterChips.Option(id: "", title: "Tout", symbol: nil)]
        if kinds.contains(nil) { options.append(.init(id: Self.tasksFilter, title: "Tâches", symbol: "checklist")) }
        for kind in ToSee.Kind.allCases where kinds.contains(kind) {
            options.append(.init(id: kind.rawValue, title: kind == .outing ? "À voir" : kind.shortTitle, symbol: kind.symbol))
        }
        return options
    }

    private var placed: [Entry] {
        // Un filtre qui ne correspond plus à rien (dernier resto testé) ne doit pas vider la carte.
        guard !filterRaw.isEmpty, filterOptions.contains(where: { $0.id == filterRaw }) else { return allPlaced }
        return allPlaced.filter { entry in
            let kind = Self.placeKind(entry.item)
            return filterRaw == Self.tasksFilter ? kind == nil : kind?.rawValue == filterRaw
        }
    }

    private var allPlaced: [Entry] {
        active.compactMap { item in
            guard let contact = TaskContact(notes: item.notes), let coordinate = locator.coordinate(for: item)
            else { return nil }
            return (item, contact, coordinate)
        }
    }

    /// Adresses à faire chercher par Plans (les lieux qui ont déjà leurs coordonnées n'en ont pas besoin).
    private var addresses: [String] { PlaceLocator.addresses(of: active) }

    private var hasPlaces: Bool { active.contains { TaskContact(notes: $0.notes) != nil } }

    /// Le lieu commun quand toutes les tâches du groupe sont au même endroit (à 30 m près).
    static func samePlace(_ group: [Entry]) -> TaskContact? {
        let first = group[0].coordinate
        let close = group.allSatisfy { abs($0.coordinate.latitude - first.latitude) < 0.0003
            && abs($0.coordinate.longitude - first.longitude) < 0.0003 }
        return close ? group[0].contact : nil
    }

    /// Toucher un groupe : zoomer juste assez pour séparer ses épingles ; si aucun zoom raisonnable ne les
    /// sépare (même immeuble), la liste de ses tâches.
    private func open(_ group: [Entry]) {
        guard Self.samePlace(group) == nil, let region,
              let span = Self.separatingSpan(group.map(\.coordinate), current: region.span, size: mapSize) else {
            sameSpot = group.map(\.item.localID)
            return
        }
        let lats = group.map(\.coordinate.latitude), lons = group.map(\.coordinate.longitude)
        let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2, longitude: (lons.min()! + lons.max()!) / 2)
        withAnimation { position = .region(MKCoordinateRegion(center: center, span: span)) }
    }

    /// Échelle où les épingles du groupe ne se chevauchent plus, en points réels de la carte (l'iPad est plus
    /// large que l'iPhone : en proportion de l'écran, des lieux à 80 m restaient groupés, 16/10). `nil` si
    /// elle passe sous `minSpan` (environ 60 m de haut) : mieux vaut alors la liste.
    static func separatingSpan(_ points: [CLLocationCoordinate2D], current: MKCoordinateSpan, size: CGSize,
                               minSpan: Double = 0.0006) -> MKCoordinateSpan? {
        let lats = points.map(\.latitude), lons = points.map(\.longitude)
        let dLat = lats.max()! - lats.min()!, dLon = lons.max()! - lons.min()!
        // Écart actuel en points ; on réduit l'échelle pour qu'il dépasse une étiquette et demie sur l'axe
        // le plus favorable (le moins de zoom possible).
        let sepX = dLon / current.longitudeDelta * size.width, sepY = dLat / current.latitudeDelta * size.height
        let factor = max(sepX / (labelSize.width * 1.5), sepY / (labelSize.height * 1.5))
        guard factor > 0 else { return nil }
        let span = MKCoordinateSpan(latitudeDelta: current.latitudeDelta * factor, longitudeDelta: current.longitudeDelta * factor)
        return span.latitudeDelta < minSpan ? nil : span
    }

    /// « Demain à 9 h 30 », « En retard · depuis 2 j », « Jusqu'au 31 janv. » ; rien sans échéance.
    static func caption(_ item: TaskItem, now: Date = .now) -> String? {
        if let toSee = item.toSee, item.dueDay == nil {
            return toSee.start == nil && toSee.end == nil ? nil : toSee.text(now: now)
        }
        return item.dueInstant().map { DueText.long(due: $0, hasTime: item.dueMinutes != nil, now: now) }
    }

    typealias Entry = (item: TaskItem, contact: TaskContact, coordinate: CLLocationCoordinate2D)

    /// Place d'une épingle et de son étiquette, en points.
    static let labelSize = CGSize(width: 120, height: 64)

    /// Épingles dont les étiquettes se chevaucheraient à l'échelle affichée, regroupées en une seule.
    private func clusters(_ entries: [Entry]) -> [[Entry]] {
        guard let region, mapSize.width > 0, mapSize.height > 0 else { return entries.map { [$0] } }
        let dLon = region.span.longitudeDelta * Self.labelSize.width / mapSize.width
        let dLat = region.span.latitudeDelta * Self.labelSize.height / mapSize.height
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
                let kind = Self.placeKind(entry.item)
                let color: Color = entry.item.priority == .urgent ? .red : kind?.mapColor ?? category?.color ?? .gray
                if group.count == 1 {
                    // Épingle dessinée : titre, puis l'échéance en plus petit (un Marker n'a qu'un style de texte).
                    Annotation(entry.item.title, coordinate: entry.coordinate, anchor: .top) {
                        MapTaskPin(title: entry.item.title, caption: Self.caption(entry.item),
                                   symbol: kind?.symbol ?? category?.symbol ?? "mappin", color: color,
                                   isEnvie: kind != nil, selected: selection == entry.item.localID)
                            .onTapGesture { selection = entry.item.localID }
                    }
                    .annotationTitles(.hidden)
                    .tag(entry.item.localID)
                } else {
                    // Groupe : le nombre, à la couleur de la plus urgente ; le toucher zoome dessus.
                    Annotation("\(group.count) tâches", coordinate: entry.coordinate, anchor: .top) {
                        MapClusterPin(count: group.count, color: color, place: Self.samePlace(group)?.name)
                            .onTapGesture {
                                open(group)
                            }
                    }
                    .annotationTitles(.hidden)
                }
            }
        }
        .onGeometryChange(for: CGSize.self, of: \.size) { mapSize = $0 }
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
            if !hasPlaces {
                ContentUnavailableView("Aucune tâche avec un lieu", systemImage: "map",
                                       description: Text("Ajoute un lieu à une tâche (section Lieu du détail) pour la voir ici."))
                    .background(.regularMaterial)
            }
        }
        .safeAreaInset(edge: .top) {
            if !filterOptions.isEmpty {
                FilterChips(selection: $filterRaw, options: filterOptions, overMap: true)
                    .contentMargins(.horizontal, 16, for: .scrollContent)
                    #if os(iOS)
                    // Place laissée au « + » flottant.
                    .padding(.trailing, 64)
                    #endif
                    .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
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
                .navigationTitle(Self.samePlace(items)?.name ?? "\(items.count) tâches proches")
                .inlineNavigationTitle()
            }
            .presentationDetents([.medium, .large])
            #if os(macOS)
            .frame(width: 420, height: 360)
            #endif
        }
        #if os(iOS)
        // La barre de navigation est masquée sur la carte : « + » flottant, au même endroit qu'ailleurs.
        .overlay(alignment: .topTrailing) {
            Button("Nouvelle tâche", systemImage: "plus") { adding = true }
                .labelStyle(.iconOnly)
                .font(.title3.weight(.semibold))
                .frame(width: 48, height: 48)
                .foregroundStyle(.white)
                .background(Color.accentColor, in: .circle)
                .shadow(radius: 3, y: 1)
                .padding(.trailing, 16)
                .padding(.top, 8)
        }
        .sheet(isPresented: $adding) { QuickAddSheet(context: .map) }
        #endif
        .navigationTitle("Carte")
        // iPhone, iPad : l'onglet porte déjà le nom ; un grand titre flottait sur le plan sans fond.
        .hiddenNavigationBar()
        .task(id: addresses) { await locator.locate(addresses) }
        .sheet(item: $editing) { TaskEditor(item: $0) }
    }
}

/// Couleurs des envies sur la carte, distinctes de celles des catégories (bleu, brun, rose, orange,
/// indigo, vert, violet) autant que possible ; la forme carrée et le symbole les distinguent aussi.
extension ToSee.Kind {
    var mapColor: Color {
        switch self {
        case .outing: .purple
        case .restaurant: .orange
        case .shop: .teal
        case .photoSpot: .indigo
        case .read, .listen, .watch: .gray
        }
    }
}

/// Rond coloré au symbole de la catégorie (carré arrondi pour une envie), titre en petit gras,
/// échéance en plus petit dessous.
private struct MapTaskPin: View {
    let title: String
    let caption: String?
    let symbol: String
    let color: Color
    var isEnvie = false
    let selected: Bool

    var body: some View {
        let size: CGFloat = selected ? 38 : 28
        let shape = RoundedRectangle(cornerRadius: isEnvie ? size * 0.28 : size / 2, style: .continuous)
        VStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: selected ? 17 : 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(color, in: shape)
                .overlay(shape.stroke(.white, lineWidth: 2))
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
                if let url = contact.destination.flatMap({ TravelTimes.mapsURL(to: $0, settings: store.scheduler.settings.departure) }) {
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
