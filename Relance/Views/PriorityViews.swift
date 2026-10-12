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

/// Ce que change la priorité, sous le choix : on comprend pourquoi la choisir.
struct PriorityFooter: View {
    let priority: TaskPriority

    var body: some View {
        switch priority {
        case .urgent: Text("Relancée toutes les 30 minutes jusqu'à ce qu'elle soit faite, même en mode Concentration.")
        case .normal: Text("Relancée à l'heure, une heure après, puis le soir.")
        case .low: Text("Un seul rappel, à l'heure prévue s'il y en a une ; ensuite, seulement le résumé du matin.")
        }
    }
}
