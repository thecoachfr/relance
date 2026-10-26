import SwiftUI

/// Interrupteur « Pour info, sans action » (P9-P) de la saisie rapide et de la fiche.
struct PourInfoSection: View {
    @Binding var notes: String
    /// Activer l'info : une date (aujourd'hui si aucune), pas d'heure.
    var onEnable: () -> Void = {}

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { PourInfo.est(notes) }, set: { on in
                notes = PourInfo.notes(notes, actif: on)
                if on { onEnable() }
            })) {
                Label("Pour info, sans action", systemImage: "megaphone")
            }
        } footer: {
            Text("Aucune relance, rien à cocher : annoncé dans le résumé du matin et affiché le jour même, puis il disparaît. Avec « Répéter », il revient tout seul.")
        }
    }
}

/// « Pour info » en tête d'À faire (iPhone, iPad, Mac) : les infos du jour, une ligne chacune, sans bouton « Fait » ;
/// celles à venir repliées dessous, pour les retrouver et les modifier.
struct PourInfoAujourdhuiSection: View {
    /// Les infos actives (non faites), dans n'importe quel ordre.
    let infos: [TaskItem]
    let now: Date
    var onSelect: (TaskItem) -> Void = { _ in }
    @State private var aVenirOuvert = false

    private var duJour: [TaskItem] { infos.filter { $0.pourInfoDuJour(now: now) } }
    private var aVenir: [TaskItem] {
        let debut = Calendar.current.startOfDay(for: now)
        return infos.filter { !$0.pourInfoDuJour(now: now) && ($0.dueDay ?? .distantPast) >= debut }
            .sorted { ($0.dueDay ?? .distantFuture) < ($1.dueDay ?? .distantFuture) }
    }

    var body: some View {
        if !infos.isEmpty {
            Section("Pour info") {
                ForEach(duJour) { item in ligne(item, detail: "Aujourd'hui") }
                if !aVenir.isEmpty {
                    DisclosureGroup("À venir (\(aVenir.count))", isExpanded: $aVenirOuvert) {
                        ForEach(aVenir) { item in
                            ligne(item, detail: item.dueDay.map { $0.formatted(.dateTime.weekday(.wide).day().month(.wide)) } ?? "")
                        }
                    }
                }
            }
            .selectionDisabled()
        }
    }

    private func ligne(_ item: TaskItem, detail: String) -> some View {
        Button { onSelect(item) } label: {
            LabeledContent {
                Text(detail)
            } label: {
                Label(item.title, systemImage: "megaphone")
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Ouvre la fiche")
    }
}
