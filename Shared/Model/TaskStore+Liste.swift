import Foundation

/// Listes d'articles cochables (P9-G1). Chaque changement d'article est horodaté (`maj`) pour la fusion entre
/// appareils ; la tâche passe en « Fait » quand tout est coché, et se rouvre si un article est décoché ou ajouté.
extension TaskStore {
    typealias Liste = TacheHA.Liste

    /// Remplace la liste (ordre, suppression) ; `nil` retire la liste de la tâche.
    func setListe(_ liste: Liste?, of item: TaskItem) {
        guard liste != item.liste else { return }
        item.liste = liste
        item.markChanged()
        commit()
    }

    /// Ajoute un article (« 2 lait » → quantité « 2 », « lait ») ; rouvre la tâche si elle était faite.
    func addArticle(_ saisie: String, to item: TaskItem, now: Date = .now) {
        guard var article = Self.article(saisie) else { return }
        article.maj = TacheHA.timestamp(now)
        var liste = item.liste ?? Liste()
        liste.articles.append(article)
        if item.isCompleted { reopen(item) }
        setListe(liste, of: item)
    }

    /// Coche ou décoche ; tout coché → « Fait » (renvoie `true` pour proposer « Annuler »), décoché → rouverte.
    @discardableResult
    func toggleArticle(id: String, of item: TaskItem, now: Date = .now) -> Bool {
        guard var liste = item.liste, let i = liste.articles.firstIndex(where: { $0.id == id }) else { return false }
        liste.articles[i].coche.toggle()
        liste.articles[i].maj = TacheHA.timestamp(now)
        setListe(liste, of: item)
        if liste.toutCoché, !item.isCompleted {
            complete(item)
            return true
        }
        if !liste.articles[i].coche, item.isCompleted { reopen(item) }
        return false
    }

    /// Coche venue d'un autre appareil (montre, P9-G2), datée de son geste : ignorée si l'article a changé depuis
    /// (file d'attente livrée en retard). Tout coché → « Fait » ; décoché → rouverte.
    func setArticle(id: String, coche: Bool, of item: TaskItem, at date: Date) {
        guard var liste = item.liste, let i = liste.articles.firstIndex(where: { $0.id == id }) else { return }
        if let maj = TacheHA.date(liste.articles[i].maj), maj > date { return }
        guard liste.articles[i].coche != coche else { return }
        liste.articles[i].coche = coche
        liste.articles[i].maj = TacheHA.timestamp(date)
        setListe(liste, of: item)
        if liste.toutCoché, !item.isCompleted { complete(item) }
        if !coche, item.isCompleted { reopen(item) }
    }

    /// Modifie le texte d'un article (« 6 œufs » → quantité 6) ; vide, l'article est retiré.
    func editArticle(id: String, saisie: String, of item: TaskItem, now: Date = .now) {
        guard var liste = item.liste, let i = liste.articles.firstIndex(where: { $0.id == id }) else { return }
        guard let lu = Self.article(saisie) else {
            liste.articles.remove(at: i)
            setListe(liste, of: item)
            return
        }
        guard lu.texte != liste.articles[i].texte || lu.quantite != liste.articles[i].quantite else { return }
        liste.articles[i].texte = lu.texte
        liste.articles[i].quantite = lu.quantite
        liste.articles[i].maj = TacheHA.timestamp(now)
        setListe(liste, of: item)
    }

    func removeArticles(at offsets: IndexSet, of item: TaskItem) {
        guard var liste = item.liste else { return }
        liste.articles.remove(atOffsets: offsets)
        setListe(liste, of: item)
    }

    func moveArticles(from source: IndexSet, to destination: Int, of item: TaskItem) {
        guard var liste = item.liste else { return }
        liste.articles.move(fromOffsets: source, toOffset: destination)
        setListe(liste, of: item)
    }

    /// Article tiré d'une saisie : un nombre en tête devient la quantité (« 6 œufs », « 2 kg pommes » non :
    /// seule la quantité nue est reconnue, le reste reste dans le texte). `nil` si la saisie est vide.
    nonisolated static func article(_ saisie: String) -> Liste.Article? {
        let texte = saisie.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texte.isEmpty else { return nil }
        let mots = texte.split(separator: " ", maxSplits: 1).map(String.init)
        if mots.count == 2, Int(mots[0]) != nil {
            return Liste.Article(texte: mots[1], quantite: mots[0])
        }
        return Liste.Article(texte: texte)
    }
}
