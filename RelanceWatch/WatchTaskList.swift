import SwiftUI

struct WatchTaskList: View {
    @Environment(WatchStore.self) private var store
    @State private var showAdd = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { context in
                let now = context.date
                let dated = store.tasks.filter { $0.due != nil }
                    .sorted { $0.isUrgent != $1.isUrgent ? $0.isUrgent : $0.due! < $1.due! }
                let late = dated.filter { $0.isLate(at: now) }
                let today = dated.filter { !$0.isLate(at: now) && isToday($0, now: now) }
                let later = dated.filter { !$0.isLate(at: now) && !isToday($0, now: now) }
                let inbox = store.tasks.filter { $0.due == nil }

                List {
                    section("En retard", late, now: now)
                    section("Aujourd'hui", today, now: now)
                    section("Bientôt", later, now: now)
                    section("Sans date", inbox, now: now)
                    if let updated = store.lastUpdate, !store.tasks.isEmpty {
                        Text("Mis à jour \(updated, format: .relative(presentation: .named))")
                            .font(.footnote).foregroundStyle(.secondary)
                            .listRowBackground(Color.clear)
                    }
                }
                .refreshable { await store.refreshFromGoogle() }
                .overlay {
                    if store.tasks.isEmpty {
                        ContentUnavailableView("Rien d'urgent", systemImage: "checkmark.circle",
                                               description: Text(store.google.isAvailable
                                                                 ? "Aucune tâche à faire."
                                                                 : "Ouvre Aiguillage sur l'iPhone une fois pour connecter la montre."))
                    }
                }
            }
            .navigationTitle("Aiguillage")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Nouvelle tâche", systemImage: "plus") { showAdd = true }
                }
            }
            .sheet(isPresented: $showAdd) { NavigationStack { WatchAddView() } }
            // Complication « + » et commande « Nouvelle tâche » : ouvrent directement la saisie.
            .onOpenURL { url in
                WatchQuickAdd.defaults.removeObject(forKey: WatchQuickAdd.pendingKey)
                showAdd = url == WatchQuickAdd.url
            }
            .onReceive(NotificationCenter.default.publisher(for: WatchQuickAdd.notification)) { _ in openPendingAdd() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { openPendingAdd() } }
            .onAppear { openPendingAdd() }
        }
    }

    private func openPendingAdd() {
        let requested = WatchQuickAdd.defaults.double(forKey: WatchQuickAdd.pendingKey)
        guard requested > 0 else { return }
        WatchQuickAdd.defaults.removeObject(forKey: WatchQuickAdd.pendingKey)
        if Date.now.timeIntervalSince1970 - requested < 10 { showAdd = true }
    }

    @ViewBuilder
    private func section(_ title: String, _ tasks: [WatchTask], now: Date) -> some View {
        if !tasks.isEmpty {
            Section(title) {
                ForEach(tasks) { task in
                    WatchTaskRow(task: task, now: now)
                        .swipeActions(edge: .leading) {
                            Button("Fait", systemImage: "checkmark") { store.complete(task) }.tint(.green)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("1 h", systemImage: "clock") { store.snooze(task) }.tint(.orange)
                        }
                }
            }
        }
    }

    private func isToday(_ task: WatchTask, now: Date) -> Bool {
        guard let due = task.due else { return false }
        let day = task.hasTime ? due : due.addingTimeInterval(-1)
        return Calendar.current.isDate(day, inSameDayAs: now)
    }
}

struct WatchTaskRow: View {
    @Environment(WatchStore.self) private var store
    let task: WatchTask
    let now: Date

    var body: some View {
        let late = task.isLate(at: now) && (task.snoozedUntil ?? .distantPast) <= now
        HStack(spacing: 8) {
            Button { store.complete(task) } label: {
                PriorityCircle(priority: task.priority ?? .normal, late: late)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Marquer « \(task.title) » comme faite")

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title).font(.body).lineLimit(2)
                    .foregroundStyle(task.priority == .low ? .secondary : .primary)
                if let status = status(late: late) {
                    Text(status).font(.footnote).foregroundStyle(late ? .red : .secondary)
                }
                if let name = task.category {
                    let category = TaskCategory(name: name)
                    HStack(spacing: 3) {
                        Image(systemName: category?.symbol ?? "tag").foregroundStyle(category?.color ?? .gray)
                        // La catégorie garde sa ligne ; ce sont les tags qui se tronquent.
                        Text(name).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                        if let tags = task.tags {
                            Text(tags.map { "#" + $0 }.joined(separator: " ")).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .font(.caption2)
                    .accessibilityLabel("Catégorie \(name)")
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(task.priority.map { $0 == .normal ? "" : "Priorité \($0.rawValue)" } ?? "")
        .accessibilityAction(named: "Fait") { store.complete(task) }
        .accessibilityAction(named: "Reporter d'une heure") { store.snooze(task) }
    }

    private func status(late: Bool) -> String? {
        if let snoozed = task.snoozedUntil, snoozed > now { return "Relance à " + DueText.clock(snoozed) }
        guard let due = task.due else { return nil }
        return DueText.long(due: due, hasTime: task.hasTime, now: now)
    }
}
