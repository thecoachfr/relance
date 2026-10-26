import Foundation

/// Ce que montre le widget d'une tâche. Partagé avec l'app : elle ne recharge les widgets que si cette liste change
/// (avant : `reloadAllTimelines()` à chaque replanification, ce qui use le budget de rechargements des widgets).
nonisolated struct WidgetTask: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var due: Date
    var hasTime: Bool
    var isUrgent = false
    var category: String?
    /// Liste d'articles (P9-G) : « 3/12 », `nil` sans liste.
    var liste: String?
}

extension WidgetTask {
    /// Les tâches datées à montrer : les Basses restent dans l'app, le widget montre ce qui presse.
    @MainActor static func depuis(_ items: [TaskItem]) -> [WidgetTask] {
        items.filter { !$0.isCompleted && !$0.isTrashed && $0.priority != .low && !$0.estPourInfo }.compactMap { item in
            item.dueInstant().map {
                WidgetTask(id: item.localID.uuidString, title: item.title, due: $0, hasTime: item.dueMinutes != nil,
                           isUrgent: item.priority == .urgent, category: item.category,
                           liste: item.liste.flatMap { $0.articles.isEmpty ? nil : "\($0.cochés)/\($0.articles.count)" })
            }
        }
    }
}
