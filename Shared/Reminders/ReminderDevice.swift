import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// L'appareil qui relance. Un seul à la fois : sinon la même tâche sonne deux fois, et un « Fait »
/// sur l'un ne coupe l'autre qu'à sa synchro suivante. Le choix est partagé par iCloud (stockage
/// clé-valeur) pour être le même, et visible, sur l'iPhone, l'iPad et le Mac.
nonisolated enum ReminderDevice: String, CaseIterable, Identifiable, Sendable {
    case iPhone, iPad, mac

    var id: String { rawValue }

    var name: String {
        switch self {
        case .iPhone: "iPhone"
        case .iPad: "iPad"
        case .mac: "Mac"
        }
    }

    var symbol: String {
        switch self {
        case .iPhone: "iphone"
        case .iPad: "ipad"
        case .mac: "laptopcomputer"
        }
    }

    @MainActor static var current: ReminderDevice {
        #if os(macOS)
        .mac
        #else
        UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone
        #endif
    }

    private static let key = "remindersDevice"
    private static var cloud: NSUbiquitousKeyValueStore { .default }

    /// iPhone par défaut. Copie locale si iCloud n'est pas disponible (compte non connecté).
    static var chosen: ReminderDevice {
        get {
            let raw = cloud.string(forKey: key) ?? UserDefaults.standard.string(forKey: key)
            return raw.flatMap(ReminderDevice.init(rawValue:)) ?? .iPhone
        }
        set {
            cloud.set(newValue.rawValue, forKey: key)
            cloud.synchronize()
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
        }
    }

    /// Récupère le dernier choix d'iCloud et appelle `onChange` quand un autre appareil le modifie.
    @MainActor static func observe(_ onChange: @escaping @MainActor () -> Void) {
        cloud.synchronize()
        NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                                               object: cloud, queue: .main) { _ in
            MainActor.assumeIsolated { onChange() }
        }
    }
}
