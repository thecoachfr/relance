import SwiftData
import SwiftUI

struct TodoView: View {
    @Environment(TaskStore.self) private var store
    @Query(filter: #Predicate<TaskItem> { !$0.isCompleted && !$0.isTrashed && $0.dueDay != nil },
           sort: \TaskItem.dueDay)
    private var dated: [TaskItem]
    @Query(filter: #Predicate<TaskItem> { $0.isCompleted && !$0.isTrashed })
    private var completed: [TaskItem]
    /// Sans date : seules les listes de courses (rappelées par le magasin) sont montrées ici.
    @Query(filter: #Predicate<TaskItem> { !$0.isCompleted && !$0.isTrashed && $0.dueDay == nil },
           sort: \TaskItem.updatedAt, order: .reverse)
    private var undated: [TaskItem]

    @State private var showAdd = false
    @State private var showDone = false
    @State private var showSettings = false
    @State private var editing: TaskItem?
    @State private var justDone: TaskItem?
    /// iPad : tâche affichée dans la colonne de droite.
    @State private var selectedID: UUID?
    @AppStorage("categoryFilter") private var categoryFilter = ""
    /// Liste ou Agenda (30/10) : mémorisé.
    @AppStorage("todoAffichage") private var affichage = Affichage.liste
    /// Plage touchée dans l'agenda : saisie rapide à ce jour et cette heure.
    @State private var ajoutAgenda: AjoutAgenda?

    enum Affichage: String { case liste, agenda }
    private struct AjoutAgenda: Identifiable { let id = UUID(); let jour: Date; let minutes: Int? }
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .regular {
            NavigationSplitView {
                list
                    // Un seul bouton de panneau latéral (celui des onglets) : la liste reste toujours visible.
                    .toolbar(removing: .sidebarToggle)
                    .navigationSplitViewColumnWidth(min: 380, ideal: 440, max: 520)
                    // Grand écran : la colonne de droite montre d'emblée la tâche la plus urgente.
                    .onAppear {
                        #if DEBUG
                        // `-fiche <début du titre>` (captures d'écran) : cette tâche à droite.
                        if let titre = UserDefaults.standard.string(forKey: "fiche") {
                            selectedID = dated.first { $0.title.hasPrefix(titre) }?.localID
                        }
                        #endif
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
            if affichage == .agenda {
                AgendaView(taches: dated.filter { $0.matches(categoryFilter: categoryFilter) }, now: now,
                           onOpen: open, onDone: markDone,
                           onAdd: { jour, minutes in ajoutAgenda = AjoutAgenda(jour: jour, minutes: minutes) })
            } else {
            // Sélection native sur grand écran : flèches ↑ ↓ au clavier, surlignage système.
            List(selection: sizeClass == .regular ? $selectedID : .constant(nil)) {
                // Bureau ou télétravail (P9-N2) : la phrase du capteur, en tête.
                LieuTravailBandeau()
                // Rappels « pour info » (P9-P) : à part, sans « Fait ».
                PourInfoAujourdhuiSection(infos: dated.filter(\.estPourInfo), now: now, onSelect: open)
                section("En retard", groups.overdue, now: now)
                section("Aujourd'hui", groups.today, now: now)
                section("Listes de courses", undated.filter { $0.estListeDeCoursesSansDate && $0.matches(categoryFilter: categoryFilter) }, now: now)
                section("Bientôt", groups.later, now: now)
                doneLink(now: now)
            }
            // Pastille du lieu à côté de la date de chaque tâche (jours travaillés, mode HA seulement).
            .environment(\.lieuTravailDesJours, store.isHAActive ? store.lieuTravail : nil)
            .overlay {
                if dated.isEmpty && !undated.contains(where: \.estListeDeCoursesSansDate) {
                    ContentUnavailableView("Rien d'urgent", systemImage: "checkmark.circle",
                                           description: Text("Les tâches avec une date apparaissent ici."))
                } else if !categoryFilter.isEmpty, !dated.contains(where: { $0.matches(categoryFilter: categoryFilter) }) {
                    ContentUnavailableView("Rien en « \(categoryFilter) »", systemImage: "line.3.horizontal.decrease.circle",
                                           description: Text("Change de filtre pour voir les autres tâches."))
                }
            }
            }
        }
        .navigationTitle("À faire")
        .settingsButton(visible: sizeClass != .regular)
        .sheet(isPresented: $showSettings) { SettingsView() }
        .refreshable { await store.sync() }
        .toolbar {
            // Liste ou Agenda (30/10) : à la place du titre.
            ToolbarItem(placement: .principal) {
                Picker("Affichage", selection: $affichage) {
                    Text("Liste").tag(Affichage.liste)
                    Text("Agenda").tag(Affichage.agenda)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            if sizeClass == .regular {
                // Grand écran (30/10) : trois entrées seulement (⋯, Liste/Agenda, +) ; synchro, réglages et filtre dans
                // le menu « ⋯ » (sept boutons se chevauchaient dans la colonne).
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Synchroniser", systemImage: "arrow.clockwise") { Task { await store.sync() } }
                            .disabled(store.isSyncing)
                        CategoryFilterMenu(filter: $categoryFilter)
                        Divider()
                        Button("Réglages", systemImage: "gearshape") { showSettings = true }
                    } label: {
                        Label("Plus", systemImage: categoryFilter.isEmpty ? "ellipsis.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    CategoryFilterMenu(filter: $categoryFilter)
                }
            }
            // La barre d'onglets d'iOS 26 masque la barre d'outils du bas : l'ajout va en haut à droite.
            AddTaskToolbarButton(context: .today, isPresented: $showAdd)
        }
        .safeAreaInset(edge: .bottom) { undoBanner }
        // ⌘R : synchroniser, même menu fermé (le bouton est rangé dans « ⋯ » sur grand écran).
        .background {
            Button("Synchroniser") { Task { await store.sync() } }
                .keyboardShortcut("r", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .sheet(isPresented: $showAdd) { QuickAddSheet() }
        .sheet(item: $ajoutAgenda) { QuickAddSheet(jour: $0.jour, minutes: $0.minutes) }
        .sheet(isPresented: $showDone) { DoneView() }
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

    /// Dernière ligne : l'historique de ce qui est fait (il n'a plus d'onglet).
    private func doneLink(now: Date) -> some View {
        let today = completed.filter { $0.completedAt.map { Calendar.current.isDate($0, inSameDayAs: now) } ?? false }.count
        return Section {
            Button { showDone = true } label: {
                LabeledContent {
                    if today > 0 { Text("\(today) aujourd'hui") }
                } label: {
                    Label("Fait", systemImage: "checkmark.circle")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Ouvre l'historique des tâches faites")
        }
        .selectionDisabled()
    }

    private func group(now: Date) -> (overdue: [TaskItem], today: [TaskItem], later: [TaskItem]) {
        let calendar = Calendar.current
        // Dans chaque section : les urgentes d'abord, puis par échéance.
        // Une sortie passée (P9-L1) quitte À faire : elle attend « Vu » dans Envies (Passées).
        let sorted = dated.filter { $0.matches(categoryFilter: categoryFilter) && !$0.estPourInfo }
            .filter { $0.toSee?.kind.isDated != true || ($0.dueInstant() ?? .distantFuture) >= now }
            .sorted { a, b in
            if a.priority.rank != b.priority.rank { return a.priority.rank < b.priority.rank }
            return (a.dueInstant() ?? .distantFuture) < (b.dueInstant() ?? .distantFuture)
        }
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
