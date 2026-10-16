import MapKit
import Testing
@testable import Relance

/// Groupes de la carte en points réels (correctif du 16/10 : le « 3 » du dentiste sur l'iPad).
@MainActor
struct MapClusterTests {
    // Géocodages réels : le dentiste et le 119 rue Paul Vaillant-Couturier, à environ 80 m.
    let dentist = CLLocationCoordinate2D(latitude: 48.8085236, longitude: 2.4188421)
    let home = CLLocationCoordinate2D(latitude: 48.8086394, longitude: 2.4177895)

    @Test func zoomSeparatesNearbyPlacesOnIPad() throws {
        let ipad = CGSize(width: 1100, height: 1000), current = MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.012)
        let span = try #require(TaskMapView.separatingSpan([dentist, home], current: current, size: ipad))
        // On zoome (plus petite échelle), et l'écart dépasse une étiquette et demie en largeur.
        #expect(span.longitudeDelta < current.longitudeDelta)
        let sepX = (dentist.longitude - home.longitude) / span.longitudeDelta * ipad.width
        #expect(sepX >= TaskMapView.labelSize.width * 1.5 - 0.001)
    }

    @Test func samePointGivesTheList() {
        let current = MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.012)
        // Même immeuble : aucun zoom ne sépare, on montre la liste.
        #expect(TaskMapView.separatingSpan([home, home], current: current, size: CGSize(width: 400, height: 800)) == nil)
        let twoMetres = CLLocationCoordinate2D(latitude: home.latitude + 0.00002, longitude: home.longitude)
        #expect(TaskMapView.separatingSpan([home, twoMetres], current: current, size: CGSize(width: 400, height: 800)) == nil)
    }
}
