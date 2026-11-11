import Foundation
import os

/// Écran ou action en cours, pour savoir ce que faisait l'app au moment d'un pic de mémoire (11/11/2026 : pics de
/// 270 à 900 Mo sur l'iPhone et l'iPad, sans savoir sur quel écran). Que des libellés fixes (« Scan de document »,
/// « À faire »), jamais de contenu. Appelable de n'importe quel fil (Vision tourne hors du fil principal).
///
/// Une action notée relève aussi l'empreinte en finissant : un pic bref entre deux mesures de `SuiviEcran`
/// (toutes les 10 s) est ainsi rattrapé, avec l'action qui l'a causé.
nonisolated enum ActiviteEcran {
    /// Libellés connus (fixes, sans contenu personnel).
    enum Libelle: String, Sendable {
        case aFaire = "À faire"
        case aTrier = "À trier"
        case envies = "Envies"
        case carte = "Carte"
        case fiche = "Fiche d'une tâche"
        case saisieRapide = "Saisie rapide"
        case scan = "Scan de document"
        case scanPDF = "Scan mis en PDF"
        case appareilPhoto = "Appareil photo"
        case chargementPhotos = "Chargement de photos"
        case preparationPiece = "Préparation d'une pièce jointe"
        case texteImage = "Lecture du texte d'une image (Vision)"
        case textePDF = "Lecture du texte d'un PDF"
        case apercuPiece = "Aperçu d'une pièce jointe"
    }

    struct Etat: Sendable {
        var suivant = 0
        /// Dans l'ordre d'arrivée : « À faire › Fiche d'une tâche › Lecture du texte… ».
        var enCours: [(id: Int, libelle: String)] = []
        /// Pic relevé en fin d'action, pas encore repris par `SuiviEcran`.
        var picEnAttente: (mo: Double, contexte: String)?
    }

    private static let etat = OSAllocatedUnfairLock(initialState: Etat())

    /// Contexte actuel (« À faire › Fiche d'une tâche »), ou nil si rien n'est noté.
    static var contexte: String? { etat.withLock { Self.texte($0.enCours) } }

    static func texte(_ liste: [(id: Int, libelle: String)]) -> String? {
        guard !liste.isEmpty else { return nil }
        // Un même libellé deux fois de suite (deux pièces lues l'une après l'autre) n'est écrit qu'une fois.
        var libelles: [String] = []
        for l in liste.map(\.libelle) where libelles.last != l { libelles.append(l) }
        return libelles.joined(separator: " › ")
    }

    /// Note le début ; renvoie un jeton à passer à `fin`.
    @discardableResult
    static func debut(_ libelle: Libelle) -> Int {
        etat.withLock {
            $0.suivant += 1
            $0.enCours.append((id: $0.suivant, libelle: libelle.rawValue))
            return $0.suivant
        }
    }

    /// Note la fin : l'empreinte est relevée avant de retirer le libellé.
    static func fin(_ jeton: Int, mo: Double = Empreinte.megaoctets()) {
        etat.withLock { e in
            if let contexte = Self.texte(e.enCours), mo > (e.picEnAttente?.mo ?? 0) {
                e.picEnAttente = (mo, contexte)
            }
            e.enCours.removeAll { $0.id == jeton }
        }
    }

    /// Le travail entre `debut` et `fin`.
    static func pendant<T>(_ libelle: Libelle, _ travail: () throws -> T) rethrows -> T {
        let jeton = debut(libelle)
        defer { fin(jeton) }
        return try travail()
    }

    static func pendant<T>(_ libelle: Libelle, _ travail: () async throws -> T) async rethrows -> T {
        let jeton = debut(libelle)
        defer { fin(jeton) }
        return try await travail()
    }

    /// Le pic relevé en fin d'action depuis le dernier appel (repris par `SuiviEcran.mesurer`).
    static func prendrePic() -> (mo: Double, contexte: String)? {
        etat.withLock { e in
            defer { e.picEnAttente = nil }
            return e.picEnAttente
        }
    }

    /// Pour les tests.
    static func reinitialiser() { etat.withLock { $0 = Etat() } }
}

#if canImport(SwiftUI)
import SwiftUI

/// Libellé noté tant que la vue est affichée (onglet, feuille, scanner).
struct ActiviteEcranModifier: ViewModifier {
    let libelle: ActiviteEcran.Libelle
    @State private var jeton: Int?

    func body(content: Content) -> some View {
        content
            .onAppear { if jeton == nil { jeton = ActiviteEcran.debut(libelle) } }
            .onDisappear {
                if let jeton { ActiviteEcran.fin(jeton) }
                jeton = nil
            }
    }
}

extension View {
    /// Note `libelle` comme écran en cours tant que la vue est affichée (diagnostic mémoire, sans contenu).
    func activiteEcran(_ libelle: ActiviteEcran.Libelle) -> some View { modifier(ActiviteEcranModifier(libelle: libelle)) }

    /// Note `libelle` tant que `actif` est vrai (aperçu Quick Look ouvert…).
    func activiteEcran(_ libelle: ActiviteEcran.Libelle, si actif: Bool) -> some View {
        modifier(ActiviteSiModifier(libelle: libelle, actif: actif))
    }
}

private struct ActiviteSiModifier: ViewModifier {
    let libelle: ActiviteEcran.Libelle
    let actif: Bool
    @State private var jeton: Int?

    func body(content: Content) -> some View {
        content
            .onChange(of: actif, initial: true) { _, oui in
                if oui, jeton == nil { jeton = ActiviteEcran.debut(libelle) }
                if !oui, let j = jeton { ActiviteEcran.fin(j); jeton = nil }
            }
            .onDisappear { if let j = jeton { ActiviteEcran.fin(j); jeton = nil } }
    }
}
#endif
