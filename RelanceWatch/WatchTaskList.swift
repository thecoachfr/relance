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
                    // Lieu de travail du jour (P9-N2), seulement les jours travaillés : en tête, sans rien demander à HA.
                    if let lieu = WatchLink.libelleDuJour(store.lieuxTravail, date: now) {
                        Text(lieu)
                            .font(.headline)
                            .listRowBackground(Color.clear)
                            .accessibilityLabel("Aujourd'hui : \(lieu)")
                    }
                    section("En retard", late, now: now)
                    section("Aujourd'hui", today, now: now)
                    section("Bientôt", later, now: now)
                    section("Sans date", inbox, now: now)
                    if let updated = store.lastUpdate, !store.tasks.isEmpty {
                        Text("Mis à jour \(updated, format: .relative(presentation: .named))")
                            .font(.footnote).foregroundStyle(.secondary)
                            .listRowBackground(Color.clear)
                    }
                    if !store.tasks.isEmpty {
                        NavigationLink { WatchDiagnosticView() } label: {
                            Label("Diagnostic", systemImage: "stethoscope")
                        }
                        Text("Version \(AppVersion.full)")
                            .font(.footnote).foregroundStyle(.tertiary)
                            .listRowBackground(Color.clear)
                    }
                }
                .refreshable { await store.refreshFromGoogle() }
                .overlay {
                    if store.tasks.isEmpty {
                        ContentUnavailableView {
                            Label("Rien d'urgent", systemImage: "checkmark.circle")
                        } description: {
                            Text(store.google.isAvailable
                                 ? "Aucune tâche à faire."
                                 : "Ouvre Aiguillage sur l'iPhone une fois pour connecter la montre.")
                            + Text("\nVersion \(AppVersion.full)").foregroundStyle(.tertiary)
                        } actions: {
                            NavigationLink { WatchDiagnosticView() } label: {
                                Label("Diagnostic", systemImage: "stethoscope")
                            }
                        }
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
                    Group {
                        if task.articles?.isEmpty == false {
                            NavigationLink { WatchListeView(taskID: task.id) } label: { WatchTaskRow(task: task, now: now) }
                        } else {
                            WatchTaskRow(task: task, now: now)
                        }
                    }
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
                if let articles = task.articles, !articles.isEmpty {
                    Label("\(articles.filter(\.coche).count)/\(articles.count)", systemImage: "checklist")
                        .font(.footnote).foregroundStyle(.secondary)
                        .accessibilityLabel("Liste : \(articles.filter(\.coche).count) cochés sur \(articles.count)")
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

/// Liste d'articles d'une tâche (P9-G2) : toucher coche ou décoche. Tout coché : la tâche passe en « Fait ».
struct WatchListeView: View {
    @Environment(WatchStore.self) private var store
    let taskID: String

    var body: some View {
        if let task = store.tasks.first(where: { $0.id == taskID }), let articles = task.articles {
            List {
                // Ce qui reste à prendre d'abord, ce qui est déjà dans le panier ensuite.
                ForEach(articles.filter { !$0.coche } + articles.filter(\.coche)) { article in
                    Button { store.setArticle(article, coche: !article.coche, of: task) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: article.coche ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(article.coche ? Color.accentColor : Color.secondary)
                            Text(article.texte)
                                .strikethrough(article.coche)
                                .foregroundStyle(article.coche ? .secondary : .primary)
                            Spacer(minLength: 0)
                            if let quantite = article.quantite {
                                Text(quantite).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityAddTraits(article.coche ? .isSelected : [])
                }
            }
            .navigationTitle(task.title)
        } else {
            ContentUnavailableView("Liste terminée", systemImage: "checkmark.circle",
                                   description: Text("Tout est coché : la tâche est faite."))
        }
    }
}
