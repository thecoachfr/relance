import SwiftUI

@main
struct RelanceMacApp: App {
    @NSApplicationDelegateAdaptor private var delegate: MacAppDelegate

    var body: some Scene {
        Window("Aiguillage", id: MacAppDelegate.mainWindowID) {
            MacRootView()
                .environment(delegate.store)
                .environment(delegate.auth)
                .modelContainer(delegate.store.container)
                .onOpenURL { delegate.auth.handle($0) }
        }
        .defaultSize(width: 1100, height: 700)
        .commands { TaskCommands(store: delegate.store) }

        Settings {
            MacSettingsView()
                .environment(delegate.store)
                .environment(delegate.auth)
        }

        // Toujours là, même fenêtre fermée : les tâches du jour et une saisie rapide.
        MenuBarExtra {
            MenuBarView()
                .environment(delegate.store)
                .environment(delegate.auth)
                .modelContainer(delegate.store.container)
        } label: {
            MenuBarLabel(status: delegate.status)
        }
        .menuBarExtraStyle(.window)
    }
}
