import AppKit
import ImageIO
import SwiftUI

struct ClipThumbnailView: View {
    @Environment(\.colorScheme) private var colorScheme
    let item: ClipItem

    @State private var image: NSImage?
    private var palette: ThemePalette { Theme.palette(for: colorScheme) }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFit()
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 30))
                    .foregroundStyle(palette.textTertiary.swiftUIColor)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: item.imageFileName) {
            image = nil
            guard let url = ClipboardStore.shared.imageURL(for: item) else { return }
            image = await ClipThumbnailProvider.shared.thumbnail(for: url)
        }
    }
}

@MainActor
private final class ClipThumbnailProvider {
    static let shared = ClipThumbnailProvider()

    private let cache = NSCache<NSString, NSImage>()
    private var inFlight: [String: Task<CGImage?, Never>] = [:]

    private init() {
        cache.countLimit = 64
        cache.totalCostLimit = 8_000_000
    }

    func thumbnail(for url: URL) async -> NSImage? {
        let key = url.lastPathComponent as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let path = url.path
        let task: Task<CGImage?, Never>
        if let existing = inFlight[path] {
            task = existing
        } else {
            task = Task.detached(priority: .utility) {
                autoreleasepool {
                    guard let source = CGImageSourceCreateWithURL(
                        URL(fileURLWithPath: path) as CFURL,
                        nil
                    ) else { return nil }
                    let options: [CFString: Any] = [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceShouldCacheImmediately: true,
                        kCGImageSourceThumbnailMaxPixelSize: 512
                    ]
                    return CGImageSourceCreateThumbnailAtIndex(
                        source,
                        0,
                        options as CFDictionary
                    )
                }
            }
            inFlight[path] = task
        }

        let cgImage = await task.value
        inFlight[path] = nil
        guard let cgImage else { return nil }

        let image = NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
        cache.setObject(
            image,
            forKey: key,
            cost: cgImage.bytesPerRow * cgImage.height
        )
        return image
    }
}
