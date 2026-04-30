// ThrowbackPhotoPicker — locked spec Item B.
//
// The Profile suggestion card opens the post editor pre-filled with a past
// workout. The throwback rules let users *optionally* attach a photo from
// the library that already existed on that date — explicitly opt-in, no
// fake "live capture" pretense. SwiftUI's `PhotosPicker` doesn't accept a
// date-range filter, so we drop down to PhotoKit's `PHFetchRequest` and
// hand-roll a small grid that pre-filters to a ±24h window around the
// workout's date.

#if canImport(UIKit)
import SwiftUI
import Photos
import PhotosUI

struct ThrowbackPhotoPicker: View {
    /// The workout's calendar date. We fetch assets from `[date - 24h,
    /// date + 24h]` so a late-night session that bled past midnight still
    /// surfaces both days' photos.
    let workoutDate: Date
    /// Fired with the chosen asset's data + thumbnail. Caller wraps it
    /// into a `PostMedia` and appends to `mediaItems`.
    var onPick: (Data, Data?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var assets: [PHAsset] = []
    @State private var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @State private var fetchState: FetchState = .idle

    private enum FetchState { case idle, loading, loaded, empty }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("photos from \(formattedDate)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("cancel") { dismiss() }
                    }
                }
                .gqPageBackground()
                .onAppear(perform: requestAndFetch)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch (authorizationStatus, fetchState) {
        case (.denied, _), (.restricted, _):
            permissionDeniedState
        case (_, .loading):
            ProgressView("loading photos…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case (_, .empty):
            emptyDayState
        case (_, .loaded):
            grid
        case (_, .idle):
            Color.clear
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                ForEach(assets, id: \.localIdentifier) { asset in
                    Button {
                        loadAndPick(asset)
                    } label: {
                        AssetThumbnail(asset: asset)
                            .aspectRatio(1, contentMode: .fill)
                            .frame(maxWidth: .infinity)
                            .clipped()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 8)
        }
    }

    private var emptyDayState: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 36))
                .foregroundStyle(GQColors.textTertiary)
            Text("no library photos from \(formattedDate)")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(GQColors.textSecondary)
            Text("you can still post the throwback without media.")
                .font(.system(size: 12))
                .foregroundColor(GQColors.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var permissionDeniedState: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 32))
                .foregroundStyle(GQColors.textTertiary)
            Text("photo library access is off")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(GQColors.textSecondary)
            Text("turn it on in Settings to attach a library photo from this day.")
                .font(.system(size: 12))
                .foregroundColor(GQColors.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var formattedDate: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: workoutDate).lowercased()
    }

    // MARK: - PhotoKit

    private func requestAndFetch() {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch current {
        case .authorized, .limited:
            authorizationStatus = current
            fetch()
        case .denied, .restricted:
            authorizationStatus = current
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                DispatchQueue.main.async {
                    authorizationStatus = status
                    if status == .authorized || status == .limited { fetch() }
                }
            }
        @unknown default:
            authorizationStatus = current
        }
    }

    private func fetch() {
        fetchState = .loading
        let cal = Calendar(identifier: .gregorian)
        let start = cal.date(byAdding: .hour, value: -24, to: workoutDate) ?? workoutDate
        let end = cal.date(byAdding: .hour, value: 24, to: workoutDate) ?? workoutDate

        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "creationDate >= %@ AND creationDate <= %@ AND mediaType == %d",
            start as NSDate,
            end as NSDate,
            PHAssetMediaType.image.rawValue
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

        DispatchQueue.global(qos: .userInitiated).async {
            let result = PHAsset.fetchAssets(with: options)
            var fetched: [PHAsset] = []
            result.enumerateObjects { asset, _, _ in fetched.append(asset) }
            DispatchQueue.main.async {
                assets = fetched
                fetchState = fetched.isEmpty ? .empty : .loaded
            }
        }
    }

    private func loadAndPick(_ asset: PHAsset) {
        let manager = PHImageManager.default()
        let opts = PHImageRequestOptions()
        opts.isNetworkAccessAllowed = true
        opts.deliveryMode = .highQualityFormat
        opts.resizeMode = .none

        // Full image data first, then a small thumb for the card preview.
        manager.requestImageDataAndOrientation(for: asset, options: opts) { data, _, _, _ in
            guard let data = data else { return }
            let thumbOpts = PHImageRequestOptions()
            thumbOpts.deliveryMode = .fastFormat
            thumbOpts.resizeMode = .exact
            manager.requestImage(
                for: asset,
                targetSize: CGSize(width: 320, height: 320),
                contentMode: .aspectFill,
                options: thumbOpts
            ) { thumb, _ in
                let thumbData = thumb?.jpegData(compressionQuality: 0.7)
                DispatchQueue.main.async {
                    onPick(data, thumbData)
                    dismiss()
                }
            }
        }
    }
}

private struct AssetThumbnail: View {
    let asset: PHAsset
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Rectangle().fill(GQColors.overlayLight)
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        let opts = PHImageRequestOptions()
        opts.deliveryMode = .opportunistic
        opts.resizeMode = .fast
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 220, height: 220),
            contentMode: .aspectFill,
            options: opts
        ) { result, _ in
            DispatchQueue.main.async { image = result }
        }
    }
}

#endif
