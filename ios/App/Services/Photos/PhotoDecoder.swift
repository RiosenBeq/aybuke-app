import UIKit

/// Turns picked photo data into an editor-ready image: RAW (ProRAW, DNG) is
/// developed with Auto, since it looks flat out of the camera, and every
/// photo gets its orientation baked in and is sized for the editor.
enum PhotoDecoder {
    static func decode(_ data: Data) async -> (image: UIImage, isRAW: Bool)? {
        let isRAW = AutoDevelop.isRAW(data)
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            if isRAW, let developed = AutoDevelop.developRAW(data) {
                return ImageUtilities.normalized(developed)
            }
            guard let image = UIImage(data: data) else { return nil }
            return ImageUtilities.normalized(image)
        }.value
        return image.map { ($0, isRAW) }
    }
}
