import SwiftUI

/// Priorité d'une tâche : elle règle l'insistance des relances (voir `ReminderPlanner`).
/// Google Tasks n'a pas de priorité : elle est rangée dans les notes (« ❗ Urgente », « 🔽 Basse ») ;
/// Normale, le cas par défaut, n'écrit rien.
nonisolated enum TaskPriority: String, CaseIterable, Identifiable, Sendable, Codable {
    case urgent = "Urgente"
    case normal = "Normale"
    case low = "Basse"

    var id: String { rawValue }

    static let urgentMarker = "❗"
    static let lowMarker = "🔽"

    var marker: String? {
        switch self {
        case .urgent: Self.urgentMarker
        case .normal: nil
        case .low: Self.lowMarker
        }
    }

    var symbol: String {
        switch self {
        case .urgent: "exclamationmark"
        case .normal: "minus"
        case .low: "arrow.down"
        }
    }

    var color: Color {
        switch self {
        case .urgent: .red
        case .normal: .secondary
        case .low: .gray
        }
    }

    /// Ordre d'affichage : les urgentes d'abord.
    var rank: Int {
        switch self {
        case .urgent: 0
        case .normal: 1
        case .low: 2
        }
    }

    init?(name: String?) {
        guard let name, let match = Self.allCases.first(where: { $0.rawValue.lowercased() == name.lowercased() }) else { return nil }
        self = match
    }

    // MARK: - Mots dits à Siri ou à Google Home

    /// Les formes négatives d'abord : « pas urgent » ne doit pas être lu comme « urgent ».
    private static let spoken: [(TaskPriority, String)] = [
        (.low, #"(c'est\s+)?pas\s+(press[ée]e?|urgente?)|sans\s+urgence|quand\s+j'ai\s+le\s+temps"#),
        (.urgent, #"(c'est\s+)?(tr[èe]s\s+)?urgente?|en\s+urgence"#),
    ]

    struct Match {
        var priority: TaskPriority
        var range: Range<String.Index>
    }

    /// « appeler le garage urgent », « renouveler le passeport, pas pressé ».
    static func detect(in text: String) -> Match? {
        for (priority, pattern) in spoken {
            if let range = text.range(of: #"\b"# + pattern + #"\b"#, options: [.regularExpression, .caseInsensitive]) {
                return Match(priority: priority, range: range)
            }
        }
        return nil
    }

    /// Le texte sans les mots de priorité, nettoyé.
    static func removing(_ match: Match?, from text: String) -> String {
        guard let match else { return text }
        var text = text
        text.removeSubrange(match.range)
        return text.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }
}

/// Rond à cocher qui porte la priorité : épais et teinté de rouge pour Urgente, en pointillés pour Basse.
/// La priorité se lit au rond, la catégorie reste une pastille : les deux ne se ressemblent plus.
struct PriorityCircle: View {
    let priority: TaskPriority
    /// Normale ou Basse en retard : rond rouge fin (l'urgente garde son rond plein).
    var late = false

    var body: some View {
        switch priority {
        case .urgent:
            Image(systemName: "circle")
                .fontWeight(.heavy)
                .foregroundStyle(Color.red)
                .background(Circle().fill(Color.red.opacity(0.15)).padding(3))
        case .normal:
            Image(systemName: "circle").foregroundStyle(late ? Color.red : Color.gray)
        case .low:
            Image(systemName: "circle.dashed").foregroundStyle(late ? Color.red : Color.gray)
        }
    }
}
