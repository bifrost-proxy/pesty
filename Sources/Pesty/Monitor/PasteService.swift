import AppKit
import Carbon.HIToolbox
import OSLog

@MainActor
enum PasteService {
    struct AccessibilityResetCommand: Equatable, Sendable {
        let executable: String
        let arguments: [String]
    }

    private static let applicationBundleIdentifier = "com.bifrostproxy.pesty"
    #if !MAS
    private static var requestedAccessibilityThisLaunch = false
    private static let logger = Logger(
        subsystem: "com.bifrostproxy.pesty",
        category: "direct-paste"
    )
    #endif

    @discardableResult
    static func copy(_ item: ClipItem, to pasteboard: NSPasteboard = .general) -> Int {
        if item.type == .image {
            guard let img = ClipboardStore.shared.loadImage(for: item) else {
                return pasteboard.changeCount
            }
            pasteboard.clearContents()
            pasteboard.writeObjects([img])
            return pasteboard.changeCount
        }
        pasteboard.clearContents()
        switch item.type {
        case .image:
            break
        case .file:
            let urls = item.fileURLs.compactMap { URL(string: $0) }
            if !urls.isEmpty { pasteboard.writeObjects(urls as [NSURL]) }
            if let t = item.text { pasteboard.setString(t, forType: .string) }
        case .color:
            if let hex = item.colorHex, let c = NSColor(hex: hex) {
                pasteboard.writeObjects([c])
                pasteboard.setString(hex, forType: .string)
            }
        case .richText:
            if let rtf = item.rtfData { pasteboard.setData(rtf, forType: .rtf) }
            if let t = item.text { pasteboard.setString(t, forType: .string) }
        case .text, .link:
            if let t = item.text { pasteboard.setString(t, forType: .string) }
        }
        return pasteboard.changeCount
    }

    static func paste(
        _ item: ClipItem,
        into targetApp: NSRunningApplication?,
        focusedElement: AXUIElement? = nil,
        forceDirectPaste: Bool = false,
        monitor: ClipboardMonitor
    ) {
        let change = copy(item)
        monitor.suppressUntilChangeCount = change
        if Settings.shared.playSound { NSSound(named: "Pop")?.play() }

        guard let target = targetApp, !target.isTerminated else { return }
        target.activate()

        #if MAS
        // Mac App Store (sandboxed) build: copy the clip and return focus to the
        // app the user came from so they can paste with ⌘V. No Accessibility
        // APIs and no synthetic keystrokes are used.
        #else
        // Direct-download build: optionally paste straight into the active app by
        // synthesizing ⌘V. This requires the user's Accessibility grant.
        guard forceDirectPaste || Settings.shared.pasteDirectly else { return }
        guard AXIsProcessTrusted() else {
            logger.error("Direct paste skipped because Accessibility is not trusted")
            if !requestedAccessibilityThisLaunch {
                requestedAccessibilityThisLaunch = true
                ensureAccessibility(prompt: true)
            }
            return
        }
        logger.info(
            "Direct paste targeting bundle=\(target.bundleIdentifier ?? "unknown", privacy: .public), pid=\(target.processIdentifier)"
        )
        waitForFrontmost(
            target,
            focusedElement: focusedElement,
            attempts: 40
        )
        #endif
    }

    #if !MAS
    static func captureFocusedElement(
        in app: NSRunningApplication
    ) -> AXUIElement? {
        guard AXIsProcessTrusted(), !app.isTerminated else { return nil }
        let applicationElement = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedUIElementAttribute as CFString,
            &value
        )
        guard result == .success, let value else {
            logger.error(
                "Could not capture focused element for bundle=\(app.bundleIdentifier ?? "unknown", privacy: .public), error=\(result.rawValue)"
            )
            return nil
        }
        logger.info(
            "Captured focused element for bundle=\(app.bundleIdentifier ?? "unknown", privacy: .public)"
        )
        return (value as! AXUIElement)
    }

    private static func waitForFrontmost(
        _ app: NSRunningApplication,
        focusedElement: AXUIElement?,
        attempts: Int
    ) {
        guard attempts > 0, !app.isTerminated else { return }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
            let focusRestored = restoreFocus(to: focusedElement)
            logger.info("Target is frontmost; focused element restored=\(focusRestored)")
            DispatchQueue.main.asyncAfter(deadline: .now() + (focusRestored ? 0.04 : 0.08)) {
                sendCommandV()
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            waitForFrontmost(
                app,
                focusedElement: focusedElement,
                attempts: attempts - 1
            )
        }
    }

    private static func restoreFocus(to element: AXUIElement?) -> Bool {
        guard let element else { return false }
        let result = AXUIElementSetAttributeValue(
            element,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        )
        return result == .success
    }

    private static func sendCommandV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let v = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        logger.info("Posted Command-V")
    }

    @discardableResult
    static func ensureAccessibility(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    static func accessibilityResetCommand() -> AccessibilityResetCommand {
        AccessibilityResetCommand(
            executable: "/usr/bin/tccutil",
            arguments: [
                "reset",
                "Accessibility",
                applicationBundleIdentifier,
            ]
        )
    }

    static func openAccessibilitySettings(forceGuide: Bool = false) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        guard NSWorkspace.shared.open(url) else { return }
        AccessibilitySettingsGuideController.shared.present(
            force: forceGuide
        )
    }

    /// Removes only Pesty's stale Accessibility authorization so macOS can
    /// register the current ad-hoc-signed build. The user must still grant
    /// access in System Settings.
    static func resetAccessibilityAuthorization() async -> String? {
        let command = accessibilityResetCommand()
        return await Task.detached(priority: .userInitiated) {
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()
            process.executableURL = URL(fileURLWithPath: command.executable)
            process.arguments = command.arguments
            process.standardOutput = stdout
            process.standardError = stderr

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                let detail = error.localizedDescription
                NSLog("Pesty Accessibility reset failed to start: %@", detail)
                return detail
            }

            guard process.terminationStatus == 0 else {
                let data = stderr.fileHandleForReading.readDataToEndOfFile()
                let detail = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let message = detail?.isEmpty == false
                    ? detail!
                    : "tccutil exited with status \(process.terminationStatus)"
                NSLog("Pesty Accessibility reset failed: %@", message)
                return message
            }
            return nil
        }.value
    }
    #endif
}
