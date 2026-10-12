import Foundation

/// Journal des derniers déclencheurs de synchro (push de la vigie, ouverture, réveil iOS),
/// affiché dans les réglages pour vérifier que la vigie réveille bien l'app.
nonisolated enum SyncLog {
    struct Entry: Codable, Hashable {
        var date: Date
        var text: String
    }

    private static let key = "syncLog"
    private static let maxEntries = 20

    static func add(_ text: String, at date: Date = .now) {
        var entries = all()
        entries.insert(Entry(date: date, text: text), at: 0)
        if let data = try? JSONEncoder().encode(Array(entries.prefix(maxEntries))) {
            AppGroup.defaults.set(data, forKey: key)
        }
    }

    static func all() -> [Entry] {
        guard let data = AppGroup.defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }
}
