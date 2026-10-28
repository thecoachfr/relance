import PhotosUI
import UniformTypeIdentifiers
import SwiftUI

/// Section « Liste » de la fiche (P9-G1) : articles cochables d'une tâche (courses, valise, matériel…).
/// Toucher coche ; la saisie en bas ajoute un article et reste prête pour le suivant. Tout coché : la tâche passe
/// en « Fait », avec « Annuler ». Seulement en mode Home Assistant (le champ n'existe pas dans Google Tasks).
struct ListeSection: View {
    @Environment(TaskStore.self) private var store
    let item: TaskItem
    @State private var saisie = ""
    @State private var terminee = false
    @FocusState private var saisieActive: Bool

    var body: some View {
        if HAConfig.isActive {
            if let liste = item.liste {
                Section {
                    ForEach(liste.recettesAPreparer, id: \.self) { titre in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(titre)
                                Text("Claude prépare la liste des ingrédients…").font(.footnote).foregroundStyle(.secondary)
                            }
                        } icon: {
                            ProgressView()
                        }
                        .accessibilityElement(children: .combine)
                    }
                    // Photos de produits pas encore lues par Claude (P9-R).
                    ForEach(0..<liste.photosALire, id: \.self) { _ in
                        Label {
                            Text("Claude lit la photo…")
                        } icon: {
                            ProgressView()
                        }
                    }
                    ForEach(liste.articles) { article in
                        ligne(article)
                    }
                    .onDelete { store.removeArticles(at: $0, of: item) }
                    .onMove { store.moveArticles(from: $0, to: $1, of: item) }
                    TextField("Ajouter un article", text: $saisie)
                        .focused($saisieActive)
                        .submitLabel(.next)
                        .onSubmit(ajouter)
                    PhotoDeCoursesBouton(item: item)
                } header: {
                    HStack {
                        Text("Liste")
                        Spacer()
                        if !liste.articles.isEmpty {
                            Text("\(liste.cochés)/\(liste.articles.count)")
                                .monospacedDigit()
                                .accessibilityLabel("\(liste.cochés) cochés sur \(liste.articles.count)")
                        }
                    }
                } footer: {
                    if terminee, item.isCompleted {
                        HStack {
                            Text("Tout est coché : tâche faite.")
                            Button("Annuler") {
                                store.reopen(item)
                                terminee = false
                            }
                            .font(.footnote.bold())
                        }
                    } else if liste.aDesProposes {
                        HStack {
                            Text("✦ Lus sur la photo par Claude : retire ceux qui ne vont pas.")
                            Button("Tout garder") { store.garderProposes(of: item) }
                                .font(.footnote.bold())
                        }
                    } else if liste.photosEnEchec > 0 {
                        Text("Une photo n'a pas pu être lue : réessaie avec une photo plus nette.")
                    } else if liste.proposee {
                        Text("Liste proposée par Claude d'après une recette classique, quantités indicatives : ajuste-la.")
                    } else if liste.articles.isEmpty {
                        Text("Quand tout est coché, la tâche passe en « Fait ».")
                    }
                }
            } else if item.toSee == nil {
                // Pas sur une envie (resto, film…) : la liste y serait du bruit.
                Section {
                    Button("Ajouter une liste", systemImage: "checklist") {
                        store.setListe(TacheHA.Liste(), of: item)
                        saisieActive = true
                    }
                    PhotoDeCoursesBouton(item: item)
                }
            }
        }
    }

    private func ligne(_ article: TacheHA.Liste.Article) -> some View {
        ArticleRow(article: article) {
            terminee = store.toggleArticle(id: article.id, of: item)
        } onEdit: { saisie in
            store.editArticle(id: article.id, saisie: saisie, of: item)
        }
    }

    private func ajouter() {
        store.addArticle(saisie, to: item)
        saisie = ""
        saisieActive = true
    }
}

/// Une ligne de la liste, comme dans Rappels : le rond coche, le texte se modifie sur place (« 6 œufs » garde la
/// quantité ; effacer le texte retire l'article).
private struct ArticleRow: View {
    let article: TacheHA.Liste.Article
    var onToggle: () -> Void
    var onEdit: (String) -> Void
    @State private var texte = ""
    @FocusState private var actif: Bool

    private var saisie: String {
        [article.quantite, article.texte].compactMap { $0 }.joined(separator: " ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: article.coche ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(article.coche ? Color.accentColor : Color.secondary)
                    .frame(minWidth: 28, minHeight: 28)
                    .contentShape(.rect)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(article.coche ? "Décocher \(article.texte)" : "Cocher \(article.texte)")
            TextField("Article", text: $texte)
                .focused($actif)
                .overlay(alignment: .trailing) {
                    // Lu sur une photo, pas encore gardé (P9-R).
                    if article.propose {
                        Image(systemName: "sparkles").foregroundStyle(.secondary).accessibilityLabel("Proposé par Claude")
                    }
                }
                .strikethrough(article.coche && !actif)
                .foregroundStyle(article.coche && !actif ? .secondary : .primary)
                .submitLabel(.done)
                .onSubmit { onEdit(texte) }
                .onChange(of: actif) { if !actif, texte != saisie { onEdit(texte) } }
        }
        .onAppear { texte = saisie }
        .onChange(of: saisie) { if !actif { texte = saisie } }
    }
}

// MARK: - Photo de produits (P9-R)

/// « Lire des produits sur une photo » : photo prise ou choisie, jointe à la tâche et notée à lire ; la vigie propose
/// les articles lus par Claude (à garder ou retirer).
struct PhotoDeCoursesBouton: View {
    @Environment(TaskStore.self) private var store
    let item: TaskItem
    @State private var choix: [PhotosPickerItem] = []
    @State private var appareil = false
    @State private var enCours = false
    @State private var erreur: String?

    var body: some View {
        Menu {
            #if os(iOS)
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Prendre une photo", systemImage: "camera") { appareil = true }
            }
            #endif
            PhotosPicker(selection: $choix, maxSelectionCount: 4, matching: .images) {
                Label("Choisir dans Photos", systemImage: "photo.on.rectangle")
            }
        } label: {
            HStack {
                Label("Lire des produits sur une photo", systemImage: "camera.viewfinder")
                if enCours { Spacer(); ProgressView() }
            }
        }
        .disabled(enCours)
        .onChange(of: choix) {
            let elements = choix
            choix = []
            Task {
                var images: [Data] = []
                for e in elements { if let d = try? await e.loadTransferable(type: Data.self) { images.append(d) } }
                await joindre(images)
            }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $appareil) {
            AppareilPhoto { image in
                appareil = false
                if let data = image?.jpegData(compressionQuality: 0.9) { Task { await joindre([data]) } }
            }
            .ignoresSafeArea()
        }
        #endif
        if let erreur { Text(erreur).font(.footnote).foregroundStyle(.red) }
    }

    /// Photo réduite hors du fil principal, jointe et notée à lire, puis envoyée tout de suite.
    private func joindre(_ images: [Data]) async {
        guard !images.isEmpty else { return }
        enCours = true
        erreur = nil
        let pieces = await Task.detached(priority: .userInitiated) {
            images.enumerated().compactMap { i, data in
                try? PiecesJointes.preparer(data, nom: "Produits \(i + 1).jpg", type: .jpeg, source: "photo")
            }
        }.value
        enCours = false
        if pieces.count < images.count { erreur = "Une photo n'a pas pu être préparée." }
        store.ajouterPhotosDeCourses(pieces, to: item)
        Task { await store.sync() }
    }
}

#if os(iOS)
/// Appareil photo du système (UIImagePickerController), pour photographier des produits.
struct AppareilPhoto: UIViewControllerRepresentable {
    var fini: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let vue = UIImagePickerController()
        vue.sourceType = .camera
        vue.delegate = context.coordinator
        return vue
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinateur { Coordinateur(fini: fini) }

    final class Coordinateur: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let fini: (UIImage?) -> Void
        init(fini: @escaping (UIImage?) -> Void) { self.fini = fini }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            fini(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { fini(nil) }
    }
}
#endif
