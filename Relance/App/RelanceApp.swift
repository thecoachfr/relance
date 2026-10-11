import BackgroundTasks
import SwiftUI

@main
struct RelanceApp: App {
    @UIApplicationDelegateAdaptor private var delegate: AppDelegate
    @Environment(\.scenePhase) private var scenePhase

    static let refreshTaskID = "fr.alexandrefau.relance.refresh"

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(delegate.store)
                .environment(delegate.auth)
                .modelContainer(delegate.store.container)
                .onOpenURL { delegate.auth.handle($0) }
                .task {
                    await delegate.auth.restore()
                    await delegate.store.sync()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: Task { await delegate.store.sync() }
            case .background: Self.scheduleRefresh()
            default: break
            }
        }
        .backgroundTask(.appRefresh(Self.refreshTaskID)) {
            await Self.scheduleRefresh()
            await delegate.store.sync()
        }
    }

    /// Demande à iOS de réveiller l'app régulièrement pour récupérer les dictées Google Home.
    nonisolated static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = .now.addingTimeInterval(30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
