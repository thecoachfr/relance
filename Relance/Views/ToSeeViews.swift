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
    /// Disponibilités TMDB de l'envie (fiche d'une tâche existante), affichées pour « À regarder ».
    var availability: Availability?
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
                // Sept types : un menu plutôt qu'un sélecteur segmenté (illisible au-delà de cinq sur iPhone).
                Picker("Type", selection: Binding(get: { toSee.kind }, set: { var t = toSee; t.kind = $0; set(t) })) {
                    ForEach(ToSee.Kind.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
                .pickerStyle(.menu)
                if toSee.kind == .photoSpot {
                    TextField("Lumière, saison (au couchant, en automne…)", text: Binding(
                        get: { toSee.note ?? "" },
                        set: { var t = toSee; t.note = $0.isEmpty ? nil : $0; set(t) }))
                }
                dateRow("Début", date: toSee.start) { var t = toSee; t.start = $0; set(t) }
                dateRow("Fin", date: toSee.end) { var t = toSee; t.end = $0; set(t) }
                if let link = ToSee.link(in: notes) {
                    Link(destination: link) {
                        Label("Ouvrir " + (link.host()?.replacingOccurrences(of: "www.", with: "") ?? "le lien"),
                              systemImage: "arrow.up.right.square")
                    }
                    if HAConfig.isActive, [.watch, .listen].contains(toSee.kind) {
                        SendToTVButton(link: link)
                    }
                }
                if toSee.kind == .watch, let availability {
                    AvailabilityView(availability: availability)
                }
            }
        } footer: {
            if let toSee {
                if toSee.kind.isPlace && toSee.kind != .outing && TaskContact(notes: notes) == nil {
                    Text("Ajoute le lieu (section Lieu) pour le retrouver sur la carte et être prévenu en passant à côté.")
                } else if toSee.end == nil && toSee.start == nil {
                    Text(toSee.kind == .outing
                         ? "Gardée dans Envies, sans relance. Ajoute une période (expo, festival…) pour être prévenu au bon moment."
                         : "Gardée dans Envies › \(toSee.kind.title), sans relance. Une période (film en salle, replay) te préviendra avant la fin.")
                } else {
                    Text("Prévenu à l'ouverture, quelques semaines avant la fin et le dernier week-end (Réglages › Relances › Envies).")
                }
            } else {
                Text("Pour une sortie, un resto, un magasin, un spot photo, un livre, un album, un film : gardé à part, sans relance chaque jour.")
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
            // Pastilles qui défilent : sept types ne tiennent pas dans un sélecteur segmenté.
            FilterChips(selection: $filterRaw,
                        options: [FilterChips.Option(id: "", title: "Tout", symbol: nil)]
                            + ToSee.Kind.allCases.map { FilterChips.Option(id: $0.rawValue, title: $0.shortTitle, symbol: $0.symbol) })
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
        case .restaurant?:
            ContentUnavailableView("Aucun resto à tester", systemImage: ToSee.Kind.restaurant.symbol,
                                   description: Text("Un restaurant ou un bar repéré : touche +, puis ajoute son lieu."))
        case .shop?:
            ContentUnavailableView("Aucun magasin", systemImage: ToSee.Kind.shop.symbol,
                                   description: Text("Une boutique où passer un jour : touche +, puis ajoute son lieu."))
        case .photoSpot?:
            ContentUnavailableView("Aucun spot photo", systemImage: ToSee.Kind.photoSpot.symbol,
                                   description: Text("Un endroit où revenir photographier, avec la bonne lumière ou la bonne saison."))
        }
    }
}

/// Où regarder en France (TMDB, données JustWatch) : l'œuvre trouvée, puis les plateformes par mode.
struct AvailabilityView: View {
    let availability: Availability

    var body: some View {
        if let status = availability.status {
            Label(status == "ambigu" ? "Plusieurs œuvres de ce nom : précise l'année dans le titre (ex. « Dune (2021) »)."
                  : "Introuvable sur TMDB.", systemImage: "questionmark.circle")
                .font(.subheadline).foregroundStyle(.secondary)
        } else {
            HStack(alignment: .top, spacing: 12) {
                if let poster = availability.poster {
                    AsyncImage(url: poster) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.secondary.opacity(0.15)
                    }
                    .frame(width: 48, height: 72)
                    .clipShape(.rect(cornerRadius: 6))
                    .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    if let title = availability.title {
                        Text([title, availability.year.map(String.init)].compactMap { $0 }.joined(separator: " · "))
                            .font(.subheadline.weight(.semibold))
                    }
                    line("En abonnement", availability.subscription)
                    line("Gratuit", availability.free)
                    line("En location", availability.rent)
                    line("À l'achat", availability.buy)
                    if availability.subscription.isEmpty && availability.free.isEmpty
                        && availability.rent.isEmpty && availability.buy.isEmpty {
                        Text("Aucune plateforme connue en France pour l'instant.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text("Disponibilités : JustWatch, via TMDB").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder private func line(_ label: String, _ providers: [Availability.Provider]) -> some View {
        if !providers.isEmpty {
            Text("\(label) : " + providers.map(\.name).joined(separator: ", "))
                .font(.subheadline)
        }
    }
}

/// « Sur la TV » : ouvre le lien sur le Freebox Player Pop par Home Assistant, avec un retour visible.
struct SendToTVButton: View {
    let link: URL
    @State private var sending = false
    @State private var outcome: TVRemote.Outcome?

    var body: some View {
        Button {
            sending = true
            outcome = nil
            Task {
                outcome = await TVRemote.send(link)
                sending = false
            }
        } label: {
            HStack {
                Label("Sur la TV", systemImage: "tv")
                Spacer()
                if sending {
                    ProgressView()
                } else if let outcome {
                    Text(Self.text(outcome))
                        .font(.subheadline)
                        .foregroundStyle(outcome == .sent ? Color.secondary : Color.red)
                }
            }
        }
        .disabled(sending)
    }

    static func text(_ outcome: TVRemote.Outcome) -> String {
        switch outcome {
        case .sent: "Envoyé à la TV"
        case .unreachable: "TV injoignable"
        case .failed(let message): message
        }
    }
}

/// Filtre en pastilles qui défilent (comme les catégories de Plans) : pour plus de cinq choix.
struct FilterChips: View {
    struct Option: Identifiable {
        let id: String
        let title: String
        let symbol: String?
    }

    @Binding var selection: String
    let options: [Option]
    /// Sur la carte : fond en matériau (lisible sur le plan) et rangée coupée à son cadre.
    var overMap = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options) { option in
                    let selected = option.id == selection
                    Button {
                        withAnimation(.snappy) { selection = option.id }
                    } label: {
                        // Pas de `Label` : dans une liste, il réserve une colonne d'icône trop large.
                        HStack(spacing: 5) {
                            if let symbol = option.symbol { Image(systemName: symbol).imageScale(.small) }
                            Text(option.title)
                        }
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12)
                        .frame(minHeight: 34)
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .background(in: .capsule)
                        .backgroundStyle(selected ? AnyShapeStyle(Color.accentColor)
                                         : overMap ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(Color.secondary.opacity(0.14)))
                        .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.vertical, 6)
        }
        .scrollClipDisabled(!overMap)
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
