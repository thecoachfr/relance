import SwiftUI

/// Modificateurs propres à iOS, sans effet sur Mac : les mêmes vues servent aux deux apps.
extension View {
    /// Titre compact dans la barre de navigation.
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    func hiddenNavigationBar() -> some View {
        #if os(iOS)
        toolbar(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }

    /// Surbrillance au survol du pointeur (iPad).
    func pointerHighlight() -> some View {
        #if os(iOS)
        hoverEffect(.highlight)
        #else
        self
        #endif
    }

    /// Champ de texte pleine largeur, sans étiquette à gauche (sur Mac, un formulaire aligne
    /// sinon le texte à droite de son nom, ce qui ne va pas pour un titre ou des notes).
    func formFieldWithoutLabel() -> some View {
        #if os(macOS)
        labelsHidden()
        #else
        self
        #endif
    }

    /// Raccourci clavier de l'iPad. Sur Mac, les menus portent déjà ces raccourcis.
    func tabletShortcut(_ key: KeyEquivalent, modifiers: EventModifiers = .command) -> some View {
        #if os(iOS)
        keyboardShortcut(key, modifiers: modifiers)
        #else
        self
        #endif
    }
}
