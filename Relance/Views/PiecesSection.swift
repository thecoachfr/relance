import PhotosUI
import QuickLook
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import VisionKit
#endif

/// Section « Pièces jointes » de la fiche (P9-K) : vignettes, aperçu plein écran (Quick Look), ajout depuis les
/// photos, les fichiers ou le scanner de documents, glisser-déposer sur Mac et iPad. Seulement en mode Home Assistant.
struct PiecesSection: View {
    @Environment(TaskStore.self) private var store
    let item: TaskItem
    @State private var photos: [PhotosPickerItem] = []
    @State private var choixPhotos = false
    @State private var choixFichiers = false
    @State private var scanner = false
    @State private var apercu: URL?
    @State private var enCours = 0
    @State private var erreur: String?

    var body: some View {
        if HAConfig.isActive {
            let pieces = item.pieces
            Section {
                if !pieces.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 10)], spacing: 10) {
                        ForEach(pieces) { piece in
                            Button { ouvrir(piece) } label: { PieceVignette(piece: piece) }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    if piece.autres["drive"] == nil {
                                        Button("Copier dans Google Drive", systemImage: "icloud.and.arrow.up") { copierDansDrive(piece) }
                                    } else {
                                        Label("Copiée dans Google Drive", systemImage: "checkmark.icloud")
                                    }
                                    Button("Retirer", systemImage: "trash", role: .destructive) {
                                        store.removePiece(piece.id, from: item)
                                    }
                                }
                                .accessibilityLabel(piece.nom)
                                .accessibilityHint("Ouvre l'aperçu")
                                .accessibilityAction(named: "Retirer") { store.removePiece(piece.id, from: item) }
                        }
                    }
                    .padding(.vertical, 4)
                }
                if enCours > 0 {
                    Label("Préparation de \(enCours) pièce\(enCours > 1 ? "s" : "")…", systemImage: "hourglass")
                        .foregroundStyle(.secondary)
                }
                if pieces.count < TacheHA.Piece.maxParTache {
                    Menu {
                        Button("Photos", systemImage: "photo.on.rectangle") { choixPhotos = true }
                        Button("Fichiers", systemImage: "folder") { choixFichiers = true }
                        #if os(iOS)
                        if VNDocumentCameraViewController.isSupported {
                            Button("Scanner un document", systemImage: "doc.viewfinder") { scanner = true }
                        }
                        #endif
                    } label: {
                        Label("Joindre", systemImage: "paperclip")
                    }
                }
                if let erreur { Text(erreur).font(.footnote).foregroundStyle(.red) }
            } header: {
                Text("Pièces jointes")
            } footer: {
                if pieces.isEmpty {
                    Text("Photo, PDF ou document scanné : rangés dans Home Assistant, le texte lu aide Claude à trier.")
                }
            }
            .photosPicker(isPresented: $choixPhotos, selection: $photos,
                          maxSelectionCount: TacheHA.Piece.maxParTache - pieces.count, matching: .images)
            .onChange(of: photos) { _, choix in
                guard !choix.isEmpty else { return }
                photos = []
                Task { await joindrePhotos(choix) }
            }
            .fileImporter(isPresented: $choixFichiers, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: true) { resultat in
                if case .success(let urls) = resultat { Task { await joindreFichiers(urls, source: "fichier") } }
            }
            #if os(iOS)
            .fullScreenCover(isPresented: $scanner) {
                ScannerDocument { pdf in
                    scanner = false
                    if let pdf { Task { await joindre([(pdf, "Document scanné.pdf", .pdf)], source: "scan") } }
                }
                .ignoresSafeArea()
            }
            #endif
            .dropDestination(for: URL.self) { urls, _ in
                Task { await joindreFichiers(urls, source: "fichier") }
                return true
            }
            .quickLookPreview($apercu)
        }
    }

    private func ouvrir(_ piece: TacheHA.Piece) {
        Task {
            erreur = nil
            if let url = await PiecesJointes.fichier(piece) { apercu = url } else {
                erreur = "Pièce pas encore disponible : Home Assistant injoignable ou envoi en cours depuis un autre appareil."
            }
        }
    }

    /// Option B : une copie dans le dossier « Aiguillage – Justificatifs » de Google Drive (factures pour la TVA).
    private func copierDansDrive(_ piece: TacheHA.Piece) {
        Task {
            erreur = nil
            guard let url = await PiecesJointes.fichier(piece) else {
                erreur = "Pièce pas encore disponible sur cet appareil."
                return
            }
            do {
                let id = try await DriveCopie.copier(url, nom: piece.nom, type: piece.type)
                store.setDrive(id, piece: piece.id, of: item)
            } catch {
                erreur = error.localizedDescription
            }
        }
    }

    private func joindrePhotos(_ choix: [PhotosPickerItem]) async {
        var fichiers: [(Data, String, UTType?)] = []
        for (i, element) in choix.enumerated() {
            if let data = try? await element.loadTransferable(type: Data.self) {
                fichiers.append((data, "Photo \(i + 1).jpg", element.supportedContentTypes.first))
            }
        }
        await joindre(fichiers, source: "photo")
    }

    private func joindreFichiers(_ urls: [URL], source: String) async {
        var fichiers: [(Data, String, UTType?)] = []
        for url in urls.prefix(TacheHA.Piece.maxParTache) {
            let acces = url.startAccessingSecurityScopedResource()
            defer { if acces { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) {
                fichiers.append((data, url.lastPathComponent, UTType(filenameExtension: url.pathExtension)))
            }
        }
        await joindre(fichiers, source: source)
    }

    /// Prépare hors du fil principal (photo réduite, texte lu), puis joint à la tâche ; l'envoi suit la synchro.
    private func joindre(_ fichiers: [(Data, String, UTType?)], source: String) async {
        guard !fichiers.isEmpty else { return }
        enCours += fichiers.count
        erreur = nil
        let resultat = await Task.detached(priority: .userInitiated) {
            fichiers.map { donnees, nom, type in
                Result { try PiecesJointes.preparer(donnees, nom: nom, type: type, source: source) }
            }
        }.value
        enCours -= fichiers.count
        let pieces = resultat.compactMap { try? $0.get() }
        if pieces.count < resultat.count {
            erreur = resultat.compactMap { if case .failure(let e) = $0 { e.localizedDescription } else { nil } }.first
        }
        store.addPieces(pieces, to: item)
        Task { await store.sync() }
    }
}

/// Vignette d'une pièce : aperçu du fichier (Quick Look) s'il est sur l'appareil, sinon son icône.
private struct PieceVignette: View {
    let piece: TacheHA.Piece
    @State private var image: CGImage?
    @Environment(\.displayScale) private var echelle

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(.quaternary)
                if let image {
                    Image(decorative: image, scale: echelle).resizable().scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    Image(systemName: piece.estPDF ? "doc.richtext" : piece.estImage ? "photo" : "doc")
                        .font(.title2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 84, height: 84)
            .clipped()
            Text(piece.nom).font(.caption2).lineLimit(1).truncationMode(.middle).frame(width: 84)
        }
        .task(id: piece.id) { await charger() }
    }

    private func charger() async {
        guard let url = await PiecesJointes.fichier(piece) else { return }
        let requete = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 84, height: 84), scale: echelle,
                                                   representationTypes: .thumbnail)
        if let vignette = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: requete) {
            image = vignette.cgImage
        }
    }
}

#if os(iOS)
/// Scanner de documents d'iOS (VisionKit) : les pages scannées, réunies en un PDF.
struct ScannerDocument: UIViewControllerRepresentable {
    let fini: (Data?) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vue = VNDocumentCameraViewController()
        vue.delegate = context.coordinator
        return vue
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinateur { Coordinateur(fini: fini) }

    final class Coordinateur: NSObject, VNDocumentCameraViewControllerDelegate {
        let fini: (Data?) -> Void
        init(fini: @escaping (Data?) -> Void) { self.fini = fini }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let pdf = PDFDocumentFromScan.pdf(scan)
            fini(pdf)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { fini(nil) }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { fini(nil) }
    }
}

/// Les pages d'un scan en un PDF (JPEG compressé par page).
private enum PDFDocumentFromScan {
    static func pdf(_ scan: VNDocumentCameraScan) -> Data? {
        let format = UIGraphicsPDFRendererFormat()
        let premiere = scan.imageOfPage(at: 0)
        let cadre = CGRect(origin: .zero, size: CGSize(width: 595, height: 595 * premiere.size.height / max(premiere.size.width, 1)))
        return UIGraphicsPDFRenderer(bounds: cadre, format: format).pdfData { contexte in
            for i in 0..<scan.pageCount {
                contexte.beginPage()
                let image = scan.imageOfPage(at: i)
                let compressee = image.jpegData(compressionQuality: 0.7).flatMap(UIImage.init(data:)) ?? image
                compressee.draw(in: cadre)
            }
        }
    }
}
#endif
