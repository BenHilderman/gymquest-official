// External share watermark — design v4.3 §7B.
// All external shares carry a subtle Lift watermark. Composes a small
// overlay onto images before handing off to the share sheet.

import Foundation
import CoreGraphics
#if canImport(UIKit)
import UIKit
#endif

enum ExternalShareDestination: String {
    case instagramStory, instagramPost, tiktok, snapchat, iMessage, copyLink
}

enum ExternalShareWatermark {
    /// Compose a "Lift" wordmark in the bottom-right corner of an image. Returns
    /// the rendered image, or the original on macOS / failure.
    #if canImport(UIKit)
    static func apply(to image: UIImage, accent: UIColor = .systemPurple) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { ctx in
            image.draw(at: .zero)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: max(14, image.size.height * 0.018), weight: .semibold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.85)
            ]
            let s = NSAttributedString(string: "lift", attributes: attrs)
            let textSize = s.size()
            let inset: CGFloat = max(12, image.size.height * 0.012)
            let bgRect = CGRect(
                x: image.size.width - textSize.width - inset * 2 - 4,
                y: image.size.height - textSize.height - inset - 4,
                width: textSize.width + inset,
                height: textSize.height + 4
            )
            let path = UIBezierPath(roundedRect: bgRect, cornerRadius: bgRect.height / 2)
            UIColor.black.withAlphaComponent(0.35).setFill()
            path.fill()
            s.draw(at: CGPoint(x: bgRect.minX + inset / 2, y: bgRect.minY + 2))
        }
    }
    #endif
}
