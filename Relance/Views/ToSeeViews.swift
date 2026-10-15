import SwiftData
import SwiftUI

extension TaskStore {
    /// Range la tâche dans les envies (sans échéance), ou l'en sort.
    @MainActor func setToSee(_ item: TaskItem, _ toSee: ToSee?) {
        update(item, title: item.title, notes: ToSee.notes(item.notes, setting: toSee),
               day: toSee == nil ? item.dueDay : nil, minutes: toSee == nil ? item.dueMinutes : nil)
    }

    /// Change le type d'une envie (une sortie devient « À regarder »…), sans toucher à sa période.
    @MainActor func setKind(_ item: TaskItem, _ kind: ToSee.Kind) {
        guard var toSee = item.toSee else { return }
        toSee.kind = kind
        setToSee(item, toSee)
    }
}

/// Section « Envie » du détail : sans échéance, un type (voir, lire, écouter, regarder),
/// une période facultative (début, fin) et le lien à ouvrir s'il y en a un dans les notes.
struct ToSeeSection: View {
    @Binding var notes: String
    /// Type proposé quand on active l'envie (celui du filtre d'où vient la saisie).
    var kind: ToSee.Kind = .outing
    /// Passer en envie retire l'échéance du formulaire.
    var onEnable: () -> Void = {}

    private var toSee: ToSee? { ToSee(notes: notes) }

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { toSee != nil }, set: { on in
                notes = ToSee.notes(notes, setting: on ? ToSee(kind) : nil)
                if on { onEnable() }
            })) {
                Label("Envie, sans échéance", systemImage: "bookmark")
            }
            if let toSee {
                Picker("Type", selection: Binding(get: { toSee.kind }, set: { var t = toSee; t.kind = $0; set(t) })) {
                    ForEach(ToSee.Kind.allCases) { Text($0.shortTitle).tag($0) }
                }
                .pickerStyle(.segmented)
                dateRow("Début", date: toSee.start) { var t = toSee; t.start = $0; set(t) }
                dateRow("Fin", date: toSee.end) { var t = toSee; t.end = $0; set(t) }
                if let link = ToSee.link(in: notes) {
                    Link(destination: link) {
                        Label("Ouvrir " + (link.host()?.replacingOccurrences(of: "www.", with: "") ?? "le lien"),
                              systemImage: "arrow.up.right.square")
                    }
                }
            }
        } footer: {
            if let toSee {
                if toSee.end == nil && toSee.start == nil {
                    Text(toSee.kind == .outing
                         ? "Gardée dans Envies, sans relance. Ajoute une période (expo, festival…) pour être prévenu au bon moment."
                         : "Gardée dans Envies › \(toSee.kind.title), sans relance. Une période (film en salle, replay) te préviendra avant la fin.")
                } else {
                    Text("Prévenu à l'ouverture, quelques semaines avant la fin et le dernier week-end (Réglages › Relances › Envies).")
                }
            } else {
                Text("Pour une sortie, un livre, un album, un film : gardé à part, sans relance chaque jour.")
            }
        }
    }

    private func set(_ toSee: ToSee) { notes = ToSee.notes(notes, setting: toSee) }

    private func dateRow(_ title: String, date: Date?, change: @escaping (Date?) -> Void) -> some View {
        LabeledContent(title) {
            HStack {
                if let date {
                    DatePicker(title, selection: Binding(get: { date }, set: { change(Calendar.current.startOfDay(for: $0)) }),
                               displayedComponents: .date)
                        .labelsHidden()
                }
                Toggle(title, isOn: Binding(get: { date != nil }, set: { change($0 ? Calendar.current.startOfDay(for: .now) : nil) }))
                    .labelsHidden()
            }
        }
    }
}

/// Envies : sorties, à lire, à écouter, à regarder. Un filtre en haut ; « Tout » range par type,
/// un type seul range par période : en cours (la fin la plus proche d'abord), à venir, sans date, terminées.
/// Sous un type : les dernières faites (« Déjà lu »), pour en remettre une.
struct ToSeeListView: View {
    @Environment(TaskStore.self) private var store
    @Query(filter: #Predicate<TaskItem> { !$0.isCompleted && !$0.isTrashed })
    private var active: [TaskItem]
    @Query(filter: #Predicate<TaskItem> { $0.isCompleted && !$0.isTrashed },
           sort: \TaskItem.completedAt, order: .reverse)
    private var completed: [TaskItem]
    @State private var editing: TaskItem?
    @State private var adding = false
    /// Type affiché ; vide = tout.
    @AppStorage("enviesFilter") private var filterRaw = ""
    var selection: Binding<UUID?>?

    private var filter: ToSee.Kind? { ToSee.Kind(rawValue: filterRaw) }

    static func groups(_ items: [TaskItem], kind: ToSee.Kind? = nil, now: Date = .now) -> [(title: String, items: [TaskItem])] {
        let seen = items.compactMap { item in item.toSee.map { (item, $0) } }
        guard let kind else {
            // Tout : un groupe par type, la fin la plus proche d'abord, puis les plus récentes.
            return ToSee.Kind.allCases.map { k in
                (k.title, seen.filter { $0.1.kind == k && !$0.1.isOver(now: now) }.sorted(by: order).map(\.0))
            }.filter { !$0.1.isEmpty }
        }
        let today = Calendar.current.startOfDay(for: now)
        let mine = seen.filter { $0.1.kind == kind }
        let over = mine.filter { $0.1.isOver(now: now) }
        let current = mine.filter { !$0.1.isOver(now: now) && ($0.1.start.map { $0 <= today } ?? true) && $0.1.end != nil }
            .sorted { $0.1.end! < $1.1.end! }
        let upcoming = mine.filter { ($0.1.start.map { $0 > today } ?? false) && !$0.1.isOver(now: now) }
            .sorted { $0.1.start! < $1.1.start! }
        let open = mine.filter { ($0.1.start.map { $0 <= today } ?? true) && $0.1.end == nil }
            .sorted { $0.0.updatedAt > $1.0.updatedAt }
        return [("En ce moment", current.map(\.0)), ("Bientôt", upcoming.map(\.0)),
                (kind == .outing ? "Sans date" : "Quand tu veux", open.map(\.0)), ("Terminé", over.map(\.0))]
            .filter { !$0.1.isEmpty }
    }

    private static func order(_ a: (TaskItem, ToSee), _ b: (TaskItem, ToSee)) -> Bool {
        switch (a.1.end, b.1.end) {
        case let (x?, y?): x < y
        case (_?, nil): true
        case (nil, _?): false
        case (nil, nil): a.0.updatedAt > b.0.updatedAt
        }
    }

    var body: some View {
        let groups = Self.groups(active, kind: filter)
        let done = filter.map { kind in completed.filter { $0.toSee?.kind == kind }.prefix(10) } ?? []
        List(selection: selection ?? .constant(nil)) {
            // En tête de liste (et pas dans une barre) : le grand titre reste visible et le filtre défile avec.
            Picker("Type", selection: $filterRaw) {
                Text("Tout").tag("")
                ForEach(ToSee.Kind.allCases) { Text($0.shortTitle).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            .selectionDisabled()
            ForEach(groups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.items) { item in
                        TaskRow(item: item, isSelected: selection?.wrappedValue == item.localID) { store.complete($0) }
                            .tag(item.localID)
                            .contentShape(Rectangle())
                            .onTapGesture { open(item) }
                            .contextMenu { menu(for: item) }
                    }
                }
            }
            if let filter, !done.isEmpty {
                Section(filter.doneSection) {
                    ForEach(done) { item in
                        DoneRow(item: item)
                            .tag(item.localID)
                            .contentShape(Rectangle())
                            .onTapGesture { open(item) }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button("Remettre", systemImage: "arrow.uturn.backward") { store.reopen(item) }.tint(.blue)
                            }
                            .contextMenu {
                                Button("Remettre dans les envies", systemImage: "arrow.uturn.backward") { store.reopen(item) }
                            }
                    }
                }
            }
        }
        .overlay {
            if groups.isEmpty && done.isEmpty { empty }
        }
        .navigationTitle("Envies")
        .sheet(item: $editing) { TaskEditor(item: $0) }
        #if os(iOS)
        // Sur Mac, le « + » de la colonne suit déjà la section.
        .toolbar { AddTaskToolbarButton(context: .toSee(filter ?? .outing), isPresented: $adding) }
        .sheet(isPresented: $adding) { QuickAddSheet(context: .toSee(filter ?? .outing)) }
        #endif
    }

    private func open(_ item: TaskItem) {
        if selection == nil { editing = item } else { selection?.wrappedValue = item.localID }
    }

    @ViewBuilder private func menu(for item: TaskItem) -> some View {
        let kind = item.toSee?.kind ?? .outing
        Button(kind.doneTitle, systemImage: "checkmark") { store.complete(item) }
        if let link = ToSee.link(in: item.notes) {
            Link(destination: link) { Label("Ouvrir", systemImage: "arrow.up.right.square") }
        }
        Menu("Type", systemImage: "arrow.left.arrow.right") {
            ForEach(ToSee.Kind.allCases.filter { $0 != kind }) { k in
                Button(k.title, systemImage: k.symbol) { store.setKind(item, k) }
            }
        }
        Button("Remettre dans À trier", systemImage: "tray") { store.setToSee(item, nil) }
    }

    @ViewBuilder private var empty: some View {
        switch filter {
        case nil:
            ContentUnavailableView("Aucune envie pour l'instant", systemImage: "bookmark",
                                   description: Text("Une expo, un livre, un album, un film : partage-le depuis une autre app, ou touche +."))
        case .outing?:
            ContentUnavailableView("Rien à voir pour l'instant", systemImage: ToSee.Kind.outing.symbol,
                                   description: Text("Une expo, un festival, un lieu à découvrir."))
        case .read?:
            ContentUnavailableView("Rien à lire pour l'instant", systemImage: ToSee.Kind.read.symbol,
                                   description: Text("Un livre, un article : partage-le depuis Safari ou Livres."))
        case .listen?:
            ContentUnavailableView("Rien à écouter pour l'instant", systemImage: ToSee.Kind.listen.symbol,
                                   description: Text("Un album, un podcast : partage-le depuis Musique, Spotify ou Podcasts."))
        case .watch?:
            ContentUnavailableView("Rien à regarder pour l'instant", systemImage: ToSee.Kind.watch.symbol,
                                   description: Text("Un film, une série, une vidéo : partage-la depuis YouTube ou une autre app."))
        }
    }
}

/// Ligne d'une tâche faite : titre barré, quand.
struct DoneRow: View {
    let item: TaskItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title).strikethrough().foregroundStyle(.secondary)
            if let date = item.completedAt {
                Text(date, format: .relative(presentation: .named))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
