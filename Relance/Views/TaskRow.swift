import SwiftUI

struct TaskRow: View {
    /// Ligne sélectionnée (Mac, iPad) : sur le fond d'accent, le rouge et le gris ne se lisent plus.
    @Environment(\.backgroundProminence) private var prominence
    let item: TaskItem
    var now: Date = .now
    /// Sélectionnée dans la liste du Mac (où `backgroundProminence` ne suit pas la sélection).
    var isSelected = false
    /// Rond à cocher, comme dans Rappels : le geste de balayage seul ne se découvre pas.
    var onDone: ((TaskItem) -> Void)?
    /// Mi-hauteur des majuscules du titre au-dessus de sa ligne de base, lue dans la police du système
    /// (17 pt sur iPhone, 13 pt sur Mac, et selon la taille du texte choisie).
    @Environment(\.dynamicTypeSize) private var typeSize
    private var capCenter: CGFloat {
        #if os(macOS)
        NSFont.preferredFont(forTextStyle: .body).capHeight / 2
        #else
        UIFont.preferredFont(forTextStyle: .body).capHeight / 2
        #endif
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if let onDone {
                // Le rond ne compte pas dans la hauteur de la ligne : en grande taille, il ajoutait de l'espace
                // au-dessus du titre. Il est posé sur la ligne de base du titre, puis centré sur ses majuscules.
                Color.clear
                    .frame(width: 44, height: 1)
                    .overlay {
                        Button { onDone(item) } label: {
                            PriorityCircle(priority: item.priority, late: item.isOverdue(now: now))
                                .font(Self.circleFont)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .pointerHighlight()
                        .offset(y: -capCenter)
                        .accessibilityLabel("Marquer comme faite")
                    }
                    .padding(.leading, -10)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title.isEmpty ? "Sans titre" : item.title)
                    .font(.body)
                    .foregroundStyle(item.priority == .low ? .secondary : .primary)
                // Étiquette sous le statut, comme les tags dans Rappels : rien n'est jamais coupé.
                statusLabel
                listeLabel
                if item.category != nil || !item.tags.isEmpty {
                    HStack(spacing: 8) {
                        if let category = item.category { CategoryChip(name: category, onSelection: isSelected) }
                        TagsText(tags: item.tags)
                    }
                } else if !item.isCompleted {
                    // La routine met toujours une catégorie : sans catégorie, la tâche attend son tri.
                    HStack(spacing: 3) {
                        Image(systemName: "sparkles").imageScale(.small)
                        Text("Tri en attente")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("En attente du tri par Claude")
                }
            }
            .accessibilityElement(children: .combine)
            // La priorité ne se voit qu'au rond : VoiceOver la dit en clair.
            .accessibilityValue(item.priority == .normal ? "" : "Priorité \(item.priority.rawValue)")
        }
        // La police réserve de l'espace au-dessus des majuscules : on le retire en haut pour que le bloc
        // paraisse centré (autant d'air au-dessus du titre que sous la dernière ligne).
        // Sur Mac, la liste n'ajoute pas de marge autour des lignes : on lui en donne une.
        #if os(macOS)
        .padding(.top, 4)
        .padding(.bottom, 8)
        #else
        .padding(.top, -2)
        .padding(.bottom, 2)
        #endif
    }

    /// Rond à la taille de celui de Rappels : plus petit sur Mac, où le texte fait 13 pt.
    private static var circleFont: Font {
        #if os(macOS)
        .title3
        #else
        .title2
        #endif
    }

    /// Sans période : la note (spot photo), sinon le lieu s'il dit autre chose que le titre, sinon le site du
    /// lien (vidéo, album), sinon le type.
    static func envieCaption(_ item: TaskItem, _ toSee: ToSee) -> String {
        if let note = toSee.note { return note }
        // À regarder : là où c'est inclus dans mes abonnements, sinon la première plateforme d'abonnement.
        if toSee.kind == .watch, let availability = item.availability {
            if let included = Subscriptions.included(in: availability).first { return "Inclus · " + included.name }
            if let first = availability.subscription.first { return "Sur " + first.name }
        }
        if toSee.kind.isPlace, let place = TaskContact(notes: item.notes) {
            let name = place.name.lowercased()
            if !item.title.lowercased().contains(name) && !name.contains(item.title.lowercased()) { return place.name }
            if let address = place.address { return address }
            return toSee.kind.title
        }
        return ToSee.link(in: item.notes)?.host()?.replacingOccurrences(of: "www.", with: "") ?? toSee.kind.title
    }

    @ViewBuilder private var statusLabel: some View {
        if let toSee = item.toSee, item.dueDay == nil {
            HStack(spacing: 5) {
                Image(systemName: toSee.kind.symbol).imageScale(.small)
                Text(toSee.start == nil && toSee.end == nil ? Self.envieCaption(item, toSee) : toSee.text(now: now))
            }
            .font(.subheadline)
            .foregroundStyle(toSee.isOver(now: now) ? Color.secondary : toSee.text(now: now).hasPrefix("Plus que") || toSee.text(now: now) == "Dernier jour" ? Color.orange : Color.secondary)
        } else if let status {
            // Pas de `Label` : dans une liste, il réserve une colonne d'icône trop large.
            HStack(spacing: 5) {
                Image(systemName: status.symbol).imageScale(.small)
                Text(status.text)
                if let rule = Recurrence(notes: item.notes) {
                    Image(systemName: "repeat").imageScale(.small)
                        .accessibilityLabel(rule.text)
                }
            }
            .font(.subheadline)
            .foregroundStyle(isSelected || prominence == .increased ? .secondary : status.color)
        }
    }

    /// Liste d'articles (P9-G1) : « 3/12 », comme une sous-tâche de Rappels.
    @ViewBuilder private var listeLabel: some View {
        if let liste = item.liste, !liste.articles.isEmpty {
            HStack(spacing: 5) {
                Image(systemName: "checklist").imageScale(.small)
                Text("\(liste.cochés)/\(liste.articles.count)").monospacedDigit()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Liste : \(liste.cochés) cochés sur \(liste.articles.count)")
        }
    }

    /// Même texte que dans les widgets et l'activité en direct (`DueText`).
    private var status: (text: String, symbol: String, color: Color)? {
        guard let due = item.dueInstant() else { return nil }
        let text = DueText.long(due: due, hasTime: item.dueMinutes != nil, now: now)
        if item.isOverdue(now: now) { return (text, "clock.fill", .red) }
        let symbol = Calendar.current.isDateInToday(item.dueDay!) ? "clock" : "calendar"
        return (text, symbol, .secondary)
    }
}

/// Actions communes aux listes : glisser à droite = Fait, à gauche = Reporter, appui long = menu.
struct TaskActions: ViewModifier {
    @Environment(TaskStore.self) private var store
    let item: TaskItem
    var onDone: (TaskItem) -> Void
    var onEdit: (TaskItem) -> Void

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture { onEdit(item) }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button("Fait", systemImage: "checkmark") { onDone(item) }
                    .tint(.green)
                if item.priority == .urgent {
                    Button("Normale", systemImage: "minus") { store.setPriority(item, .normal) }
                        .tint(.gray)
                } else {
                    Button("Urgente", systemImage: "exclamationmark") { store.setPriority(item, .urgent) }
                        .tint(.red)
                }
            }
            .swipeActions(edge: .trailing) {
                Button("Demain", systemImage: "sunrise") { store.moveToTomorrow(item) }
                    .tint(.indigo)
                Button("1 h", systemImage: "clock") { store.snooze(item, until: .now.addingTimeInterval(3600)) }
                    .tint(.orange)
            }
            .contextMenu {
                Button("Fait", systemImage: "checkmark") { onDone(item) }
                Button("Dans 1 h", systemImage: "clock") { store.snooze(item, until: .now.addingTimeInterval(3600)) }
                Button("Demain matin", systemImage: "sunrise") { store.moveToTomorrow(item) }
                Picker("Priorité", systemImage: "exclamationmark.circle",
                       selection: Binding(get: { item.priority }, set: { store.setPriority(item, $0) })) {
                    ForEach(TaskPriority.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
                }
                .pickerStyle(.menu)
                Button("Modifier", systemImage: "pencil") { onEdit(item) }
                Button("Supprimer", systemImage: "trash", role: .destructive) { store.delete(item) }
            }
            .accessibilityAction(named: "Fait") { onDone(item) }
            .accessibilityAction(named: "Reporter à demain") { store.moveToTomorrow(item) }
            .accessibilityAction(named: item.priority == .urgent ? "Priorité normale" : "Marquer urgente") {
                store.setPriority(item, item.priority == .urgent ? .normal : .urgent)
            }
    }
}

extension View {
    func taskActions(_ item: TaskItem, onDone: @escaping (TaskItem) -> Void, onEdit: @escaping (TaskItem) -> Void) -> some View {
        modifier(TaskActions(item: item, onDone: onDone, onEdit: onEdit))
    }
}
