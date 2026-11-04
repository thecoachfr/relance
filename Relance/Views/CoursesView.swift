import SwiftUI

/// La liste de courses unique (P9-U) : ce qui reste à prendre, filtrable par magasin, et où acheter chaque article.
/// Remplace la fiche pour cette tâche, qui n'a ni date ni « Fait ». Un article ajouté pendant un filtre va à ce magasin.
struct CoursesView: View {
    @Environment(TaskStore.self) private var store
    let item: TaskItem
    /// Identifiant d'un groupe de Mes lieux ; vide : tous les magasins. Mémorisé.
    @AppStorage("coursesFiltre") private var filtre = ""
    @State private var saisie = ""
    @State private var choix: ArticleChoisi?
    @FocusState private var saisieActive: Bool

    private struct ArticleChoisi: Identifiable { let id: String }

    var body: some View {
        let lieux = store.mesLieux
        let liste = item.liste ?? TacheHA.Liste()
        // Supermarchés d'abord : le filtre le plus utile reste visible sans faire défiler.
        let tous = lieux.groupes(de: liste)
        let magasins = tous.filter { $0 == MesLieux.supermarches } + tous.filter { $0 != MesLieux.supermarches }
        // Le dernier article d'un magasin pris : retour à tous les magasins.
        let actif = magasins.contains(filtre) ? filtre : ""
        let aPrendre = actif.isEmpty ? liste.articles.filter { !$0.coche } : lieux.articles(de: liste, dans: actif)
        List {
            if magasins.count > 1 {
                Section { filtres(liste, magasins, actif, lieux) }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            Section {
                ForEach(0..<liste.photosALire, id: \.self) { _ in
                    Label { Text("Claude lit la photo…") } icon: { ProgressView() }
                }
                ForEach(aPrendre) { ligne($0, lieux) }
                    .onDelete { offsets in retirer(offsets.map { aPrendre[$0].id }) }
                TextField("Ajouter un article", text: $saisie)
                    .formFieldWithoutLabel()
                    .focused($saisieActive)
                    .submitLabel(.next)
                    .onSubmit(ajouter)
                PhotoDeCoursesBouton { pieces in
                    store.ajouterPhotosDeCourses(pieces, to: item)
                    Task { await store.sync() }
                }
            } footer: {
                if liste.aDesProposes {
                    HStack {
                        Text("✦ Lus sur la photo par Claude : retire ceux qui ne vont pas.")
                        Button("Tout garder") { store.garderProposes(of: item) }
                            .font(.footnote.bold())
                    }
                } else if liste.photosEnEchec > 0 {
                    Text("Une photo n'a pas pu être lue : réessaie avec une photo plus nette.")
                } else if liste.articles.isEmpty {
                    Text("Claude choisit où acheter chaque article ; tu peux changer son choix, il le retient.")
                }
            }
            let pris = liste.articles.filter { $0.coche && (actif.isEmpty || lieux.groupes(de: $0).contains(actif)) }
            if !pris.isEmpty {
                Section {
                    ForEach(pris) { ligne($0, lieux) }
                        .onDelete { offsets in retirer(offsets.map { pris[$0].id }) }
                } header: {
                    Text("Pris")
                } footer: {
                    Text("Retirés au bout de 24 h. Décoche pour annuler.")
                }
            }
        }
        .navigationTitle("Courses")
        .inlineNavigationTitle()
        .sheet(item: $choix) { OuAcheterView(item: item, articleID: $0.id) }
    }

    private func filtres(_ liste: TacheHA.Liste, _ magasins: [String], _ actif: String, _ lieux: MesLieux) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                bouton("Tous", liste.aPrendre.count, actif.isEmpty) { filtre = "" }
                ForEach(magasins, id: \.self) { id in
                    bouton(lieux.nom(id), lieux.articles(de: liste, dans: id).count, actif == id) { filtre = id }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func bouton(_ nom: String, _ n: Int, _ actif: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(nom)
                Text("\(n)").monospacedDigit().foregroundStyle(actif ? Color.white.opacity(0.85) : .secondary)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(actif ? Color.white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(actif ? Color.accentColor : Color.secondary.opacity(0.15), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(nom), \(n) à prendre")
        .accessibilityAddTraits(actif ? .isSelected : [])
    }

    private func ligne(_ article: TacheHA.Liste.Article, _ lieux: MesLieux) -> some View {
        ArticleRow(article: article, magasin: lieux.noms(de: article), onMagasin: { choix = ArticleChoisi(id: article.id) }) {
            store.toggleArticle(id: article.id, of: item)
        } onEdit: { saisie in
            store.editArticle(id: article.id, saisie: saisie, of: item)
        }
    }

    private func ajouter() {
        let lieux = store.mesLieux
        let actif = item.liste.map { lieux.groupes(de: $0).contains(filtre) } == true ? filtre : ""
        store.addArticle(saisie, to: item, magasins: actif.isEmpty ? [] : [actif])
        saisie = ""
        saisieActive = true
    }

    private func retirer(_ ids: [String]) {
        guard var liste = item.liste else { return }
        liste.articles.removeAll { ids.contains($0.id) }
        store.setListe(liste, of: item)
    }
}

/// « Où l'acheter » : les magasins de Mes lieux, plusieurs possibles. Le choix est retenu pour ce produit.
private struct OuAcheterView: View {
    @Environment(TaskStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let item: TaskItem
    let articleID: String

    var body: some View {
        let lieux = store.mesLieux
        let article = item.liste?.articles.first { $0.id == articleID }
        let choisis = article.map { lieux.groupes(de: $0) } ?? []
        NavigationStack {
            List {
                Section {
                    ForEach(lieux.groupesMagasins) { groupe in
                        let coche = choisis.contains(groupe.id)
                        Button {
                            let nouveaux = coche ? choisis.filter { $0 != groupe.id } : choisis + [groupe.id]
                            store.setMagasins(nouveaux, ofArticle: articleID, of: item)
                        } label: {
                            HStack {
                                Image(systemName: coche ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(coche ? Color.accentColor : .secondary)
                                Text(groupe.nom)
                                Spacer()
                                Text(groupe.lieux.isEmpty ? "Aucun lieu" : "\(groupe.lieux.count)")
                                    .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(coche && choisis.count == 1)
                        .accessibilityAddTraits(coche ? .isSelected : [])
                    }
                } footer: {
                    Text("Chaque magasin te préviendra en passant. Claude retient ce choix pour ce produit. Les magasins se règlent dans Réglages › Mes lieux.")
                }
            }
            .navigationTitle(article?.texte ?? "Où l'acheter")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Ligne de la liste unique dans À faire : ouvre l'écran Courses, sans date ni rond « Fait ».
struct CoursesLigne: View {
    @Environment(TaskStore.self) private var store
    let item: TaskItem
    var onOpen: ((TaskItem) -> Void)? = nil

    var body: some View {
        let contenu = HStack(spacing: 12) {
            Image(systemName: "cart").font(.title3).foregroundStyle(Color.accentColor).frame(minWidth: 28, minHeight: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("Courses")
                Text(item.liste.map { store.mesLieux.resume(de: $0) } ?? "Rien à prendre")
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        if let onOpen {
            Button { onOpen(item) } label: { contenu }.buttonStyle(.plain)
        } else {
            contenu
        }
    }
}
