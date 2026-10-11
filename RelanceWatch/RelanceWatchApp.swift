import SwiftUI

@main
struct RelanceWatchApp: App {
    @State private var store = WatchStore()

    var body: some Scene {
        WindowGroup {
            WatchTaskList()
                .environment(store)
        }
    }
}
