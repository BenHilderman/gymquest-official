import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Fetches real fitness/gym/running/yoga photos from Unsplash's public
/// CDN and caches them to disk. Used to progressively enhance seeded
/// posts — the procedural gradient thumbnails render instantly on seed,
/// then this service swaps them for real photos in the background.
///
/// No API key required; hits the public image CDN directly against a
/// curated list of photo IDs.
enum UnsplashPhotoService {

    /// Curated Unsplash photo IDs — all real fitness, gym, running,
    /// yoga, or cardio content. Sized to 600×600 via CDN params so we
    /// download a consistent thumbnail instead of multi-MB originals.
    static let photoIds: [String] = [
        // Gym / strength
        "1534438327276-14e5300c3a48",    // dumbbells
        "1571019613454-1cb2f99b2d8b",    // gym interior
        "1583454110551-21f2fa2afe61",    // barbell floor
        "1583500178450-e59e4309b01f",    // kettlebell row
        "1581009146145-b5ef050c2e1e",    // dumbbell press
        "1540497077202-7c8a3999166f",    // athlete running stairs
        "1517836357463-d25dfeac3438",    // runner outdoors
        "1486218119243-13883505764c",    // runner on track
        "1594737625785-a6cbdabd333c",    // sprinter
        "1604480133435-25b86862d276",    // athlete training
        "1535743686920-55e4145369b9",    // weight plates
        "1518611012118-696072aa579a",    // barbell bench
        "1574680096145-d05b474e2155",    // yoga flow
        "1575052814086-f385e2e2ad1b",    // yoga pose
        "1506629082955-511b1aa562c8",    // yoga mat
        "1518310383802-640c2de311b2",    // HIIT class
        "1593079831268-3381b0db4a77",    // outdoor HIIT
        "1549060279-7e168fcee0c2",       // pull up
        "1558611848-73f7eb4001a1",       // rope training
        "1434596922112-19c563067271",    // lifter at rack
        "1552196563-55cd4e45efb3",       // crossfit box
        "1532384748853-8f54a8f476e2",    // athlete portrait
        "1520975916090-3105956dac38",    // woman lifting
        "1544367567-0f2fcb009e0b",       // studio yoga
        "1517344884509-a0c97ec11bcc",    // runner silhouette
        "1552239830-3c45fb4b2b04",       // treadmill
        "1583454155184-870a1f63aebc",    // squat rack
        "1541534741688-6078c6bfb5c5",    // cardio machines
        "1576678927484-cc907957088c",    // stretching
        "1556817411-58c45525a8a1"        // rowing
    ]

    /// Returns cached data if present, otherwise downloads and caches.
    /// Returns nil on network failure — callers should fall back to
    /// whatever photoData was already set on the post.
    static func fetch(id: String) async -> Data? {
        let url = "https://images.unsplash.com/photo-\(id)?auto=format&fit=crop&w=600&h=600&q=80"
        let cacheURL = cacheURL(for: id)

        if let cached = try? Data(contentsOf: cacheURL), !cached.isEmpty {
            return cached
        }

        guard let requestURL = URL(string: url) else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: requestURL)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, !data.isEmpty else {
                return nil
            }
            // Recompress so on-disk payload stays small — SwiftData
            // persists this blob per post and the 600px original JPEG
            // can exceed 200KB. 0.7 quality gets us ~80KB.
            #if canImport(UIKit)
            let resized: Data
            if let img = UIImage(data: data), let jpeg = img.jpegData(compressionQuality: 0.7) {
                resized = jpeg
            } else {
                resized = data
            }
            #else
            let resized = data
            #endif
            try? resized.write(to: cacheURL)
            return resized
        } catch {
            return nil
        }
    }

    /// Deterministic photo ID for a post, so the same post always gets
    /// the same picture across app launches (no flicker between seeds).
    static func photoId(forIndex index: Int) -> String {
        photoIds[index % photoIds.count]
    }

    private static func cacheURL(for id: String) -> URL {
        let fm = FileManager.default
        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = caches.appendingPathComponent("unsplash-photos", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(id.replacingOccurrences(of: "/", with: "_")).jpg")
    }
}
