import SwiftData
import SwiftUI

struct MacRootView: View {
    @Environment(GoogleAuth.self) private var auth
    @Environment(TaskStore.self) private var store

    var body: some View {
        Group {
            if auth.isRestoring {
                ProgressView()
            } else if !auth.isSignedIn {
                MacSignInView()
            } else {
                MacMainView()
            }
        }
        .frame(minWidth: 860, minHeight: 520)
        // Après une (re)connexion, la copie locale est vide : on va chercher les tâches tout de suite.
        .onChange(of: auth.isSignedIn) { _, signedIn in
            if signedIn { Task { await store.sync() } }
        }
    }
}

/// Listes de la barre latérale.
enum MacSection: Hashable {
    case todo, inbox, toSee, map, done
    case category(String)
    case tag(String)

    var title: String {
        switch self {
        case .todo: "À faire"
        case .inbox: "À trier"
        case .toSee: "À voir"
        case .map: "Carte"
        case .done: "Fait"
        case .category(let name): name
        case .tag(let tag): "#" + tag
        }
    }
}

/// Trois colonnes, comme Rappels ou Mail : listes, tâches, détail.
struct MacMainView: View {
    @Environment(TaskStore.self) private var store
    @Query(filter: #Predicate<TaskItem> { !$0.isCompleted && !$0.isTrashed })
    private var active: [TaskItem]

    @State private var section: MacSection? = .todo
    @State private var selectedID: UUID?
    @State private var search = ""
    @State private var deleting: TaskItem?

    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 280)
        } content: {
            Group {
                if section == .map {
                    TaskMapView(selection: $selectedID, showsSummary: false)
                } else if section == .toSee {
                    ToSeeListView(selection: $selectedID)
                } else {
                    MacTaskList(section: section ?? .todo, search: search, selection: $selectedID)
                }
            }
                .environment(\.deleteTask, requestDelete)
                .navigationSplitViewColumnWidth(min: 300, ideal: 380, max: 520)
                // Au-dessus de la liste ; les actions de la tâche vont au-dessus du détail.
                .toolbar {
                    ToolbarItemGroup {
                        Button("Synchroniser", systemImage: "arrow.clockwise") { Task { await store.sync() } }
                            .disabled(store.isSyncing)
                            .help(store.lastError.map { "Dernière synchro en échec : \($0)" } ?? "Synchroniser avec Google Tasks (⌘R)")
                        Button("Nouvelle tâche", systemImage: "plus") { store.showQuickAdd = true }
                            .help("Nouvelle tâche (⌘N)")
                    }
                }
        } detail: {
            detail
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Rechercher")
        .sheet(isPresented: $store.showQuickAdd) {
            QuickAddSheet()
                .formStyle(.grouped)
                .frame(width: 480, height: 540)
        }
        .confirmationDialog("Cette tâche est dans ton agenda.", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible, presenting: deleting) { item in
            Button("Supprimer la tâche et l'événement", role: .destructive) {
                CalendarLink.shared.remove(item, taskStore: store, keepTask: false)
                delete(item)
            }
            Button("Supprimer la tâche seulement", role: .destructive) { delete(item) }
        }
        .focusedSceneValue(\.selectedTask, selectedID.flatMap { store.task($0) })
        .focusedSceneValue(\.deleteTask, requestDelete)
        .onChange(of: section) { selectedID = nil }
        // Clic sur une notification ou sur une tâche de la barre des menus.
        .onChange(of: store.openedTaskID, initial: true) { _, id in
            guard let id, let item = store.task(id) else { return }
            section = item.isCompleted ? .done : item.toSee != nil ? .toSee : item.needsTriage ? .inbox : .todo
            search = ""
            // Après le changement de section (qui vide la sélection).
            Task { selectedID = id }
            store.openedTaskID = nil
        }
    }

    /// Une tâche liée à un événement : on demande s'il faut aussi l'enlever de l'agenda.
    private func requestDelete(_ item: TaskItem) {
        if item.calendarEventID != nil { deleting = item } else { delete(item) }
    }

    private func delete(_ item: TaskItem) {
        if selectedID == item.localID { selectedID = nil }
        store.delete(item)
    }

    private var sidebar: some View {
        return List(selection: $section) {
            Section {
                Label("À faire", systemImage: "checklist")
                    .badge(active.filter { $0.dueDay != nil }.count)
                    .tag(MacSection.todo)
                Label("À trier", systemImage: "tray")
                    .badge(active.filter(\.needsTriage).count)
                    .tag(MacSection.inbox)
                Label("À voir", systemImage: "eyeglasses")
                    .badge(active.filter { $0.toSee != nil }.count)
                    .tag(MacSection.toSee)
                Label("Carte", systemImage: "map")
                    .tag(MacSection.map)
                Label("Fait", systemImage: "checkmark.circle")
                    .tag(MacSection.done)
            }
            Section("Catégories") {
                ForEach(TaskCategory.allCases) { category in
                    Label {
                        Text(category.rawValue)
                    } icon: {
                        Image(systemName: category.symbol).foregroundStyle(category.color)
                    }
                    .badge(active.filter { $0.category == category.rawValue }.count)
                    .tag(MacSection.category(category.rawValue))
                }
            }
            Section("Tags") {
                ForEach(store.knownTags(), id: \.self) { tag in
                    // Le « # » du texte suffit : une icône « # » en plus faisait doublon, en plus gros.
                    Label("#" + tag, systemImage: "tag")
                        .badge(active.filter { $0.matches(categoryFilter: "#" + tag) }.count)
                        .tag(MacSection.tag(tag))
                }
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if let id = selectedID, let item = store.task(id), !item.isTrashed {
            NavigationStack { TaskDetailView(item: item) }
                .formStyle(.grouped)
                .id(id)
        } else {
            ContentUnavailableView("Aucune tâche sélectionnée", systemImage: "checklist",
                                   description: Text("Choisis une tâche dans la liste pour la voir ici."))
        }
    }
}

extension FocusedValues {
    /// Tâche sélectionnée dans la fenêtre, pour le menu Tâche.
    @Entry var selectedTask: TaskItem?
    /// Supprime une tâche en demandant quoi faire de son événement d'agenda.
    @Entry var deleteTask: ((TaskItem) -> Void)?
}
