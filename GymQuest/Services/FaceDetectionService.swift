// FaceDetectionService — content-psychology pass.
//
// Wraps Vision's `VNDetectFaceRectanglesRequest` so the post editor
// can default audience to .friends (and surface a "this looks personal"
// hint) when a user attaches a photo with a recognizable face.
//
// Privacy framing matters here: the goal is to put friction on the
// right side. First time a user attaches a body shot, they should
// have to consciously upgrade audience past .friends. Vision runs
// entirely on-device.

import Foundation
import Vision
#if canImport(UIKit)
import UIKit
#endif

@MainActor
enum FaceDetectionService {

    /// True if Vision detects ≥1 face in the image. Returns false when
    /// the image can't be decoded or no faces are found. Off by default
    /// on macOS (no face detection at this resolution there).
    static func containsFace(imageData: Data) async -> Bool {
        #if canImport(UIKit)
        guard let uiImage = UIImage(data: imageData),
              let cgImage = uiImage.cgImage else { return false }

        return await withCheckedContinuation { continuation in
            let request = VNDetectFaceRectanglesRequest { request, _ in
                let observations = request.results as? [VNFaceObservation] ?? []
                continuation.resume(returning: !observations.isEmpty)
            }
            request.revision = VNDetectFaceRectanglesRequestRevision3
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
        #else
        return false
        #endif
    }
}
