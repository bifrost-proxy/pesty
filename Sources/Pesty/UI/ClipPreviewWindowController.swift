import AppKit
import ImageIO
import QuickLookUI

struct ClipPreviewContext {
    let item: ClipItem
    let cardFrameInScreen: NSRect
}

@MainActor
protocol ClipStripGeometryProviding: AnyObject {
    func previewContext(for itemID: UUID) -> ClipPreviewContext?
    func assistantPopoverAnchorView(for itemID: UUID) -> NSView?
}

@MainActor
final class ClipStripGeometryBridge {
    static let shared = ClipStripGeometryBridge()

    private weak var provider: (any ClipStripGeometryProviding)?

    func connect(_ provider: any ClipStripGeometryProviding) {
        self.provider = provider
    }

    func disconnect(_ provider: any ClipStripGeometryProviding) {
        guard self.provider === provider else { return }
        self.provider = nil
    }

    func context(for itemID: UUID) -> ClipPreviewContext? {
        provider?.previewContext(for: itemID)
    }

    func assistantPopoverAnchorView(for itemID: UUID) -> NSView? {
        provider?.assistantPopoverAnchorView(for: itemID)
    }
}

enum ClipPreviewContentKind: String {
    case text
    case image
    case quickLook
    case color
    case unavailable
}

struct ClipPreviewAutomationSnapshot {
    let isVisible: Bool
    let itemID: UUID?
    let contentKind: ClipPreviewContentKind?
    let windowFrame: NSRect
    let cardFrameInScreen: NSRect?
    let arrowTipInScreen: NSPoint?
    let hasTitleHeader: Bool
    let usesTranslucentBackground: Bool
    let textCharacterCount: Int
    let textNeedsVerticalScrolling: Bool
    let imageSourcePixelSize: NSSize?
    let imageDecodedPixelSize: NSSize?
    let imageLoadPhase: ClipImageLoadPhase?
    let quickLookURL: URL?
}

private final class ClipPreviewPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class ClipPreviewBubbleView: NSView {
    static let arrowHeight: CGFloat = 12
    private static let arrowWidth: CGFloat = 24

    private let bubbleView = NSVisualEffectView()
    private let arrowView = NSVisualEffectView()
    private let content: NSView

    var arrowTipX: CGFloat {
        didSet { needsLayout = true }
    }

    init(content: NSView, arrowTipX: CGFloat) {
        self.content = content
        self.arrowTipX = arrowTipX
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        for effectView in [bubbleView, arrowView] {
            effectView.material = .popover
            effectView.blendingMode = .behindWindow
            effectView.state = .active
            effectView.wantsLayer = true
            addSubview(effectView)
        }

        bubbleView.wantsLayer = true
        bubbleView.layer?.cornerRadius = 18
        bubbleView.layer?.masksToBounds = true
        bubbleView.addSubview(content)
        setAccessibilityIdentifier("pesty-preview-root")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) unavailable")
    }

    override func layout() {
        super.layout()

        let arrowHeight = Self.arrowHeight
        bubbleView.frame = NSRect(
            x: 0,
            y: arrowHeight,
            width: bounds.width,
            height: max(0, bounds.height - arrowHeight)
        )
        content.frame = bubbleView.bounds

        let arrowWidth = Self.arrowWidth
        let clampedTipX = min(
            bounds.maxX - arrowWidth / 2,
            max(bounds.minX + arrowWidth / 2, arrowTipX)
        )
        arrowView.frame = NSRect(
            x: clampedTipX - arrowWidth / 2,
            y: 0,
            width: arrowWidth,
            height: arrowHeight
        )

        let mask = CAShapeLayer()
        let path = CGMutablePath()
        path.move(to: CGPoint(x: arrowWidth / 2, y: 0))
        path.addLine(to: CGPoint(x: 0, y: arrowHeight))
        path.addLine(to: CGPoint(x: arrowWidth, y: arrowHeight))
        path.closeSubpath()
        mask.path = path
        arrowView.layer?.mask = mask
    }
}

private final class FilePreviewItem: NSObject, QLPreviewItem {
    let previewItemURL: URL?
    let previewItemTitle: String?

    init(url: URL, title: String) {
        previewItemURL = url
        previewItemTitle = title
    }
}

private struct DecodedPreviewImage: @unchecked Sendable {
    let image: CGImage
    let sourcePixelSize: NSSize
    let decodedPixelSize: NSSize
}

private struct ClipPreviewPlacement {
    let frame: NSRect
    let arrowTipX: CGFloat
}

private func previewImagePixelSize(from source: CGImageSource) -> NSSize? {
    guard let properties = CGImageSourceCopyPropertiesAtIndex(
            source,
            0,
            nil
          ) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
          let height = properties[kCGImagePropertyPixelHeight] as? NSNumber
    else {
        return nil
    }
    return NSSize(width: width.doubleValue, height: height.doubleValue)
}

private final class PreviewImageRequest: @unchecked Sendable {
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

private final class ClipPreviewImageDecoder: @unchecked Sendable {
    static let shared = ClipPreviewImageDecoder()

    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.bifrostproxy.pesty.preview-image-decoder"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    func pixelSize(at url: URL) async -> NSSize? {
        let request = PreviewImageRequest()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                queue.addOperation {
                    guard !request.isCancelled else {
                        continuation.resume(returning: nil)
                        return
                    }
                    let size = autoreleasepool {
                        Self.pixelSizeSynchronously(at: url)
                    }
                    continuation.resume(
                        returning: request.isCancelled ? nil : size
                    )
                }
            }
        } onCancel: {
            request.cancel()
        }
    }

    func decode(
        at url: URL,
        maximumPixelDimension: Int
    ) async -> DecodedPreviewImage? {
        let request = PreviewImageRequest()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                queue.addOperation {
                    guard !request.isCancelled else {
                        continuation.resume(returning: nil)
                        return
                    }
                    let decoded = autoreleasepool {
                        Self.decodeSynchronously(
                            at: url,
                            maximumPixelDimension: maximumPixelDimension
                        )
                    }
                    continuation.resume(
                        returning: request.isCancelled ? nil : decoded
                    )
                }
            }
        } onCancel: {
            request.cancel()
        }
    }

    private static func pixelSizeSynchronously(at url: URL) -> NSSize? {
        var result: NSSize?
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
            result = previewImagePixelSize(from: source)
        }
        return coordinationError == nil ? result : nil
    }

    private static func decodeSynchronously(
        at url: URL,
        maximumPixelDimension: Int
    ) -> DecodedPreviewImage? {
        var result: DecodedPreviewImage?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(
            readingItemAt: url,
            options: [],
            error: &coordinationError
        ) { coordinatedURL in
            guard let source = CGImageSourceCreateWithURL(
                coordinatedURL as CFURL,
                nil
            ), let sourceSize = previewImagePixelSize(from: source) else {
                return
            }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize:
                    min(2_047, max(1, maximumPixelDimension)),
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                options as CFDictionary
            ) else { return }
            result = DecodedPreviewImage(
                image: image,
                sourcePixelSize: sourceSize,
                decodedPixelSize: NSSize(
                    width: image.width,
                    height: image.height
                )
            )
        }
        return coordinationError == nil ? result : nil
    }
}

@MainActor
final class ClipPreviewWindowController:
    NSWindowController,
    NSWindowDelegate
{
    static let shared = ClipPreviewWindowController()

    private weak var parentWindow: NSWindow?
    private var previewedItem: ClipItem?
    private var previewContext: ClipPreviewContext?
    private var contentKind: ClipPreviewContentKind?
    private var textView: NSTextView?
    private var imageTask: Task<Void, Never>?
    private var imageSourcePixelSize: NSSize?
    private var imageDecodedPixelSize: NSSize?
    private var imageLoadPhase: ClipImageLoadPhase?
    private var quickLookView: QLPreviewView?
    private var quickLookItem: FilePreviewItem?
    private var quickLookURL: URL?
    private var fallbackURL: URL?
    private var selectionRefreshGeneration = 0
    private var constrainedFrame: NSRect?
    private var arrowTipX: CGFloat?
    private weak var bubbleView: ClipPreviewBubbleView?
    private var isApplyingConstrainedFrame = false

    private init() {
        super.init(window: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) unavailable")
    }

    private func ensureWindow() -> NSWindow {
        if isWindowLoaded, let window {
            return window
        }
        let panel = ClipPreviewPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
        ]
        panel.delegate = self
        window = panel
        return panel
    }

    var isVisible: Bool {
        isWindowLoaded && window?.isVisible == true
    }

    var isMouseInside: Bool {
        guard isWindowLoaded else { return false }
        guard let window, window.isVisible else { return false }
        return window.frame.contains(NSEvent.mouseLocation)
    }

    func owns(_ candidate: NSWindow?) -> Bool {
        guard isWindowLoaded else { return false }
        guard let window, let candidate else { return false }
        return window === candidate
    }

    func toggle(context: ClipPreviewContext, parentWindow: NSWindow) {
        if isVisible {
            dismiss()
        } else {
            present(context: context, parentWindow: parentWindow)
        }
    }

    func present(context: ClipPreviewContext, parentWindow: NSWindow) {
        _ = ensureWindow()
        self.parentWindow = parentWindow
        configure(context: context)
        if window?.parent !== parentWindow {
            if let existingParent = window?.parent, let window {
                existingParent.removeChildWindow(window)
            }
            if let window {
                parentWindow.addChildWindow(window, ordered: .above)
            }
        }
        if let window {
            window.level = NSWindow.Level(rawValue: parentWindow.level.rawValue + 1)
            window.orderFront(nil)
        }
    }

    func selectionDidChange(to itemID: UUID?) {
        guard isVisible else { return }
        selectionRefreshGeneration &+= 1
        let generation = selectionRefreshGeneration
        guard let itemID else {
            dismiss()
            return
        }
        refreshSelection(itemID: itemID, generation: generation, attempt: 0)
    }

    func dismiss() {
        selectionRefreshGeneration &+= 1
        imageTask?.cancel()
        imageTask = nil
        releaseQuickLook()
        textView = nil
        previewedItem = nil
        previewContext = nil
        contentKind = nil
        imageSourcePixelSize = nil
        imageDecodedPixelSize = nil
        fallbackURL = nil
        constrainedFrame = nil
        arrowTipX = nil
        bubbleView = nil

        guard isWindowLoaded, let window else { return }
        let wasKey = window.isKeyWindow
        window.orderOut(nil)
        if let parent = window.parent {
            parent.removeChildWindow(window)
        }
        window.contentView = nil
        if wasKey {
            parentWindow?.makeKey()
        }
        parentWindow = nil
    }

    func automationSnapshot() -> ClipPreviewAutomationSnapshot {
        guard isWindowLoaded else {
            return ClipPreviewAutomationSnapshot(
                isVisible: false,
                itemID: nil,
                contentKind: nil,
                windowFrame: .zero,
                cardFrameInScreen: nil,
                arrowTipInScreen: nil,
                hasTitleHeader: false,
                usesTranslucentBackground: false,
                textCharacterCount: 0,
                textNeedsVerticalScrolling: false,
                imageSourcePixelSize: nil,
                imageDecodedPixelSize: nil,
                imageLoadPhase: nil,
                quickLookURL: nil
            )
        }
        window?.contentView?.layoutSubtreeIfNeeded()
        let needsVerticalScrolling: Bool
        if let textView,
           let scrollView = textView.enclosingScrollView,
           let layoutManager = textView.layoutManager,
           let textContainer = textView.textContainer {
            layoutManager.ensureLayout(for: textContainer)
            needsVerticalScrolling =
                layoutManager.usedRect(for: textContainer).height
                > scrollView.contentSize.height
        } else {
            needsVerticalScrolling = false
        }
        return ClipPreviewAutomationSnapshot(
            isVisible: isVisible,
            itemID: previewedItem?.id,
            contentKind: contentKind,
            windowFrame: window?.frame ?? .zero,
            cardFrameInScreen: previewContext?.cardFrameInScreen,
            arrowTipInScreen: arrowTipX.flatMap { tipX in
                guard let origin = window?.frame.origin else { return nil }
                return NSPoint(x: origin.x + tipX, y: origin.y)
            },
            hasTitleHeader: false,
            usesTranslucentBackground: bubbleView != nil,
            textCharacterCount: textView?.string.count ?? 0,
            textNeedsVerticalScrolling: needsVerticalScrolling,
            imageSourcePixelSize: imageSourcePixelSize,
            imageDecodedPixelSize: imageDecodedPixelSize,
            imageLoadPhase: imageLoadPhase,
            quickLookURL: quickLookURL
        )
    }

    private func refreshSelection(
        itemID: UUID,
        generation: Int,
        attempt: Int
    ) {
        guard isVisible, generation == selectionRefreshGeneration else { return }
        if let context = ClipStripGeometryBridge.shared.context(for: itemID),
           let parentWindow {
            present(context: context, parentWindow: parentWindow)
            return
        }
        guard attempt < 4 else {
            dismiss()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            self?.refreshSelection(
                itemID: itemID,
                generation: generation,
                attempt: attempt + 1
            )
        }
    }

    private func configure(context: ClipPreviewContext) {
        imageTask?.cancel()
        imageTask = nil
        releaseQuickLook()
        textView = nil
        imageSourcePixelSize = nil
        imageDecodedPixelSize = nil
        imageLoadPhase = nil
        fallbackURL = nil
        previewedItem = context.item
        previewContext = context

        guard let parentWindow,
              let screen = parentWindow.screen
                ?? NSScreen.screens.first(where: {
                    $0.frame.intersects(context.cardFrameInScreen)
                })
                ?? NSScreen.main else { return }

        let preferredSize = preferredWindowSize(
            for: context.item,
            on: screen
        )
        let placement = previewPlacement(
            preferredSize: preferredSize,
            cardFrame: context.cardFrameInScreen,
            screen: screen
        )
        constrainedFrame = placement.frame
        arrowTipX = placement.arrowTipX
        applyConstrainedFrame()

        let content: NSView
        switch context.item.type {
        case .text, .richText, .link:
            contentKind = .text
            content = makeTextPreview(for: context.item)
        case .image:
            contentKind = .image
            content = makeImagePreview(
                for: context.item,
                screenScale: screen.backingScaleFactor
            )
        case .file:
            content = makeFilePreview(for: context.item)
        case .color:
            contentKind = .color
            content = makeColorPreview(for: context.item)
        }
        let rootView = makeRootView(
            content: content,
            arrowTipX: placement.arrowTipX
        )
        bubbleView = rootView
        window?.contentView = rootView
        window?.minSize = placement.frame.size
        window?.maxSize = placement.frame.size
        applyConstrainedFrame()
        scheduleConstrainedFrameChecks()
    }

    func windowDidMove(_ notification: Notification) {
        guard !isApplyingConstrainedFrame else { return }
        DispatchQueue.main.async { [weak self] in
            self?.applyConstrainedFrame()
        }
    }

    func windowDidResize(_ notification: Notification) {
        guard !isApplyingConstrainedFrame else { return }
        DispatchQueue.main.async { [weak self] in
            self?.applyConstrainedFrame()
        }
    }

    private func scheduleConstrainedFrameChecks() {
        for delay in [0.02, 0.10, 0.30] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                [weak self] in
                self?.applyConstrainedFrame()
            }
        }
    }

    private func applyConstrainedFrame() {
        guard let constrainedFrame,
              let window,
              !NSEqualRects(window.frame, constrainedFrame) else {
            return
        }
        isApplyingConstrainedFrame = true
        window.setFrame(constrainedFrame, display: true)
        isApplyingConstrainedFrame = false
    }

    private func preferredWindowSize(
        for item: ClipItem,
        on _: NSScreen
    ) -> NSSize {
        switch item.type {
        case .text, .richText, .link:
            return NSSize(width: 720, height: 600)
        case .file:
            return NSSize(width: 800, height: 560)
        case .color:
            return NSSize(width: 480, height: 320)
        case .image:
            return NSSize(width: 720, height: 480)
        }
    }

    private func previewPlacement(
        preferredSize: NSSize,
        cardFrame: NSRect,
        screen: NSScreen
    ) -> ClipPreviewPlacement {
        let bounds = screen.visibleFrame.insetBy(dx: 16, dy: 16)
        let width = min(max(320, preferredSize.width), min(900, bounds.width))
        let arrowTipY = max(bounds.minY, cardFrame.maxY + 4)
        let availableAbove = max(0, bounds.maxY - arrowTipY)
        let height = max(
            1,
            min(max(160, preferredSize.height), availableAbove)
        )
        let y = arrowTipY
        let centeredX = cardFrame.midX - width / 2
        let x = min(bounds.maxX - width, max(bounds.minX, centeredX))
        let arrowTipX = min(
            width - 18,
            max(18, cardFrame.midX - x)
        )
        return ClipPreviewPlacement(
            frame: NSRect(x: x, y: y, width: width, height: height),
            arrowTipX: arrowTipX
        )
    }

    private func makeRootView(
        content: NSView,
        arrowTipX: CGFloat
    ) -> ClipPreviewBubbleView {
        ClipPreviewBubbleView(content: content, arrowTipX: arrowTipX)
    }

    private func makeTextPreview(for item: ClipItem) -> NSView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.setAccessibilityIdentifier("pesty-preview-text-scroll")

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 680, height: 420))
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.isRichText = item.type == .richText
        textView.textContainerInset = NSSize(width: 16, height: 14)
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: 680,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.setAccessibilityIdentifier("pesty-preview-text")

        if item.type == .richText,
           let data = item.rtfData,
           let attributed = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
           ) {
            textView.textStorage?.setAttributedString(attributed)
        } else {
            textView.font = item.type == .link
                ? .monospacedSystemFont(ofSize: 13, weight: .regular)
                : .systemFont(ofSize: 14)
            textView.textColor = .textColor
            textView.string = item.text ?? ""
        }
        scrollView.documentView = textView
        self.textView = textView
        return scrollView
    }

    private func makeImagePreview(
        for item: ClipItem,
        screenScale: CGFloat
    ) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        container.setAccessibilityIdentifier("pesty-preview-image-container")

        let imageView = NSImageView()
        imageView.imageAlignment = .alignCenter
        imageView.imageScaling = .scaleProportionallyDown
        imageView.setAccessibilityIdentifier("pesty-preview-image")

        let progress = NSProgressIndicator()
        progress.style = .spinning
        progress.controlSize = .small
        progress.startAnimation(nil)

        let statusIcon = NSImageView()
        statusIcon.image = NSImage(
            systemSymbolName: "icloud",
            accessibilityDescription: nil
        )
        statusIcon.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: 26,
            weight: .regular
        )
        statusIcon.contentTintColor = .secondaryLabelColor

        let statusLabel = NSTextField(
            wrappingLabelWithString: L10n.checkingICloudImage
        )
        statusLabel.alignment = .center
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.setAccessibilityIdentifier(
            "pesty-preview-image-loading-status"
        )

        let retryButton = NSButton(
            title: L10n.retry,
            target: self,
            action: #selector(retryImagePreview)
        )
        retryButton.bezelStyle = .rounded
        retryButton.isHidden = true
        retryButton.setAccessibilityIdentifier(
            "pesty-preview-image-retry"
        )

        let statusStack = NSStackView(
            views: [statusIcon, progress, statusLabel, retryButton]
        )
        statusStack.orientation = .vertical
        statusStack.alignment = .centerX
        statusStack.spacing = 8

        let errorLabel = NSTextField(
            wrappingLabelWithString: L10n.previewUnavailable
        )
        errorLabel.alignment = .center
        errorLabel.textColor = .secondaryLabelColor
        errorLabel.isHidden = true

        [imageView, statusStack, errorLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview($0)
        }
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            imageView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            statusStack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            statusStack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            statusLabel.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor, constant: -48),
            errorLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            errorLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: container.leadingAnchor,
                constant: 24
            ),
            errorLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: container.trailingAnchor,
                constant: -24
            ),
        ])

        guard let url = ClipboardStore.shared.imageURL(for: item) else {
            progress.stopAnimation(nil)
            contentKind = .unavailable
            return makeUnavailablePreview(
                message: L10n.previewUnavailable,
                url: nil
            )
        }

        imageTask = Task {
            [weak self, weak imageView, weak statusStack, weak statusIcon,
             weak progress, weak statusLabel, weak retryButton,
             weak errorLabel] in
            guard let self else { return }
            let prepared = await ClipImageMaterializer.prepare(at: url) {
                [weak self, weak statusIcon, weak progress, weak statusLabel,
                 weak retryButton] phase in
                self?.imageLoadPhase = phase
                if phase == .failed {
                    self?.contentKind = .unavailable
                }
                self?.updateImageLoadingUI(
                    phase,
                    icon: statusIcon,
                    progress: progress,
                    label: statusLabel,
                    retryButton: retryButton
                )
            }
            guard prepared, !Task.isCancelled else { return }
            let sourcePixelSize =
                await ClipPreviewImageDecoder.shared.pixelSize(at: url)
            guard !Task.isCancelled else { return }
            guard let sourcePixelSize else {
                progress?.stopAnimation(nil)
                progress?.isHidden = true
                errorLabel?.isHidden = true
                self.contentKind = .unavailable
                self.imageLoadPhase = .failed
                self.updateImageLoadingUI(
                    .failed,
                    icon: statusIcon,
                    progress: progress,
                    label: statusLabel,
                    retryButton: retryButton
                )
                return
            }
            self.imageSourcePixelSize = sourcePixelSize
            let maximumPixelDimension =
                self.constrainWindowForImage(sourcePixelSize)
            let decoded = await ClipPreviewImageDecoder.shared.decode(
                at: url,
                maximumPixelDimension: maximumPixelDimension
            )
            guard !Task.isCancelled else { return }
            progress?.stopAnimation(nil)
            guard let decoded else {
                self.contentKind = .unavailable
                errorLabel?.isHidden = true
                self.imageLoadPhase = .failed
                self.updateImageLoadingUI(
                    .failed,
                    icon: statusIcon,
                    progress: progress,
                    label: statusLabel,
                    retryButton: retryButton
                )
                return
            }
            self.imageSourcePixelSize = decoded.sourcePixelSize
            self.imageDecodedPixelSize = decoded.decodedPixelSize
            let image = NSImage(
                cgImage: decoded.image,
                size: NSSize(
                    width: decoded.decodedPixelSize.width
                        / max(1, self.parentWindow?.screen?.backingScaleFactor
                            ?? screenScale),
                    height: decoded.decodedPixelSize.height
                        / max(1, self.parentWindow?.screen?.backingScaleFactor
                            ?? screenScale)
                )
            )
            imageView?.image = image
            self.imageLoadPhase = .ready
            statusStack?.isHidden = true
        }
        return container
    }

    private func updateImageLoadingUI(
        _ phase: ClipImageLoadPhase,
        icon: NSImageView?,
        progress: NSProgressIndicator?,
        label: NSTextField?,
        retryButton: NSButton?
    ) {
        switch phase {
        case .checkingICloud:
            icon?.image = NSImage(
                systemSymbolName: "icloud",
                accessibilityDescription: nil
            )
            icon?.isHidden = false
            progress?.isHidden = false
            progress?.startAnimation(nil)
            label?.stringValue = L10n.checkingICloudImage
            retryButton?.isHidden = true
        case .downloadingICloud:
            icon?.image = NSImage(
                systemSymbolName: "icloud.and.arrow.down",
                accessibilityDescription: nil
            )
            icon?.isHidden = false
            progress?.isHidden = false
            progress?.startAnimation(nil)
            label?.stringValue = L10n.downloadingICloudImage
            retryButton?.isHidden = true
        case .reading:
            icon?.image = NSImage(
                systemSymbolName: "photo",
                accessibilityDescription: nil
            )
            icon?.isHidden = false
            progress?.isHidden = false
            progress?.startAnimation(nil)
            label?.stringValue = L10n.readingImage
            retryButton?.isHidden = true
        case .ready:
            icon?.isHidden = true
            progress?.stopAnimation(nil)
            progress?.isHidden = true
            label?.stringValue = ""
            retryButton?.isHidden = true
        case .failed:
            icon?.image = NSImage(
                systemSymbolName: "icloud.slash",
                accessibilityDescription: nil
            )
            icon?.isHidden = false
            progress?.stopAnimation(nil)
            progress?.isHidden = true
            label?.stringValue = L10n.iCloudImageDownloadFailed
            retryButton?.isHidden = false
        }
    }

    @objc private func retryImagePreview() {
        guard let previewContext else { return }
        configure(context: previewContext)
    }

    private func constrainWindowForImage(_ sourcePixelSize: NSSize) -> Int {
        guard let previewContext,
              let parentWindow,
              let screen = parentWindow.screen else {
            let scale = max(1, parentWindow?.screen?.backingScaleFactor ?? 1)
            let currentSize = window?.frame.size ?? NSSize(width: 720, height: 480)
            return Int(
                ceil(
                    max(
                        currentSize.width - 24,
                        currentSize.height
                            - 24
                            - ClipPreviewBubbleView.arrowHeight
                    ) * scale
                )
            )
        }
        let scale = max(1, screen.backingScaleFactor)
        let preferredSize = NSSize(
            width: max(320, sourcePixelSize.width / scale + 24),
            height: max(
                220,
                sourcePixelSize.height / scale
                    + 24
                    + ClipPreviewBubbleView.arrowHeight
            )
        )
        let placement = previewPlacement(
            preferredSize: preferredSize,
            cardFrame: previewContext.cardFrameInScreen,
            screen: screen
        )
        constrainedFrame = placement.frame
        arrowTipX = placement.arrowTipX
        bubbleView?.arrowTipX = placement.arrowTipX
        window?.minSize = placement.frame.size
        window?.maxSize = placement.frame.size
        applyConstrainedFrame()
        scheduleConstrainedFrameChecks()
        return Int(
            ceil(
                max(
                    placement.frame.width - 24,
                    placement.frame.height
                        - 24
                        - ClipPreviewBubbleView.arrowHeight
                ) * scale
            )
        )
    }

    private func makeFilePreview(for item: ClipItem) -> NSView {
        let urls = item.fileURLs.compactMap(URL.init(string:))
        guard let url = urls.first,
              url.isFileURL,
              FileManager.default.fileExists(atPath: url.path) else {
            contentKind = .unavailable
            return makeUnavailablePreview(
                message: L10n.previewFileUnavailable,
                url: urls.first
            )
        }
        guard let preview = QLPreviewView(frame: .zero, style: .normal) else {
            contentKind = .unavailable
            return makeUnavailablePreview(
                message: L10n.previewUnavailable,
                url: url
            )
        }
        let previewItem = FilePreviewItem(url: url, title: item.displayTitle)
        preview.shouldCloseWithWindow = false
        preview.autostarts = false
        preview.previewItem = previewItem
        preview.setAccessibilityIdentifier("pesty-preview-quicklook")
        quickLookView = preview
        quickLookItem = previewItem
        quickLookURL = url
        contentKind = .quickLook
        return preview
    }

    private func makeColorPreview(for item: ClipItem) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor

        let swatch = NSView()
        swatch.wantsLayer = true
        swatch.layer?.cornerRadius = 14
        swatch.layer?.borderWidth = 1
        swatch.layer?.borderColor = NSColor.separatorColor.cgColor
        swatch.layer?.backgroundColor =
            item.colorHex.flatMap(NSColor.init(hex:))?.cgColor
            ?? NSColor.clear.cgColor

        let label = NSTextField(labelWithString: item.colorHex ?? L10n.color)
        label.font = .monospacedSystemFont(ofSize: 18, weight: .semibold)
        label.alignment = .center

        [swatch, label].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview($0)
        }
        NSLayoutConstraint.activate([
            swatch.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            swatch.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -18),
            swatch.widthAnchor.constraint(equalToConstant: 160),
            swatch.heightAnchor.constraint(equalToConstant: 110),
            label.topAnchor.constraint(equalTo: swatch.bottomAnchor, constant: 16),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
        ])
        return container
    }

    private func makeUnavailablePreview(message: String, url: URL?) -> NSView {
        fallbackURL = url
        let label = NSTextField(wrappingLabelWithString: message)
        label.alignment = .center
        label.textColor = .secondaryLabelColor
        label.font = .systemFont(ofSize: 13)

        let views: [NSView]
        if url != nil {
            let button = NSButton(
                title: L10n.revealInFinder,
                target: self,
                action: #selector(revealFallbackInFinder)
            )
            button.bezelStyle = .rounded
            views = [label, button]
        } else {
            views = [label]
        }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12

        let container = NSView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            stack.leadingAnchor.constraint(
                greaterThanOrEqualTo: container.leadingAnchor,
                constant: 24
            ),
            stack.trailingAnchor.constraint(
                lessThanOrEqualTo: container.trailingAnchor,
                constant: -24
            ),
        ])
        return container
    }

    @objc private func revealFallbackInFinder() {
        guard let fallbackURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([fallbackURL])
    }

    private func releaseQuickLook() {
        quickLookView?.previewItem = nil
        quickLookView?.close()
        quickLookView = nil
        quickLookItem = nil
        quickLookURL = nil
    }

}
