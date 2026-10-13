import SwiftUI

/// Ce que devient le partage : une tâche (par défaut) ou une fiche du mémo de tri.
enum ShareMode: String, CaseIterable, Identifiable {
    case task = "Tâche", memo = "Mémo"
    var id: String { rawValue }
}

/// Une seule entrée « Aiguillage » dans la feuille de partage, avec le choix Tâche / Mémo en haut.
/// (Une seconde extension « Mémo Aiguillage » ne s'affichait pas dans Notes.)
struct ShareRootView: View {
    let original: String
    let memoDraft: (title: String, details: String)
    let onDone: () -> Void
    let onCancel: () -> Void

    @State private var mode = ShareMode.task

    var body: some View {
        switch mode {
        case .task: ShareComposeView(original: original, mode: $mode, onDone: onDone, onCancel: onCancel)
        case .memo: MemoShareView(draft: memoDraft, mode: $mode, onDone: onDone, onCancel: onCancel)
        }
    }
}

/// Sélecteur Tâche / Mémo, à la place du titre de la barre.
struct ShareModePicker: View {
    @Binding var mode: ShareMode

    var body: some View {
        Picker("Ajouter comme", selection: $mode) {
            ForEach(ShareMode.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .fixedSize()
    }
}
