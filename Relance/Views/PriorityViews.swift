import SwiftUI

/// Priorité en texte (là où il n'y a pas de rond à cocher, comme la carte d'À trier).
/// Pas de pastille : elle ressemblerait à une catégorie. Normale n'affiche rien.
struct PriorityChip: View {
    let priority: TaskPriority

    var body: some View {
        if priority != .normal {
            ChipContent(text: priority.rawValue, symbol: priority.symbol)
                .font(.subheadline.weight(priority == .urgent ? .semibold : .regular))
                .foregroundStyle(priority == .urgent ? Color.red : Color.secondary)
                .accessibilityLabel("Priorité \(priority.rawValue)")
        }
    }
}

/// Choix de priorité des formulaires : trois options côte à côte, la différence se lit d'un coup d'œil.
struct PriorityPicker: View {
    @Binding var priority: TaskPriority

    var body: some View {
        Picker("Priorité", selection: $priority) {
            ForEach(TaskPriority.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .accessibilityHint("Une tâche urgente est relancée toutes les 30 minutes ; une tâche basse une seule fois.")
    }
}

/// Ce que change la priorité, sous le choix : le réglage réel (Réglages › Relances), pas un texte figé.
struct PriorityFooter: View {
    @Environment(TaskStore.self) private var store
    let priority: TaskPriority
    /// Relances propres à la tâche : le texte décrit alors ce qui s'applique vraiment.
    var reminders: ReminderOverride?
    /// Sortie réservée (P9-L1) : ses propres rappels, pas ceux de la priorité.
    var isEvent = false

    var body: some View {
        let profile = store.scheduler.settings[priority]
        if isEvent {
            Text("Sortie : rappel une semaine avant, la veille au soir et 2 h avant.")
        } else {
            Text(ReminderSummary.text(for: reminders?.applied(to: profile) ?? profile) + ".")
        }
    }
}
