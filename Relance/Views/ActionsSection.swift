import SwiftUI

/// Section « Actions » de la fiche (P9-D1) : ce que la tâche déclenche, qui l'exécute et où elle en est.
/// Les actions « sur l'appareil » (ouvrir le lien, envoyer à la TV) s'exécutent au toucher ; celles de la vigie
/// ou d'une routine s'affichent avec leur état. L'ajout à la playlist Spotify fait par la vigie (D4) s'y montre aussi.
struct ActionsSection: View {
    @Environment(TaskStore.self) private var store
    @Environment(\.openURL) private var openURL
    let item: TaskItem
    /// Lien de la tâche (envie, sinon premier lien des notes) : paramètre des nouvelles actions.
    let lien: URL?
    @State private var enCours: String?

    var body: some View {
        let actions = item.actions
        // Ancienne note de la vigie (D4, avant les recettes) : seulement si l'action n'existe pas.
        let playlist = actions.contains(where: { $0.type == "playlist_spotify" }) ? nil
            : PlaylistNote(item.envieRaw.flatMap { try? JSONDecoder().decode(TacheHA.Envie.self, from: Data($0.utf8)) })
        if !actions.isEmpty || playlist != nil || lien != nil || HAConfig.isActive {
            Section {
                if let playlist {
                    LabeledContent {
                        Text(playlist.texte).foregroundStyle(playlist.ok ? Color.secondary : Color.red)
                    } label: {
                        Label("Playlist « À écouter »", systemImage: "music.note.list")
                    }
                    .accessibilityElement(children: .combine)
                }
                ForEach(actions) { action in
                    ligne(action)
                        .swipeActions { supprimer(action) }
                        .contextMenu { supprimer(action) }
                }
                Menu {
                    if HAConfig.isActive, !actions.contains(where: { $0.type == TacheHA.Action.rappelMaison }) {
                        Button("Me le rappeler à la maison", systemImage: "house") {
                            store.addAction(.aLaMaison(), to: item)
                        }
                    }
                    if HAConfig.isActive, !store.pieces.isEmpty {
                        // Bermuda sait dans quelle pièce est Alexandre : rappel en y entrant.
                        Menu("Me le rappeler dans…", systemImage: "figure.walk.arrival") {
                            ForEach(store.pieces, id: \.self) { piece in
                                Button(piece) { store.addAction(.dans(piece), to: item) }
                            }
                        }
                    }
                    if let lien {
                        if !actions.contains(where: { $0.type == TacheHA.Action.ouvrirLien }) {
                            Button("Ouvrir le lien", systemImage: "link") {
                                store.addAction(.surAppareil(TacheHA.Action.ouvrirLien, lien: lien), to: item)
                            }
                        }
                        if !actions.contains(where: { $0.type == TacheHA.Action.surTV }) {
                            Button("Sur la TV", systemImage: "tv") {
                                store.addAction(.surAppareil(TacheHA.Action.surTV, lien: lien), to: item)
                            }
                        }
                    }
                } label: {
                    Label("Ajouter une action", systemImage: "plus.circle")
                }
            } header: {
                Text("Actions")
            } footer: {
                if actions.contains(where: { $0.type == TacheHA.Action.rappelMaison || $0.type == TacheHA.Action.rappelPiece }) {
                    Text("Home Assistant te prévient quand tu rentres ou entres dans la pièce, une fois par jour, jusqu'à ce que la tâche soit faite.")
                } else if !actions.isEmpty {
                    Text("Touche une action pour la lancer. Elles se synchronisent avec tes autres appareils.")
                }
            }
        }
    }

    @ViewBuilder private func ligne(_ action: TacheHA.Action) -> some View {
        let contenu = HStack {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.titre).foregroundStyle(.primary)
                    Text(action.etatTexte).font(.subheadline)
                        .foregroundStyle(action.etat == "echec" ? Color.red : Color.secondary)
                }
            } icon: {
                Image(systemName: action.symbole)
            }
            Spacer()
            if enCours == action.id { ProgressView() }
        }
        if action.auToucher, action.lien != nil {
            Button { executer(action) } label: { contenu }
                .disabled(enCours != nil)
                .accessibilityHint("Lance l'action")
        } else {
            contenu.accessibilityElement(children: .combine)
        }
    }

    private func supprimer(_ action: TacheHA.Action) -> some View {
        Button("Supprimer", systemImage: "trash", role: .destructive) {
            store.removeAction(id: action.id, from: item)
        }
    }

    private func executer(_ action: TacheHA.Action) {
        guard let lien = action.lien else { return }
        switch action.type {
        case TacheHA.Action.ouvrirLien:
            openURL(lien)
            store.markAction(id: action.id, of: item, etat: "faite", resultat: nil)
        case TacheHA.Action.surTV:
            enCours = action.id
            Task {
                let outcome = await TVRemote.send(lien)
                store.markAction(id: action.id, of: item, etat: outcome == .sent ? "faite" : "echec",
                                 resultat: SendToTVButton.text(outcome))
                enCours = nil
            }
        default:
            break
        }
    }
}
