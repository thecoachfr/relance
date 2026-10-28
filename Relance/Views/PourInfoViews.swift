import SwiftUI

/// « Pour info » en tête d'À faire (iPhone, iPad, Mac) : les infos du jour, une ligne chacune, sans bouton « Fait » ;
/// celles à venir repliées dessous, pour les retrouver et les modifier.
struct PourInfoAujourdhuiSection: View {
    /// Les infos actives (non faites), dans n'importe quel ordre.
    let infos: [TaskItem]
    let now: Date
    var onSelect: (TaskItem) -> Void = { _ in }
    @State private var aVenirOuvert = false

    /// Celles avec une heure d'abord (par heure), puis les autres par titre : même ordre que le Hub.
    private var duJour: [TaskItem] {
        infos.filter { $0.pourInfoDuJour(now: now) }.sorted {
            ($0.dueMinutes ?? Int.max, $0.title.lowercased()) < ($1.dueMinutes ?? Int.max, $1.title.lowercased())
        }
    }
    private var aVenir: [TaskItem] {
        let debut = Calendar.current.startOfDay(for: now)
        return infos.filter { !$0.pourInfoDuJour(now: now) && ($0.dueDay ?? .distantPast) >= debut }
            .sorted { ($0.dueDay ?? .distantFuture) < ($1.dueDay ?? .distantFuture) }
    }

    var body: some View {
        if !infos.isEmpty {
            Section("Pour info") {
                ForEach(duJour) { item in ligne(item, detail: item.heurePourInfo ?? "Aujourd'hui") }
                if !aVenir.isEmpty {
                    DisclosureGroup("À venir (\(aVenir.count))", isExpanded: $aVenirOuvert) {
                        ForEach(aVenir) { item in
                            ligne(item, detail: (item.dueDay.map { $0.formatted(.dateTime.weekday(.wide).day().month(.wide)) } ?? "")
                                  + (item.heurePourInfo.map { " · " + $0 } ?? ""))
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

/// Nature d'une tâche (revue d'ergonomie du 28/10) : une tâche ordinaire, un rappel « pour info » (P9-P) ou une envie.
/// Avant : deux interrupteurs rangés dans « Plus d'options ». Chaque nature ne montre que ses sections.
enum NatureTache: String, CaseIterable, Identifiable {
    case tache = "Tâche", info = "Info", envie = "Envie"
    var id: Self { self }

    init(notes: String) {
        self = ToSee(notes: notes) != nil ? .envie : PourInfo.est(notes) ? .info : .tache
    }

    /// Les notes passées à cette nature (lignes 👀… et 📣 ajoutées ou retirées).
    func notes(_ notes: String, envie kind: ToSee.Kind = .outing) -> String {
        switch self {
        case .tache: PourInfo.notes(ToSee.notes(notes, setting: nil), actif: false)
        case .info: PourInfo.notes(ToSee.notes(notes, setting: nil), actif: true)
        case .envie: ToSee.notes(PourInfo.notes(notes, actif: false), setting: ToSee(notes: notes) ?? ToSee(kind))
        }
    }

    var explication: String? {
        switch self {
        case .tache: nil
        case .info: "Pour info : aucune relance, rien à cocher. Annoncé dans le résumé du matin et affiché le jour même, puis il disparaît. L'heure est facultative, seulement affichée. Avec « Répéter », il revient tout seul."
        // La section Envie, juste dessous, explique déjà où elle est rangée.
        case .envie: nil
        }
    }
}

/// Sélecteur segmenté Tâche · Info · Envie, sous le titre de la fiche et de la saisie rapide.
struct NatureSection: View {
    @Binding var notes: String
    /// Type proposé en passant en envie (celui de l'onglet Envies d'où vient la saisie).
    var kind: ToSee.Kind = .outing
    /// Appelé après un changement de nature (date à poser ou à retirer).
    var onChange: (NatureTache) -> Void = { _ in }

    var body: some View {
        let nature = NatureTache(notes: notes)
        Section {
            Picker("Nature", selection: Binding(get: { nature }, set: { nouvelle in
                notes = nouvelle.notes(notes, envie: kind)
                onChange(nouvelle)
            })) {
                ForEach(NatureTache.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        } footer: {
            if let texte = nature.explication { Text(texte) }
        }
    }
}
