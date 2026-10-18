import DonneesHA
import Foundation
import Testing
import UIKit
@testable import Relance

/// Pièces jointes (P9-K) : format dans HA, ligne des notes, préparation sur l'appareil.
@MainActor
struct PiecesTests {
    @Test func formatEtLigne() throws {
        let json = """
        {"titre":"Facture","fait":false,"pieces":[{"id":"\(String(repeating: "a", count: 64))","nom":"EDF.pdf",
          "type":"application/pdf","taille":1200,"texte":"Montant 84,12 €","drive":"x"},{"sans_id":true}]}
        """
        let tache = try JSONDecoder().decode(TacheHA.self, from: Data(json.utf8))
        #expect(tache.pieces.count == 1 && tache.pieces[0].autres["drive"] == .texte("x"))
        let relu = try JSONDecoder().decode(TacheHA.self, from: JSONEncoder().encode(tache))
        #expect(relu.pieces == tache.pieces && relu.autres["pieces"] == nil)
        let notes = TacheHA.Piece.notes("Payer avant le 30", setting: tache.pieces)
        #expect(notes == "Payer avant le 30\n📎 1 pièce jointe")
        #expect(TacheHA.Piece.notes(notes, setting: []) == "Payer avant le 30")
        #expect(NoteLines.visible(notes) == "Payer avant le 30")
    }

    @Test func photoReduiteEtTexte() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 1200)).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 3000, height: 1200))
            ("FACTURE EDF Montant 84,12 euros" as NSString).draw(at: CGPoint(x: 80, y: 400),
                withAttributes: [.font: UIFont.systemFont(ofSize: 140)])
        }
        let piece = try PiecesJointes.preparer(try #require(image.pngData()), nom: "Capture.png", type: .png, source: "photo")
        #expect(piece.type == "image/jpeg" && piece.nom == "Capture.jpg" && piece.id.count == 64)
        #expect(piece.texte?.contains("FACTURE") == true)
        #expect(PiecesJointes.enAttente[piece.id] != nil)
        let local = try #require(PiecesJointes.local(piece))
        let reduite = try #require(UIImage(contentsOfFile: local.path))
        #expect(max(reduite.size.width, reduite.size.height) * reduite.scale <= 2048)
    }

    @Test func texteDUnPDF() throws {
        let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842)).pdfData { ctx in
            ctx.beginPage()
            ("Convocation AG du 119, le 12 novembre" as NSString).draw(at: CGPoint(x: 50, y: 100),
                withAttributes: [.font: UIFont.systemFont(ofSize: 18)])
        }
        let piece = try PiecesJointes.preparer(pdf, nom: "AG.pdf", type: .pdf, source: "fichier")
        #expect(piece.type == "application/pdf" && piece.texte?.contains("Convocation AG") == true)
    }

    @Test func joindreEtRetirer() {
        let store = TaskStore(auth: SlowAccount(), inMemory: true)
        let item = store.add(title: "Facture", day: nil, minutes: nil)
        let p = (0..<7).map { TacheHA.Piece(id: String(repeating: "\($0)", count: 64), nom: "f\($0)", type: "image/jpeg", taille: 1) }
        store.addPieces(p, to: item)
        #expect(item.pieces.count == TacheHA.Piece.maxParTache)
        store.removePiece(p[0].id, from: item)
        #expect(item.pieces.count == 4 && TacheHA(item).notes.hasSuffix("📎 4 pièces jointes"))
    }
}
