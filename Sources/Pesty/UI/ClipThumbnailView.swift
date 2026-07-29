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
            let thumbnail = await ClipThumbnailProvider.shared.thumbnail(for: url)
            guard !Task.isCancelled else { return }
            image = thumbnail
        }
    }
}

@MainActor
private final class ClipThumbnailProvider {
    static let shared = ClipThumbnailProvider()

    private let cache = NSCache<NSString, NSImage>()
    private let decoder = ClipThumbnailDecoder()

    private init() {
        cache.countLimit = 8
        cache.totalCostLimit = 4_000_000
    }

    func thumbnail(for url: URL) async -> NSImage? {
        let key = url.lastPathComponent as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        guard let cgImage = await decoder.thumbnail(at: url),
              !Task.isCancelled else { return nil }

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

private final class ClipThumbnailRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

private final class ClipThumbnailDecoder: @unchecked Sendable {
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.bifrostproxy.pesty.thumbnail-decoder"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 2
        return queue
    }()

    func thumbnail(at url: URL) async -> CGImage? {
        let request = ClipThumbnailRequest()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                queue.addOperation {
                    guard !request.isCancelled else {
                        continuation.resume(returning: nil)
                        return
                    }
                    let image = autoreleasepool {
                        Self.decodeThumbnail(at: url)
                    }
                    continuation.resume(
                        returning: request.isCancelled ? nil : image
                    )
                }
            }
        } onCancel: {
            request.cancel()
        }
    }

    private static func decodeThumbnail(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
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
