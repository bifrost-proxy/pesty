import AppKit
import SwiftUI

enum AssistantPopoverKind: Equatable {
    case translation
    case explanation
}

enum AssistantPopoverLayout {
    static let width: CGFloat = 404
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
    /// with the rendered source and result, and scrolls only after reaching the
    /// reading limit.
    static func preferredTranslationHeight(
        sourceText: String,
        translation: String
    ) -> CGFloat {
        guard !translation.isEmpty else { return translationDefaultHeight }

        let sourceFont = NSFont.systemFont(ofSize: 12)
        let bodyFont = NSFont.systemFont(ofSize: 15)
        let textWidth = width - 28
        let sourceLineHeight = lineHeight(for: sourceFont)
        let sourceTextHeight = min(
            sourceLineHeight * 2,
            measuredHeight(
                for: sourceText,
                font: sourceFont,
                width: textWidth - 20
            )
        )
        let sourcePreviewHeight = max(
            sourceLineHeight,
            sourceTextHeight
        ) + 14
        let translationHeight = max(
            lineHeight(for: bodyFont),
            measuredHeight(
                for: translation,
                font: bodyFont,
                width: textWidth
            )
        )
        let chromeHeight: CGFloat = 44 + 1 + 28 + 24 + 18 + 18
        let naturalHeight =
            chromeHeight + sourcePreviewHeight + translationHeight
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
    private var itemID: UUID?
    private var remainingAnchorRetries = 0

    private override init() {
        super.init()
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.delegate = self
        popover.contentSize = AssistantPopoverLayout.contentSize(for: .translation)
    }

    var isPresented: Bool { popover.isShown }

    var screenFrame: NSRect? {
        popover.contentViewController?.view.window?.frame
    }

    var contentViewForScreenshot: NSView? {
        popover.contentViewController?.view
    }

    func present(kind: AssistantPopoverKind, for itemID: UUID) {
        self.kind = kind
        self.itemID = itemID
        remainingAnchorRetries = 8
        configureContent(for: kind)
        showWhenAnchorIsReady()
    }

    func dismiss(kind requestedKind: AssistantPopoverKind? = nil) {
        guard requestedKind == nil || requestedKind == kind else { return }
        popover.close()
        kind = nil
        itemID = nil
        remainingAnchorRetries = 0
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
        itemID = nil
        remainingAnchorRetries = 0
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

    private func showWhenAnchorIsReady() {
        guard let itemID else { return }
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
        if popover.isShown {
            popover.close()
        }
        let positioningRect = anchorView.bounds.insetBy(dx: 20, dy: 0)
        popover.show(
            relativeTo: positioningRect,
            of: anchorView,
            preferredEdge: .maxY
        )
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
