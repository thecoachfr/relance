import Foundation
import Testing
@testable import Relance

/// Rappels à l'approche avec beaucoup de lieux (P9-A4).
struct ProximityPlannerTests {
    /// 40 lieux le long d'une ligne est-ouest dans Paris, environ 370 m entre deux (0,005° de longitude).
    let places: [ProximityPlanner.Candidate] = (0..<40).map {
        .init(id: "lieu-\($0)", latitude: 48.85, longitude: 2.25 + Double($0) * 0.005, urgent: false, due: nil)
    }

    @Test func closestTwentyFollowTheMove() {
        let west = ProximityPlanner.choose(places, near: (48.85, 2.25))
        #expect(west.count == 20 && Set(west) == Set((0..<20).map { "lieu-\($0)" }))
        // On se déplace à l'est : les zones suivent.
        let east = ProximityPlanner.choose(places, near: (48.85, 2.25 + 39 * 0.005))
        #expect(east.count == 20 && Set(east) == Set((20..<40).map { "lieu-\($0)" }))
        #expect(east.first == "lieu-39")
    }

    @Test func urgentTasksKeepTheirPlace() {
        var all = places
        let soon = Date(timeIntervalSince1970: 1_000), later = Date(timeIntervalSince1970: 2_000)
        for i in [35, 36, 37, 38, 39, 34] { all[i].urgent = true }
        all[39].due = soon
        all[34].due = later
        // Loin de moi, mais urgentes : 5 places au plus, la plus proche de l'échéance d'abord.
        let chosen = ProximityPlanner.choose(all, near: (48.85, 2.25))
        #expect(chosen.count == 20 && chosen.first == "lieu-39")
        #expect(chosen.prefix(5).allSatisfy { id in all.first { $0.id == id }!.urgent })
        #expect(chosen.dropFirst(5).first == "lieu-0")
        // Sans position : l'ordre d'avant (urgentes, puis échéance).
        #expect(ProximityPlanner.choose(all, near: nil).prefix(6).allSatisfy { id in all.first { $0.id == id }!.urgent })
        // Peu de lieux : tous surveillés.
        #expect(ProximityPlanner.choose(Array(places.prefix(3)), near: nil).count == 3)
    }

    @Test func distanceIsInMetres() {
        let d = ProximityPlanner.distance(places[1], (48.85, 2.25))
        #expect(d > 360 && d < 380)
    }

    /// Choix par envie : écrit seulement quand il diffère du défaut du type.
    @Test func nearbyChoiceAndDefaults() {
        let spot = ToSee(.photoSpot).lines.joined(separator: "\n")
        #expect(NearbyReminder.choice(spot) == nil && NearbyReminder.isOn(spot, byDefault: true))
        let off = NearbyReminder.notes(spot, on: false, byDefault: true)
        #expect(off.hasSuffix("🔕 Pas à l'approche") && !NearbyReminder.isOn(off, byDefault: true))
        #expect(NoteLines.visible(off).isEmpty)
        // Remis comme le défaut : plus de ligne.
        #expect(NearbyReminder.notes(off, on: true, byDefault: true) == spot)
        // Hors défaut : la ligne d'avant, inchangée.
        let shop = NearbyReminder.notes("🛍 Magasin", on: true)
        #expect(shop == "🛍 Magasin\n🔔 À l'approche" && NearbyReminder.isOn(shop))
        #expect(NearbyReminder.notes(shop, on: false) == "🛍 Magasin")

        let settings = ToSeeSettings()
        #expect(settings.nearbyByDefault(.photoSpot) && !settings.nearbyByDefault(.shop) && !settings.nearbyByDefault(nil))
        // Réglages enregistrés avant A4 : spots photo activés par défaut.
        let old = try? JSONDecoder().decode(ToSeeSettings.self, from: Data(#"{"atOpening":true,"time":600}"#.utf8))
        #expect(old?.nearbyKinds == ["photoSpot"])
    }

    /// Franprix à 15 h, autre magasin du groupe à 15 h 20 : il rappelle aussi ; pas le Franprix une seconde fois.
    @Test func eachShopOfTheGroupReminds() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let franprix = ProximityReminders.groupKey(taskID: "courses", lieuID: "franprix")
        var notified = [franprix: t0.timeIntervalSince1970]
        let later = t0.addingTimeInterval(20 * 60)
        notified = ProximityReminders.recentGroupNotifications(notified, now: later)
        #expect(notified[ProximityReminders.groupKey(taskID: "courses", lieuID: "monop")] == nil)
        #expect(notified[franprix] != nil)
        // Plus de 2 h après : le Franprix peut rappeler à nouveau.
        #expect(ProximityReminders.recentGroupNotifications(notified, now: t0.addingTimeInterval(2 * 3600 + 1)).isEmpty)
    }
}
