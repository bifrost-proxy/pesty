import AppKit
import CoreGraphics
import SwiftUI

final class BarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class BarHostingView: NSHostingView<BarView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class BarWindowController: NSWindowController, NSWindowDelegate {

    /// Full-screen Spaces can place their content above the Dock window level.
    /// Keep the clipboard panel above ordinary application and system overlay
    /// content while remaining below WindowServer's shielding windows.
    private static let presentationLevel = NSWindow.Level(
        rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 1
    )

    private var isPresenting = false
    private var isDismissing = false
    private var hideCompletions: [() -> Void] = []
    private var localOutsideClickMonitor: Any?
    private var globalOutsideClickMonitor: Any?

    init() {
        let initialScreenFrame = NSScreen.main?.frame
            ?? NSRect(x: 0, y: 0, width: 800, height: 360)
        let initialHeight = CGFloat(Settings.shared.barHeight)
        let initialFrame = NSRect(
            x: initialScreenFrame.minX,
            y: initialScreenFrame.minY,
            width: initialScreenFrame.width,
            height: initialHeight
        )
        let panel = BarPanel(
            contentRect: initialFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.isFloatingPanel = true
        panel.level = Self.presentationLevel
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
        ]
        panel.isMovable = false
        panel.contentView = BarHostingView(rootView: BarView())
        super.init(window: panel)
        panel.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    func show() {
        guard let panel = window else { return }
        isPresenting = true
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main ?? NSScreen.screens.first else { isPresenting = false; return }
        let screenFrame = screen.frame
        let height = CGFloat(Settings.shared.barHeight)
        let onScreen = NSRect(
            x: screenFrame.minX,
            y: screenFrame.minY,
            width: screenFrame.width,
            height: height
        )
        panel.makeFirstResponder(nil)
        panel.alphaValue = 0
        panel.setFrame(onScreen, display: false)
        // Reassert the level on every presentation because macOS can reorder
        // an auxiliary panel while entering or leaving a full-screen Space.
        panel.level = Self.presentationLevel
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
        ]
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.makeFirstResponder(nil)
        startOutsideClickMonitoring()

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .linear)
            panel.animator().alphaValue = 1
        }, completionHandler: { [weak self] in
            DispatchQueue.main.async {
                guard let self, let panel = self.window else { return }
                panel.contentView?.layoutSubtreeIfNeeded()
                NotificationCenter.default.post(
                    name: .pestyBarDidFinishPresentation,
                    object: panel
                )
                self.isPresenting = false
            }
        })
    }

    func hide(completion: (() -> Void)? = nil) {
        if let completion {
            hideCompletions.append(completion)
        }
        guard let panel = window, panel.isVisible else {
            finishHiding()
            return
        }
        guard !isDismissing else { return }
        isDismissing = true
        stopOutsideClickMonitoring()
        panel.makeFirstResponder(nil)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.08
            ctx.timingFunction = CAMediaTimingFunction(name: .linear)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            panel.orderOut(nil)
            self?.finishHiding()
        })
    }

    func windowDidResignKey(_ notification: Notification) {
        guard !isPresenting,
              !AppController.shared.suppressAutoHide,
              !ClipPreviewWindowController.shared.owns(NSApp.keyWindow)
        else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.window?.isKeyWindow != true,
                  !ClipPreviewWindowController.shared.owns(NSApp.keyWindow),
                  !self.isMouseInsidePestyWindows else { return }
            AppController.shared.hideBar()
        }
    }

    private func startOutsideClickMonitoring() {
        stopOutsideClickMonitoring()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

        localOutsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self else { return event }
            let panelWindowNumber = self.window?.windowNumber
            if event.windowNumber == panelWindowNumber,
               AssistantPopoverController.shared.dismissForPanelInteraction(
                at: NSEvent.mouseLocation
               ) {
                return event
            }
            if event.windowNumber != panelWindowNumber,
               !ClipPreviewWindowController.shared.owns(event.window),
               !self.isMouseInsidePestyWindows {
                DispatchQueue.main.async { [weak self] in
                    self?.hideForOutsideInteraction()
                }
            }
            return event
        }

        globalOutsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isMouseInsidePestyWindows else { return }
                self.hideForOutsideInteraction()
            }
        }
    }

    private func stopOutsideClickMonitoring() {
        if let monitor = localOutsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            localOutsideClickMonitor = nil
        }
        if let monitor = globalOutsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalOutsideClickMonitor = nil
        }
    }

    private func hideForOutsideInteraction() {
        guard !isPresenting,
              window?.isVisible == true,
              !isMouseInsidePestyWindows,
              !AppController.shared.suppressAutoHide else { return }
        AppController.shared.hideBar()
    }

    private var isMouseInsidePestyWindows: Bool {
        let isInsideBar = window?.isVisible == true
            && window?.frame.contains(NSEvent.mouseLocation) == true
        let isInsideAssistant =
            AssistantPopoverController.shared.screenFrame?
                .contains(NSEvent.mouseLocation) == true
        return isInsideBar
            || isInsideAssistant
            || ClipPreviewWindowController.shared.isMouseInside
    }

    private func finishHiding() {
        isDismissing = false
        let completions = hideCompletions
        hideCompletions.removeAll()
        completions.forEach { $0() }
    }
}
