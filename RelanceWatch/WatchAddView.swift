import SwiftUI

/// Dictée d'une tâche : « appeler le garage vendredi 15 h ». La date est repérée dans la phrase ;
/// sinon on propose Aujourd'hui / Demain / Sans date.
struct WatchAddView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var choice: DayChoice = .today

    private enum DayChoice: String, CaseIterable, Identifiable {
        case today = "Aujourd'hui", tomorrow = "Demain", none = "Sans date"
        var id: String { rawValue }
    }

    var body: some View {
        let match = DateDetection.firstMatch(in: text)
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                // Sur la montre, toucher le champ propose la dictée en premier.
                TextField("Que faut-il faire ?", text: $text)

                if let match {
                    Label(DueText.long(due: dueInstant(match), hasTime: match.hasTime), systemImage: "calendar")
                        .font(.footnote).foregroundStyle(.secondary)
                } else if !text.isEmpty {
                    Picker("Échéance", selection: $choice) {
                        ForEach(DayChoice.allCases) { Text($0.rawValue).tag($0) }
                    }
                }

                Button("Ajouter") { save(match) }
                    .buttonStyle(.borderedProminent)
                    .disabled(DateDetection.title(of: text, removing: match).isEmpty)
            }
        }
        .navigationTitle("Nouvelle tâche")
    }

    /// Même convention que l'iPhone : sans heure, l'échéance est la fin du jour.
    private func dueInstant(_ match: DateDetection.Match) -> Date {
        let calendar = Calendar.current
        if match.hasTime { return match.date }
        return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: match.date))!
    }

    private func save(_ match: DateDetection.Match?) {
        let title = DateDetection.title(of: text, removing: match)
        guard !title.isEmpty else { return }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        if let match {
            store.add(title: title, due: match.hasTime ? match.date : calendar.startOfDay(for: match.date), hasTime: match.hasTime)
        } else {
            switch choice {
            case .today: store.add(title: title, due: today, hasTime: false)
            case .tomorrow: store.add(title: title, due: calendar.date(byAdding: .day, value: 1, to: today), hasTime: false)
            case .none: store.add(title: title, due: nil, hasTime: false)
            }
        }
        dismiss()
    }
}
