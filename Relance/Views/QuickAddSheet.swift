import SwiftUI

/// Saisie rapide : une phrase, la date est reconnue dedans, des puces pour corriger.
struct QuickAddSheet: View {
    @Environment(TaskStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var day: Date? = Calendar.current.startOfDay(for: .now)
    @State private var hasTime = false
    @State private var time = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now)!
    /// Vrai dès que l'utilisateur touche les réglages : la phrase ne les écrase plus.
    @State private var manual = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Appeler le garage vendredi 15 h", text: $text, axis: .vertical)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(save)
                        .onChange(of: text) { detect() }
                }
                Section("Échéance") {
                    Picker("Jour", selection: dayChoice) {
                        Text("Aujourd'hui").tag(DayChoice.today)
                        Text("Demain").tag(DayChoice.tomorrow)
                        Text("Autre").tag(DayChoice.other)
                        Text("Sans date").tag(DayChoice.none)
                    }
                    .pickerStyle(.segmented)

                    if dayChoice.wrappedValue == .other {
                        DatePicker("Date", selection: Binding(get: { day ?? .now }, set: { day = $0; manual = true }),
                                   in: Calendar.current.startOfDay(for: .now)..., displayedComponents: .date)
                    }
                    if day != nil {
                        Toggle("Heure", isOn: Binding(get: { hasTime }, set: { hasTime = $0; manual = true }))
                        if hasTime {
                            DatePicker("Heure", selection: Binding(get: { time }, set: { time = $0; manual = true }),
                                       displayedComponents: .hourAndMinute)
                        }
                    }
                }
            }
            .navigationTitle("Nouvelle tâche")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter", action: save).disabled(cleanTitle.isEmpty)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
    }

    private enum DayChoice: Hashable { case today, tomorrow, other, none }

    private var dayChoice: Binding<DayChoice> {
        Binding {
            let calendar = Calendar.current
            guard let day else { return .none }
            if calendar.isDateInToday(day) { return .today }
            if calendar.isDateInTomorrow(day) { return .tomorrow }
            return .other
        } set: { choice in
            manual = true
            let today = Calendar.current.startOfDay(for: .now)
            switch choice {
            case .today: day = today
            case .tomorrow: day = Calendar.current.date(byAdding: .day, value: 1, to: today)
            case .other: day = day ?? Calendar.current.date(byAdding: .day, value: 2, to: today)
            case .none: day = nil
            }
        }
    }

    // MARK: - Reconnaissance de la date dans la phrase

    private var detected: (range: Range<String.Index>, date: Date, hasTime: Bool)? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
              let match = detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let date = match.date, let range = Range(match.range, in: text) else { return nil }
        let fragment = text[range]
        let hasTime = fragment.range(of: #"\d{1,2}\s*(h|:)"#, options: .regularExpression) != nil
        return (range, date, hasTime)
    }

    private func detect() {
        guard !manual, let found = detected else { return }
        day = Calendar.current.startOfDay(for: found.date)
        hasTime = found.hasTime
        if found.hasTime { time = found.date }
    }

    private var cleanTitle: String {
        var title = text
        if !manual, let found = detected { title.removeSubrange(found.range) }
        return title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        guard !cleanTitle.isEmpty else { return }
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        store.add(title: cleanTitle, day: day, minutes: hasTime ? (c.hour! * 60 + c.minute!) : nil)
        dismiss()
    }
}
