import UIKit
import AppCore

/// Photo Booth prints: four Retro Cam shots as a classic strip or a 2×2
/// grid on ink, with an optional caption and the date like a real booth.
/// Frames are cropped around the face, as on the "Photo strip" share
/// design. On-device work, so never branded. Safe off the main thread.
enum BoothPrint {
    /// Where the face is in each shot (Vision, on the device), worked out
    /// once so changing the layout or the caption re-prints quickly.
    static func faces(in shots: [UIImage]) -> [CGRect?] {
        shots.map { SubjectAnalysis.analyze($0, includingCutout: false).face }
    }

    /// `caption` must already have passed the content policy.
    static func render(_ shots: [UIImage], faces: [CGRect?], layout: BoothLayout, caption: String, date: Date?) -> UIImage {
        let caption = PhotoBooth.cleanCaption(caption)
        let plan = layout.plan(hasFooter: !caption.isEmpty || date != nil)
        let canvas = CGSize(width: plan.width, height: plan.height)
        return ShareRenderer.renderer(canvas, opaque: true).image { context in
            let cg = context.cgContext
            UIColor.brandInk.setFill()
            cg.fill(CGRect(origin: .zero, size: canvas))
            for (index, cell) in plan.cells.enumerated() where index < shots.count {
                let frame = CGRect(x: cell.x, y: cell.y, width: cell.width, height: cell.height)
                let shot = shots[index]
                let face = index < faces.count ? faces[index] : nil
                cg.saveGState()
                cg.clip(to: frame)
                shot.draw(in: ShareRenderer.fillRect(for: shot.size, in: frame, face: face, faceAnchor: CGPoint(x: 0.5, y: 0.45)))
                cg.restoreGState()
            }
            if let footer = plan.footer {
                drawFooter(in: CGRect(x: footer.x, y: footer.y, width: footer.width, height: footer.height), caption: caption, date: date)
            }
        }
    }

    /// The caption in the editorial italic (it falls back to the system's
    /// glyphs for every app language), the date in typewriter type.
    private static func drawFooter(in footer: CGRect, caption: String, date: Date?) {
        let stamp = date.map { "✦ \($0.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year(.twoDigits))) ✦" }
        let typewriter = UIFont(name: "Courier-Bold", size: 46) ?? .monospacedSystemFont(ofSize: 46, weight: .bold)
        let captionFont = ShareRenderer.accentFont(88)
        switch (caption.isEmpty, stamp) {
        case (false, let stamp?):
            ShareRenderer.drawText(caption, font: captionFont, color: .white,
                                   centeredIn: CGRect(x: footer.minX, y: footer.minY + 40, width: footer.width, height: 130))
            ShareRenderer.drawText(stamp, font: typewriter, color: UIColor.white.withAlphaComponent(0.8),
                                   centeredIn: CGRect(x: footer.minX, y: footer.minY + 180, width: footer.width, height: 70))
        case (false, nil):
            ShareRenderer.drawText(caption, font: captionFont, color: .white, centeredIn: footer.insetBy(dx: 0, dy: 30))
        case (true, let stamp?):
            ShareRenderer.drawText(stamp, font: typewriter.withSize(56), color: .white, centeredIn: footer.insetBy(dx: 0, dy: 30))
        case (true, nil):
            break
        }
    }
}
