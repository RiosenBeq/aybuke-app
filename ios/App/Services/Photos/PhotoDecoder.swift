import UIKit
import AppCore

/// Turns picked photo data into an editor-ready image: RAW (ProRAW, DNG) is
/// developed with Auto, since it looks flat out of the camera, and every
/// photo gets its orientation baked in and is sized for the editor.
enum PhotoDecoder {
    /// `sourceType`: the AI marking the file already carried. Decoding drops
    /// the XMP, so it's read first and kept (see `Provenance`).
    static func decode(_ data: Data) async -> (image: UIImage, isRAW: Bool, sourceType: DigitalSourceType?)? {
        let isRAW = AutoDevelop.isRAW(data)
        return await Task.detached(priority: .userInitiated) { () -> (UIImage, Bool, DigitalSourceType?)? in
            let sourceType = ImageExporter.digitalSourceType(in: data)
            if isRAW, let developed = AutoDevelop.developRAW(data) {
                return (ImageUtilities.normalized(developed), isRAW, sourceType)
            }
            guard let image = ImageUtilities.decodedImage(from: data) else { return nil }
            return (image, isRAW, sourceType)
        }.value
    }
}
