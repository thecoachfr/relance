import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Point d'entrée de l'extension de partage : lit le texte (ou le lien) reçu et affiche la fiche.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        Task { @MainActor in
            let text = await Self.sharedText(from: extensionContext)
            let host = UIHostingController(rootView: ShareComposeView(original: text) { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
            } onCancel: { [weak self] in
                self?.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
            })
            addChild(host)
            host.view.frame = view.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(host.view)
            host.didMove(toParent: self)
        }
    }

    /// Texte d'abord (un message), sinon l'adresse du lien.
    private static func sharedText(from context: NSExtensionContext?) async -> String {
        let providers = (context?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        var texts: [String] = []
        var urls: [String] = []
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
               let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                texts.append(text)
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                      let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                urls.append(url.absoluteString)
            }
        }
        return (texts.isEmpty ? urls : texts + urls.filter { url in !texts.contains { $0.contains(url) } })
            .joined(separator: "\n")
    }
}
