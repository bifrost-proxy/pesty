import AppKit
import ImageIO
import SwiftUI

struct ClipThumbnailView: View {
    @Environment(\.colorScheme) private var colorScheme
    let item: ClipItem

    @State private var image: NSImage?
    @State private var loadPhase: ClipImageLoadPhase = .checkingICloud
    private var palette: ThemePalette { Theme.palette(for: colorScheme) }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFit()
            } else {
                statusView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: item.imageFileName) {
            image = nil
            loadPhase = .checkingICloud
            guard let url = ClipboardStore.shared.imageURL(for: item) else { return }
            let thumbnail = await ClipThumbnailProvider.shared.thumbnail(
                for: url
            ) { phase in
                loadPhase = phase
            }
            guard !Task.isCancelled else { return }
            image = thumbnail
            loadPhase = thumbnail == nil ? .failed : .ready
        }
    }

    @ViewBuilder
    private var statusView: some View {
        VStack(spacing: 7) {
            if loadPhase == .checkingICloud || loadPhase == .reading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(
                    systemName: loadPhase == .downloadingICloud
                        ? "icloud.and.arrow.down"
                        : loadPhase == .failed
                            ? "icloud.slash"
                            : "photo"
                )
                .font(.system(size: 28))
            }

            if loadPhase == .downloadingICloud {
                Text("iCloud")
                    .font(.system(size: 11, weight: .medium))
            } else if loadPhase == .failed {
                Text(L10n.previewUnavailable)
                    .font(.system(size: 10))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }
        }
        .foregroundStyle(palette.textTertiary.swiftUIColor)
        .accessibilityLabel(accessibilityStatus)
    }

    private var accessibilityStatus: String {
        switch loadPhase {
        case .checkingICloud: return L10n.checkingICloudImage
        case .downloadingICloud: return L10n.downloadingICloudImage
        case .reading: return L10n.readingImage
        case .ready: return L10n.image
        case .failed: return L10n.iCloudImageDownloadFailed
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

    func thumbnail(
        for url: URL,
        phase: @escaping ClipImageMaterializer.PhaseHandler
    ) async -> NSImage? {
        let key = url.lastPathComponent as NSString
        if let cached = cache.object(forKey: key) {
            phase(.ready)
            return cached
        }

        guard await ClipImageMaterializer.prepare(at: url, phase: phase),
              !Task.isCancelled else { return nil }
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
        var result: CGImage?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(
            readingItemAt: url,
            options: [],
            error: &coordinationError
        ) { coordinatedURL in
            guard let source = CGImageSourceCreateWithURL(
                coordinatedURL as CFURL,
                nil
            ) else { return }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: 512
            ]
            result = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                options as CFDictionary
            )
        }
        return coordinationError == nil ? result : nil
    }
}
