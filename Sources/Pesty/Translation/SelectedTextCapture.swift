import AppKit
import OSLog

struct SelectedTextContext: Equatable {
    let text: String
    let screenRect: NSRect
    let sourceBundleIdentifier: String?
}

struct PasteboardSnapshot: Equatable {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(
                uniqueKeysWithValues: item.types.compactMap { type in
                    item.data(forType: type).map { (type, $0) }
                }
            )
        }
    }

    @discardableResult
    func restore(to pasteboard: NSPasteboard) -> Int {
        pasteboard.clearContents()
        let restoredItems = items.map { values -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in values {
                item.setData(data, forType: type)
            }
            return item
        }
        if !restoredItems.isEmpty {
            pasteboard.writeObjects(restoredItems)
        }
        return pasteboard.changeCount
    }
}

enum SelectedTextCaptureFailure: Error, Equatable {
    case accessibilityPermissionRequired
    case noSelection
    case secureText
    case selectionLocationUnavailable

    var message: String {
        switch self {
        case .accessibilityPermissionRequired:
            return L10n.globalTranslationAccessibilityRequired
        case .noSelection:
            return L10n.selectTextToTranslate
        case .secureText:
            return L10n.secureTextCannotBeTranslated
        case .selectionLocationUnavailable:
            return L10n.selectedTextLocationUnavailable
        }
    }
}

enum SelectedTextScreenGeometry {
    static func appKitRect(
        fromAccessibilityRect rect: CGRect,
        primaryScreenMaxY: CGFloat
    ) -> NSRect {
        NSRect(
            x: rect.minX,
            y: primaryScreenMaxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    static func usableAnchorRect(
        _ rect: NSRect,
        screens: [NSRect]
    ) -> NSRect? {
        guard rect.width.isFinite,
              rect.height.isFinite,
              rect.minX.isFinite,
              rect.minY.isFinite,
              rect.width > 0,
              rect.height > 0 else {
            return nil
        }
        for screen in screens {
            let visibleSelection = rect.intersection(screen)
            if !visibleSelection.isNull,
               visibleSelection.width > 0,
               visibleSelection.height > 0 {
                return visibleSelection
            }
        }
        return nil
    }
}

#if !MAS
@MainActor
enum SelectedTextCaptureService {
    private static let logger = Logger(
        subsystem: "com.bifrostproxy.pesty",
        category: "global-translation"
    )

    static func capture(
        in application: NSRunningApplication?
    ) -> Result<SelectedTextContext, SelectedTextCaptureFailure> {
        guard AXIsProcessTrusted() else {
            logger.notice("selection-capture accessibility-permission-required")
            return .failure(.accessibilityPermissionRequired)
        }
        guard let application, !application.isTerminated else {
            logger.notice("selection-capture no-frontmost-application")
            return .failure(.noSelection)
        }

        let applicationElement = AXUIElementCreateApplication(
            application.processIdentifier
        )
        guard let focusedElement = copyElementAttribute(
            kAXFocusedUIElementAttribute,
            from: applicationElement
        ) else {
            logger.notice(
                "selection-capture no-focused-element bundle=\(application.bundleIdentifier ?? "unknown", privacy: .public)"
            )
            return .failure(.noSelection)
        }

        var candidate: AXUIElement? = focusedElement
        var foundTextWithoutBounds = false
        for _ in 0..<8 {
            guard let element = candidate else { break }
            if isSecureTextElement(element) {
                logger.notice(
                    "selection-capture secure-text bundle=\(application.bundleIdentifier ?? "unknown", privacy: .public)"
                )
                return .failure(.secureText)
            }
            if let selectedText = copyStringAttribute(
                kAXSelectedTextAttribute,
                from: element
            )?.trimmingCharacters(in: .whitespacesAndNewlines),
               !selectedText.isEmpty {
                guard let accessibilityRect = selectedTextBounds(for: element),
                      let appKitRect = convertedScreenRect(
                        from: accessibilityRect
                      ) else {
                    foundTextWithoutBounds = true
                    candidate = copyElementAttribute(
                        kAXParentAttribute,
                        from: element
                    )
                    continue
                }
                logger.notice(
                    "selection-capture success bundle=\(application.bundleIdentifier ?? "unknown", privacy: .public) characters=\(selectedText.count, privacy: .public)"
                )
                return .success(
                    SelectedTextContext(
                        text: selectedText,
                        screenRect: appKitRect,
                        sourceBundleIdentifier: application.bundleIdentifier
                    )
                )
            }
            candidate = copyElementAttribute(kAXParentAttribute, from: element)
        }

        if foundTextWithoutBounds {
            logger.notice(
                "selection-capture location-unavailable bundle=\(application.bundleIdentifier ?? "unknown", privacy: .public)"
            )
            return .failure(.selectionLocationUnavailable)
        }
        logger.notice(
            "selection-capture empty bundle=\(application.bundleIdentifier ?? "unknown", privacy: .public)"
        )
        return .failure(.noSelection)
    }

    private static func selectedTextBounds(
        for element: AXUIElement
    ) -> CGRect? {
        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeValue
        ) == .success,
        let rangeValue,
        CFGetTypeID(rangeValue) == AXValueGetTypeID() else {
            return nil
        }

        let rangeAXValue = rangeValue as! AXValue
        guard AXValueGetType(rangeAXValue) == .cfRange else { return nil }
        var selectedRange = CFRange()
        guard AXValueGetValue(
            rangeAXValue,
            .cfRange,
            &selectedRange
        ), selectedRange.length > 0 else {
            return nil
        }

        var boundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeAXValue,
            &boundsValue
        ) == .success,
        let boundsValue,
        CFGetTypeID(boundsValue) == AXValueGetTypeID() else {
            return nil
        }

        let boundsAXValue = boundsValue as! AXValue
        guard AXValueGetType(boundsAXValue) == .cgRect else { return nil }
        var bounds = CGRect.zero
        guard AXValueGetValue(boundsAXValue, .cgRect, &bounds) else {
            return nil
        }
        return bounds
    }

    private static func convertedScreenRect(
        from accessibilityRect: CGRect
    ) -> NSRect? {
        guard let primaryScreen = NSScreen.screens.first else { return nil }
        let converted = SelectedTextScreenGeometry.appKitRect(
            fromAccessibilityRect: accessibilityRect,
            primaryScreenMaxY: primaryScreen.frame.maxY
        )
        return SelectedTextScreenGeometry.usableAnchorRect(
            converted,
            screens: NSScreen.screens.map(\.frame)
        )
    }

    private static func isSecureTextElement(_ element: AXUIElement) -> Bool {
        copyStringAttribute(kAXSubroleAttribute, from: element)
            == kAXSecureTextFieldSubrole as String
    }

    private static func copyStringAttribute(
        _ attribute: String,
        from element: AXUIElement
    ) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success else {
            return nil
        }
        return value as? String
    }

    private static func copyElementAttribute(
        _ attribute: String,
        from element: AXUIElement
    ) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success,
        let value,
        CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }
}
#endif
