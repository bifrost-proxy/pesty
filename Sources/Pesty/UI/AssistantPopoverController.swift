import AppKit
import SwiftUI

enum AssistantPopoverKind: Equatable {
    case translation
    case explanation
}

enum AssistantPopoverAnchor: Equatable {
    case clipItem(UUID)
    case screenRect(NSRect)
}

enum AssistantPopoverLayout {
    static let width: CGFloat = 480
    static let translationDefaultHeight: CGFloat = 320
    static let translationMaximumHeight: CGFloat = 520
    static let explanationDefaultHeight: CGFloat = 300
    static let explanationMaximumHeight: CGFloat = 460

    static func contentSize(for kind: AssistantPopoverKind) -> NSSize {
        NSSize(
            width: width,
            height: kind == .translation
                ? translationDefaultHeight
                : explanationDefaultHeight
        )
    }

    /// Translation starts tall enough for ordinary multi-line output, grows
    /// with the rendered result, and scrolls only after reaching the reading
    /// limit. The source already exists on the anchored clipboard card and is
    /// intentionally not repeated inside the popover.
    static func preferredTranslationHeight(
        translation: String
    ) -> CGFloat {
        guard !translation.isEmpty else { return translationDefaultHeight }

        let bodyFont = NSFont.systemFont(ofSize: 15)
        let textWidth = width - 28
        let translationHeight = max(
            lineHeight(for: bodyFont),
            measuredHeight(
                for: translation,
                font: bodyFont,
                width: textWidth
            )
        )
        let chromeHeight: CGFloat = 44 + 1 + 16 + 18 + 18
        let naturalHeight = chromeHeight + translationHeight
        return min(
            translationMaximumHeight,
            max(translationDefaultHeight, ceil(naturalHeight))
        )
    }

    /// Explanation starts roomy for a short answer, grows with the generated
    /// text, and stops at a deliberate reading limit. The board's result area
    /// then scrolls rather than extending across the clipboard strip.
    static func preferredExplanationHeight(sourceText: String, explanation: String) -> CGFloat {
        guard !explanation.isEmpty else { return explanationDefaultHeight }

        let sourceFont = NSFont.systemFont(ofSize: 10.5)
        let bodyFont = NSFont.systemFont(ofSize: 13)
        let textWidth = width - 20
        let sourceLineHeight = lineHeight(for: sourceFont)
        let sourceTextHeight = min(sourceLineHeight, measuredHeight(
            for: sourceText,
            font: sourceFont,
            width: textWidth
        ))
        // The source preview always includes its vertical padding, even for an
        // exceptionally short clip.
        let sourcePreviewHeight = max(sourceLineHeight, sourceTextHeight) + 10
        let explanationHeight = max(
            lineHeight(for: bodyFont),
            measuredHeight(for: explanation, font: bodyFont, width: textWidth)
        )
        let chromeHeight: CGFloat = 44 + 1 + 20 + 18 + 16 + 18
        let naturalHeight = chromeHeight + sourcePreviewHeight + explanationHeight
        return min(explanationMaximumHeight, max(explanationDefaultHeight, ceil(naturalHeight)))
    }

    private static func measuredHeight(for text: String, font: NSFont, width: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        return ceil((text as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        ).height)
    }

    private static func lineHeight(for font: NSFont) -> CGFloat {
        ceil(font.ascender - font.descender + font.leading)
    }
}

/// Keeps the currently rendered card view available as a native popover anchor.
/// The reference is deliberately weak: collection cells remain reusable and are
/// never retained by an AI presentation.
@MainActor
final class SelectedClipPopoverAnchor {
    static let shared = SelectedClipPopoverAnchor()

    private weak var view: NSView?
    private(set) var itemID: UUID?

    private init() {}

    func update(itemID: UUID, view: NSView) {
        self.itemID = itemID
        self.view = view
    }

    func view(for itemID: UUID) -> NSView? {
        guard self.itemID == itemID, view?.window != nil else { return nil }
        return view
    }

    func screenFrame(for itemID: UUID) -> NSRect? {
        guard let view = view(for: itemID), let window = view.window else { return nil }
        return window.convertToScreen(view.convert(view.bounds, to: nil))
    }
}

/// A native, card-anchored popover shared by translation and explanation.
/// NSPopover supplies the small pointer and handles screen-edge avoidance.
@MainActor
final class AssistantPopoverController: NSObject, NSPopoverDelegate {
    static let shared = AssistantPopoverController()

    private let popover = NSPopover()
    private var kind: AssistantPopoverKind?
    private var anchor: AssistantPopoverAnchor?
    private var remainingAnchorRetries = 0
    private var screenAnchorPanel: NSPanel?
    private var localOutsideClickMonitor: Any?
    private var globalOutsideClickMonitor: Any?

    private override init() {
        super.init()
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.delegate = self
        popover.contentSize = AssistantPopoverLayout.contentSize(for: .translation)
    }

    var isPresented: Bool { popover.isShown }
    var isWindowVisible: Bool {
        popover.contentViewController?.view.window?.isVisible == true
    }
    var isScreenAnchored: Bool { anchor?.isScreenRect == true }

    var screenFrame: NSRect? {
        popover.contentViewController?.view.window?.frame
    }
    var screenAnchorFrame: NSRect? { screenAnchorPanel?.frame }

    var contentViewForScreenshot: NSView? {
        popover.contentViewController?.view
    }

    func present(kind: AssistantPopoverKind, for itemID: UUID) {
        present(kind: kind, anchor: .clipItem(itemID))
    }

    func present(
        kind: AssistantPopoverKind,
        anchor: AssistantPopoverAnchor
    ) {
        if popover.isShown {
            closePopoverImmediately()
        }
        self.kind = kind
        self.anchor = anchor
        remainingAnchorRetries = 8
        configureContent(for: kind)
        showWhenAnchorIsReady()
    }

    func dismiss(kind requestedKind: AssistantPopoverKind? = nil) {
        guard requestedKind == nil || requestedKind == kind else { return }
        closePopoverImmediately()
        kind = nil
        anchor = nil
        remainingAnchorRetries = 0
        releaseScreenAnchor()
        stopOutsideClickMonitoring()
    }

    /// The clipboard panel remains interactive while an assistant card is
    /// visible. A click on the panel outside that card closes it and clears its
    /// transient result, so the next shortcut opens a fresh card.
    @discardableResult
    func dismissForPanelInteraction(at screenPoint: NSPoint) -> Bool {
        guard popover.isShown,
              screenFrame?.contains(screenPoint) != true else {
            return false
        }
        dismissActiveAssistant()
        return true
    }

    func dismissActiveAssistant() {
        switch kind {
        case .translation:
            TranslationCenter.shared.dismiss()
        case .explanation:
            ExplanationCenter.shared.dismiss()
        case nil:
            dismiss()
        }
    }

    func updatePreferredHeight(_ height: CGFloat, for requestedKind: AssistantPopoverKind) {
        guard kind == requestedKind else { return }
        let size = NSSize(width: AssistantPopoverLayout.width, height: height)
        popover.contentSize = size
        popover.contentViewController?.preferredContentSize = size
    }

    func popoverDidClose(_ notification: Notification) {
        kind = nil
        anchor = nil
        remainingAnchorRetries = 0
        releaseScreenAnchor()
        stopOutsideClickMonitoring()
    }

    private func configureContent(for kind: AssistantPopoverKind) {
        let root: AnyView
        switch kind {
        case .translation:
            root = AnyView(TranslationBoardView())
        case .explanation:
            root = AnyView(ExplanationBoardView())
        }
        popover.contentViewController = NSHostingController(rootView: root)
        let size = AssistantPopoverLayout.contentSize(for: kind)
        popover.contentSize = size
        popover.contentViewController?.preferredContentSize = size
    }

    /// Assistant state is cleared as part of the same shortcut action that
    /// dismisses the popover. Letting AppKit animate that close would briefly
    /// render the now-empty SwiftUI board inside the fading popover, producing
    /// a translucent ghost frame. Opening can still animate; closing is
    /// deliberately synchronous.
    private func closePopoverImmediately() {
        let shouldAnimateOpening = popover.animates
        popover.animates = false
        popover.close()
        popover.animates = shouldAnimateOpening
    }

    private func showWhenAnchorIsReady() {
        guard let anchor else { return }
        switch anchor {
        case .clipItem(let itemID):
            showWhenClipAnchorIsReady(itemID: itemID)
        case .screenRect(let screenRect):
            showAtScreenRect(screenRect)
        }
    }

    private func showWhenClipAnchorIsReady(itemID: UUID) {
        let resolvedAnchor =
            SelectedClipPopoverAnchor.shared.view(for: itemID)
            ?? ClipStripGeometryBridge.shared.assistantPopoverAnchorView(
                for: itemID
            )
        guard let anchorView = resolvedAnchor else {
            retryAfterLayout()
            return
        }
        SelectedClipPopoverAnchor.shared.update(itemID: itemID, view: anchorView)
        anchorView.layoutSubtreeIfNeeded()
        let positioningRect = anchorView.bounds.insetBy(dx: 20, dy: 0)
        popover.show(
            relativeTo: positioningRect,
            of: anchorView,
            preferredEdge: .maxY
        )
    }

    private func showAtScreenRect(_ selectionRect: NSRect) {
        guard let screen = NSScreen.screens.first(where: {
            $0.frame.intersects(selectionRect)
        }) ?? NSScreen.main ?? NSScreen.screens.first else {
            return
        }
        let visibleFrame = screen.visibleFrame
        let roomAbove = visibleFrame.maxY - selectionRect.maxY
        let roomBelow = selectionRect.minY - visibleFrame.minY
        let placesAbove = roomAbove >= roomBelow
        let anchorX = min(
            visibleFrame.maxX - 2,
            max(visibleFrame.minX + 2, selectionRect.midX)
        )
        let anchorY = placesAbove
            ? min(visibleFrame.maxY - 1, selectionRect.maxY)
            : max(visibleFrame.minY + 1, selectionRect.minY)
        let panelFrame = NSRect(
            x: anchorX - 1,
            y: anchorY - 1,
            width: 2,
            height: 2
        )

        releaseScreenAnchor()
        let panel = NSPanel(
            contentRect: panelFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
        ]
        let anchorView = NSView(frame: NSRect(origin: .zero, size: panelFrame.size))
        panel.contentView = anchorView
        panel.orderFrontRegardless()
        screenAnchorPanel = panel

        popover.show(
            relativeTo: anchorView.bounds,
            of: anchorView,
            preferredEdge: placesAbove ? .maxY : .minY
        )
        startOutsideClickMonitoring()
    }

    private func releaseScreenAnchor() {
        screenAnchorPanel?.orderOut(nil)
        screenAnchorPanel = nil
    }

    private func startOutsideClickMonitoring() {
        stopOutsideClickMonitoring()
        localOutsideClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self,
                  self.anchor?.isScreenRect == true,
                  self.screenFrame?.contains(NSEvent.mouseLocation) != true else {
                return event
            }
            self.dismissActiveAssistant()
            return event
        }
        globalOutsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self,
                      self.anchor?.isScreenRect == true,
                      self.screenFrame?.contains(NSEvent.mouseLocation) != true else {
                    return
                }
                self.dismissActiveAssistant()
            }
        }
    }

    private func stopOutsideClickMonitoring() {
        if let localOutsideClickMonitor {
            NSEvent.removeMonitor(localOutsideClickMonitor)
            self.localOutsideClickMonitor = nil
        }
        if let globalOutsideClickMonitor {
            NSEvent.removeMonitor(globalOutsideClickMonitor)
            self.globalOutsideClickMonitor = nil
        }
    }

    private func retryAfterLayout() {
        guard remainingAnchorRetries > 0 else {
            NSLog(
                "Pesty assistant popover could not resolve the selected card anchor"
            )
            return
        }
        remainingAnchorRetries -= 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            self?.showWhenAnchorIsReady()
        }
    }
}

private extension AssistantPopoverAnchor {
    var isScreenRect: Bool {
        if case .screenRect = self { return true }
        return false
    }
}
