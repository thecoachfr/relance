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
        Button {
            terminee = store.toggleArticle(id: article.id, of: item)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: article.coche ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(article.coche ? Color.accentColor : Color.secondary)
                Text(article.texte)
                    .strikethrough(article.coche)
                    .foregroundStyle(article.coche ? .secondary : .primary)
                Spacer()
                if let quantite = article.quantite {
                    Text(quantite).foregroundStyle(.secondary)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(article.coche ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(article.coche ? "Décoche l'article" : "Coche l'article")
    }

    private func ajouter() {
        store.addArticle(saisie, to: item)
        saisie = ""
        saisieActive = true
    }
}
