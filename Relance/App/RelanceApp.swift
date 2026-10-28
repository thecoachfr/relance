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
                .onOpenURL { url in
                    // relance://nouvelle, relance://tache/<clé>, relance://memo/<id> (README, « Liens ») ;
                    // sinon le retour de la connexion Google.
                    if url.scheme == LienAiguillage.schema {
                        delegate.store.ouvrir(url)
                    } else {
                        delegate.auth.handle(url)
                    }
                }
                .task {
                    if !AppDelegate.isDemo { await delegate.auth.restore() }
                    await delegate.store.sync()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                if AppGroup.defaults.bool(forKey: NewTaskIntent.pendingKey) {
                    AppGroup.defaults.removeObject(forKey: NewTaskIntent.pendingKey)
                    delegate.store.showQuickAdd = true
                }
                SyncLog.add("Ouverture de l'app")
                Task { await delegate.store.sync() }
            case .background: Self.scheduleRefresh()
            default: break
            }
        }
        .backgroundTask(.appRefresh(Self.refreshTaskID)) {
            SyncLog.add("Réveil iOS en arrière-plan")
            await Self.scheduleRefresh()
            await delegate.store.sync()
        }
    }

    /// Demande à iOS de réveiller l'app régulièrement pour récupérer les dictées Google Home.
    nonisolated static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = .now.addingTimeInterval(30 * 60)
        Journal.essayer(.systeme, "Programmation du réveil en arrière-plan") { try BGTaskScheduler.shared.submit(request) }
    }
}
