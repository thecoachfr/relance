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
                    ForEach(liste.articles) { article in
                        ligne(article)
                    }
                    .onDelete { store.removeArticles(at: $0, of: item) }
                    .onMove { store.moveArticles(from: $0, to: $1, of: item) }
                    TextField("Ajouter un article", text: $saisie)
                        .focused($saisieActive)
                        .submitLabel(.next)
                        .onSubmit(ajouter)
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
