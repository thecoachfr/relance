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

    var body: some View {
        Map(position: $position, selection: $selection) {
            ForEach(placed, id: \.item.localID) { entry in
                let category = TaskCategory(name: entry.item.category)
                Marker(entry.item.title, systemImage: category?.symbol ?? "mappin",
                       coordinate: entry.coordinate)
                    .tint(entry.item.priority == .urgent ? .red : category?.color ?? .gray)
                    .tag(entry.item.localID)
            }
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
        .navigationTitle("Carte")
        // iPhone, iPad : l'onglet porte déjà le nom ; un grand titre flottait sur le plan sans fond.
        .hiddenNavigationBar()
        .task(id: addresses) { await locator.locate(addresses) }
        .sheet(item: $editing) { TaskEditor(item: $0) }
    }
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
