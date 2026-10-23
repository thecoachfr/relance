import SwiftUI
import WatchKit

@main
struct RelanceWatchApp: App {
    @State private var store = WatchStore.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchTaskList()
                .environment(store)
                // Mémoire et arrêts inattendus, seulement pendant que l'app est à l'écran (Diagnostic).
                .suiviEcran()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refreshFromGoogle() } }
            if phase == .background { Self.scheduleRefresh() }
        }
        // Rafraîchissement régulier, même iPhone absent : garde la complication à jour.
        .backgroundTask(.appRefresh) { _ in
            await store.refreshFromGoogle()
            await Self.scheduleRefresh()
        }
    }

    nonisolated static func scheduleRefresh() {
        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: .now.addingTimeInterval(30 * 60), userInfo: nil) { _ in }
    }
}
