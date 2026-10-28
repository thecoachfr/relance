import SwiftUI

/// Ligne « Répéter » de l'échéance : « Jamais » ou la règle (« Tous les mois le 5 »).
struct RecurrenceRow: View {
    @Binding var notes: String
    /// Jour d'échéance : sert de point de départ aux choix (le 5 si la tâche est le 5…).
    let day: Date

    var body: some View {
        NavigationLink {
            RecurrenceView(notes: $notes, day: day)
        } label: {
            LabeledContent {
                Text(Recurrence(notes: notes)?.text ?? "Jamais")
            } label: {
                // Une icône par ligne de l'échéance, comme Durée et Où la faire (28/10).
                Label("Répéter", systemImage: "repeat")
            }
        }
    }
}

/// Choix de la répétition. À chaque « Fait », Aiguillage crée la tâche suivante.
struct RecurrenceView: View {
    @Binding var notes: String
    let day: Date

    private enum Kind: String, CaseIterable, Identifiable {
        case never = "Jamais", daily = "Tous les jours", weekly = "Toutes les semaines", monthly = "Tous les mois",
             yearly = "Tous les ans", afterDone = "Après avoir été faite"
        var id: String { rawValue }
    }

    private var rule: Recurrence? { Recurrence(notes: notes) }
    private var calendar: Calendar { .current }

    private var kind: Kind {
        switch rule {
        case nil: .never
        case .daily?: .daily
        case .weekly?: .weekly
        case .monthlyDay?, .monthlyWeekday?: .monthly
        case .yearly?: .yearly
        case .afterDone?: .afterDone
        }
    }

    private func set(_ rule: Recurrence?) { notes = Recurrence.notes(notes, setting: rule) }

    /// Règle par défaut d'un type, calée sur le jour d'échéance.
    private func defaultRule(_ kind: Kind) -> Recurrence? {
        let c = calendar.dateComponents([.day, .month, .weekday], from: day)
        return switch kind {
        case .never: nil
        case .daily: .daily(every: 1)
        case .weekly: .weekly(every: 1, weekdays: [c.weekday!])
        case .monthly: .monthlyDay(every: 1, day: c.day!)
        case .yearly: .yearly(month: c.month!, day: c.day!)
        case .afterDone: .afterDone(amount: 1, unit: .month)
        }
    }

    var body: some View {
        Form {
            Section {
                Picker("Répéter", selection: Binding(get: { kind }, set: { set(defaultRule($0)) })) {
                    ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } footer: {
                Text(kind == .afterDone
                     ? "La suivante part du jour où tu coches : pratique pour un filtre ou une sauvegarde, même si tu es en retard."
                     : "À chaque « Fait », Aiguillage crée la suivante, avec la même heure, catégorie, priorité et lieu.")
            }
            if let rule { details(rule) }
        }
        .navigationTitle("Répéter")
        .inlineNavigationTitle()
    }

    @ViewBuilder private func details(_ rule: Recurrence) -> some View {
        switch rule {
        case .daily(let n):
            Section { Stepper(n == 1 ? "Tous les jours" : "Tous les \(n) jours", value: binding(n) { .daily(every: $0) }, in: 1...30) }
        case .weekly(let n, let days):
            Section {
                Stepper(n == 1 ? "Toutes les semaines" : "Toutes les \(n) semaines",
                        value: binding(n) { .weekly(every: $0, weekdays: days) }, in: 1...12)
                WeekdayPicker(selection: Binding(get: { days }, set: { set(.weekly(every: n, weekdays: $0.isEmpty ? days : $0)) }))
            }
        case .monthlyDay(let n, _), .monthlyWeekday(let n, _, _):
            Section {
                Stepper(n == 1 ? "Tous les mois" : "Tous les \(n) mois", value: binding(n) { monthly(rule, every: $0) }, in: 1...12)
                Picker("Quel jour", selection: Binding(get: { monthlyChoice(rule) }, set: { set(monthlyRule($0, every: n)) })) {
                    ForEach(MonthlyChoice.allCases, id: \.self) { Text(label($0)).tag($0) }
                }
            }
        case .yearly:
            EmptyView()
        case .afterDone(let amount, let unit):
            Section {
                Stepper("\(amount)", value: binding(amount) { .afterDone(amount: $0, unit: unit) }, in: 1...36)
                Picker("Unité", selection: Binding(get: { unit }, set: { set(.afterDone(amount: amount, unit: $0)) })) {
                    Text("jours").tag(Recurrence.Unit.day)
                    Text("semaines").tag(Recurrence.Unit.week)
                    Text("mois").tag(Recurrence.Unit.month)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(rule.text + ".")
            }
        }
    }

    private func binding(_ value: Int, _ make: @escaping (Int) -> Recurrence) -> Binding<Int> {
        Binding(get: { value }, set: { set(make($0)) })
    }

    // MARK: - Mensuel : le 5, le 2e mardi, le dernier jour

    private enum MonthlyChoice: Hashable, CaseIterable { case dayOfMonth, weekdayOfMonth, lastDay }

    private func monthlyChoice(_ rule: Recurrence) -> MonthlyChoice {
        switch rule {
        case .monthlyDay(_, 0): .lastDay
        case .monthlyWeekday: .weekdayOfMonth
        default: .dayOfMonth
        }
    }

    private func label(_ choice: MonthlyChoice) -> String {
        switch choice {
        case .dayOfMonth: return "Le \(calendar.component(.day, from: day))"
        case .weekdayOfMonth: return String(Recurrence.monthlyWeekday(every: 1, ordinal: ordinal, weekday: weekday).text.dropFirst("Tous les mois ".count))
        case .lastDay: return "Le dernier jour"
        }
    }

    private var weekday: Int { calendar.component(.weekday, from: day) }
    /// 1er, 2e… mardi du mois ; « dernier » au-delà du 4e.
    private var ordinal: Int {
        let n = calendar.component(.weekdayOrdinal, from: day)
        return n > 4 ? -1 : n
    }

    private func monthlyRule(_ choice: MonthlyChoice, every n: Int) -> Recurrence {
        switch choice {
        case .dayOfMonth: .monthlyDay(every: n, day: calendar.component(.day, from: day))
        case .weekdayOfMonth: .monthlyWeekday(every: n, ordinal: ordinal, weekday: weekday)
        case .lastDay: .monthlyDay(every: n, day: 0)
        }
    }

    private func monthly(_ rule: Recurrence, every n: Int) -> Recurrence {
        switch rule {
        case .monthlyDay(_, let d): .monthlyDay(every: n, day: d)
        case .monthlyWeekday(_, let o, let w): .monthlyWeekday(every: n, ordinal: o, weekday: w)
        default: rule
        }
    }
}

/// Jours de la semaine à cocher (L M M J V S D), au moins un.
private struct WeekdayPicker: View {
    @Binding var selection: [Int]
    private let order = [2, 3, 4, 5, 6, 7, 1]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(order, id: \.self) { weekday in
                let on = selection.contains(weekday)
                Button {
                    selection = on ? selection.filter { $0 != weekday } : selection + [weekday]
                } label: {
                    Text(Recurrence.weekdayNames[weekday - 1].prefix(1).uppercased())
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(on ? Color.accentColor : Color.secondary.opacity(0.15), in: .circle)
                        .foregroundStyle(on ? .white : .primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Recurrence.weekdayNames[weekday - 1])
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}
