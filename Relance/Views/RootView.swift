import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(GoogleAuth.self) private var auth
    @Environment(TaskStore.self) private var store
    @AppStorage("onboardingDone") private var onboardingDone = false

    var body: some View {
        Group {
            if auth.isRestoring {
                ProgressView()
            } else if !auth.isSignedIn || !onboardingDone {
                OnboardingView(done: $onboardingDone)
            } else {
                MainTabs()
            }
        }
        // Après une (re)connexion, la copie locale est vide : on va chercher les tâches tout de suite.
        .onChange(of: auth.isSignedIn) { _, signedIn in
            if signedIn { Task { await store.sync() } }
        }
    }
}

struct MainTabs: View {
    @Environment(TaskStore.self) private var store
    @Query(filter: #Predicate<TaskItem> { !$0.isCompleted && !$0.isTrashed })
    private var active: [TaskItem]

    var body: some View {
        @Bindable var store = store
        TabView {
            Tab("À faire", systemImage: "checklist") {
                TodoView()
            }
            Tab("À trier", systemImage: "tray") {
                InboxView()
            }
            .badge(active.filter(\.needsTriage).count)
            Tab("Fait", systemImage: "checkmark.circle") {
                DoneView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .sheet(item: Binding(
            get: { store.openedTaskID.flatMap { store.task($0) } },
            set: { store.openedTaskID = $0?.localID })
        ) { item in
            TaskEditor(item: item)
        }
    }
}
