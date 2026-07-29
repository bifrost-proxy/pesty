import AppKit

@MainActor
enum AppIconProvider {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 64
        cache.totalCostLimit = 2_000_000
        return cache
    }()

    static func icon(forBundleID bundleID: String?) -> NSImage {
        guard let bundleID else { return generic }
        let key = bundleID as NSString
        if let cached = cache.object(forKey: key) { return cached }
        var source = generic
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            source = NSWorkspace.shared.icon(forFile: url.path)
        }
        let image = rasterized(source) ?? generic
        cache.setObject(image, forKey: key, cost: 64 * 64 * 4)
        return image
    }

    static let generic: NSImage =
        NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
        ?? NSImage()

    private static func rasterized(_ source: NSImage) -> NSImage? {
        let pixelSize = 64
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        source.draw(
            in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: 32, height: 32))
        bitmap.size = image.size
        image.addRepresentation(bitmap)
        return image
    }
}
