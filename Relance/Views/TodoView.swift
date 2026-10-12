import SwiftData
import SwiftUI

struct TodoView: View {
    @Environment(TaskStore.self) private var store
    @Query(filter: #Predicate<TaskItem> { !$0.isCompleted && !$0.isTrashed && $0.dueDay != nil },
           sort: \TaskItem.dueDay)
    private var dated: [TaskItem]

    @State private var showAdd = false
    @State private var showSettings = false
    @State private var editing: TaskItem?
    @State private var justDone: TaskItem?
    /// iPad : tâche affichée dans la colonne de droite.
    @State private var selectedID: UUID?
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .regular {
            NavigationSplitView {
                list
                    // Un seul bouton de panneau latéral (celui des onglets) : la liste reste toujours visible.
                    .toolbar(removing: .sidebarToggle)
                    .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 460)
                    // Grand écran : la colonne de droite montre d'emblée la tâche la plus urgente.
                    .onAppear {
                        if selectedID == nil {
                            selectedID = dated.min { ($0.dueInstant() ?? .distantFuture) < ($1.dueInstant() ?? .distantFuture) }?.localID
                        }
                    }
            } detail: {
                if let id = selectedID, let item = store.task(id), !item.isTrashed {
                    NavigationStack { TaskDetailView(item: item) }
                        .id(id)
                } else {
                    ContentUnavailableView("Aucune tâche sélectionnée", systemImage: "checklist",
                                           description: Text("Choisis une tâche dans la liste pour la voir ici."))
                }
            }
        } else {
            NavigationStack { list }
        }
    }

    /// Grand écran : la tâche s'ouvre à droite ; iPhone : dans une feuille.
    private func open(_ item: TaskItem) {
        if sizeClass == .regular { selectedID = item.localID } else { editing = item }
    }

    private var list: some View {
        TimelineView(.everyMinute) { context in
            let now = context.date
            let groups = group(now: now)
            // Sélection native sur grand écran : flèches ↑ ↓ au clavier, surlignage système.
            List(selection: sizeClass == .regular ? $selectedID : .constant(nil)) {
                section("En retard", groups.overdue, now: now)
                section("Aujourd'hui", groups.today, now: now)
                section("Bientôt", groups.later, now: now)
            }
            .overlay {
                if dated.isEmpty {
                    ContentUnavailableView("Rien d'urgent", systemImage: "checkmark.circle",
                                           description: Text("Les tâches avec une date apparaissent ici."))
                }
            }
        }
        .navigationTitle("À faire")
        .refreshable { await store.sync() }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Réglages", systemImage: "gearshape") { showSettings = true }
            }
            // Tirer pour actualiser ne se devine pas au trackpad : bouton visible sur grand écran.
            if sizeClass == .regular {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Synchroniser", systemImage: "arrow.clockwise") { Task { await store.sync() } }
                        .keyboardShortcut("r", modifiers: .command)
                        .disabled(store.isSyncing)
                }
            }
            // La barre d'onglets d'iOS 26 masque la barre d'outils du bas : l'ajout va en haut à droite.
            ToolbarItem(placement: .primaryAction) {
                Button("Nouvelle tâche", systemImage: "plus") { showAdd = true }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("n", modifiers: .command)
            }
        }
        .safeAreaInset(edge: .bottom) { undoBanner }
        .sheet(isPresented: $showAdd) { QuickAddSheet() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(item: $editing) { TaskEditor(item: $0) }
        .sensoryFeedback(.success, trigger: justDone)
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [TaskItem], now: Date) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { item in
                    TaskRow(item: item, now: now, onDone: markDone)
                        .taskActions(item, onDone: markDone, onEdit: open)
                        .tag(item.localID)
                }
            }
        }
    }

    private func group(now: Date) -> (overdue: [TaskItem], today: [TaskItem], later: [TaskItem]) {
        let calendar = Calendar.current
        let sorted = dated.sorted { ($0.dueInstant() ?? .distantFuture) < ($1.dueInstant() ?? .distantFuture) }
        let overdue = sorted.filter { $0.isOverdue(now: now) }
        let rest = sorted.filter { !$0.isOverdue(now: now) }
        return (overdue,
                rest.filter { calendar.isDateInToday($0.dueDay!) },
                rest.filter { !calendar.isDateInToday($0.dueDay!) })
    }

    private func markDone(_ item: TaskItem) {
        withAnimation { store.complete(item) }
        justDone = item
        Task {
            try? await Task.sleep(for: .seconds(4))
            if justDone == item { withAnimation { justDone = nil } }
        }
    }

    /// Annuler plutôt que confirmer (HIG).
    @ViewBuilder
    private var undoBanner: some View {
        if let item = justDone {
            HStack {
                Text("« \(item.title) » fait").lineLimit(1)
                Spacer()
                Button("Annuler") {
                    withAnimation {
                        store.reopen(item)
                        justDone = nil
                    }
                }
                .bold()
            }
            .padding()
            .background(.regularMaterial, in: .rect(cornerRadius: 14))
            .padding(.horizontal)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
