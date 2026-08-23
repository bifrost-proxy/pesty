import AppKit
import CoreGraphics
import OSLog
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

    private static let logger = Logger(
        subsystem: "com.bifrostproxy.pesty",
        category: "clipboard-panel"
    )

    /// Some full-screen applications create overlays at the screen-saver
    /// level. The assistive-technology level keeps this user-invoked panel
    /// deterministically above those windows while remaining below secure
    /// WindowServer shielding.
    static let presentationLevel = NSWindow.Level(
        rawValue: Int(CGWindowLevelForKey(.assistiveTechHighWindow))
    )
    static let normalCollectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces,
        .canJoinAllApplications,
        .fullScreenAuxiliary,
        .stationary,
        .ignoresCycle,
    ]
    static let activeSpaceRecoveryCollectionBehavior: NSWindow.CollectionBehavior = [
        .moveToActiveSpace,
        .canJoinAllApplications,
        .fullScreenAuxiliary,
        .stationary,
        .ignoresCycle,
    ]

    private var isPresenting = false
    private var isDismissing = false
    private var isReattachingToActiveSpace = false
    private var presentationGeneration: UInt = 0
    private var visibilityRecoveryGeneration: UInt = 0
    private var isVisibilityRecoveryActive = false
    private var hideCompletions: [() -> Void] = []
    private var localOutsideClickMonitor: Any?
    private var globalOutsideClickMonitor: Any?

    // Internal overrides make the WindowServer recovery state machine
    // deterministic in the automated panel regression.
    var visibilityRecoveryIntervals: [TimeInterval] = [0.15, 0.25, 0.35, 0.45]
    var panelOnScreenProvider: ((CGWindowID) -> Bool)?
    var activeSpaceReattachmentObserver: (() -> Void)?

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
        panel.canHide = false
        panel.level = Self.presentationLevel
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = Self.normalCollectionBehavior
        panel.isMovable = false
        panel.contentView = BarHostingView(rootView: BarView())
        super.init(window: panel)
        panel.delegate = self

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleActiveSpaceChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleApplicationActivation),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowOcclusionChange),
            name: NSWindow.didChangeOcclusionStateNotification,
            object: panel
        )
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    func show() {
        guard let panel = window else { return }
        presentationGeneration &+= 1
        visibilityRecoveryGeneration &+= 1
        isVisibilityRecoveryActive = false
        isPresenting = true
        isDismissing = false
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
        // A hidden all-Spaces panel may still be attached to the Space where
        // it was last shown. Every hotkey presentation first uses
        // moveToActiveSpace, so the same synchronous path both attaches the
        // panel to the current full-screen Space and places it at the highest
        // supported overlay level.
        attachToActiveSpaceForPresentation(panel)
        startOutsideClickMonitoring()

        let generation = presentationGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.presentationGeneration == generation,
                  self.window?.isVisible == true else { return }
            self.restorePresentationPolicyAndOrdering()
            self.isReattachingToActiveSpace = false
            self.beginVisibilityRecovery(reassertImmediately: false)
        }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .linear)
            panel.animator().alphaValue = 1
        }, completionHandler: { [weak self] in
            DispatchQueue.main.async {
                guard let self,
                      self.presentationGeneration == generation,
                      let panel = self.window else { return }
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
            presentationGeneration &+= 1
            visibilityRecoveryGeneration &+= 1
            isVisibilityRecoveryActive = false
            isReattachingToActiveSpace = false
            finishHiding()
            return
        }
        guard !isDismissing else { return }
        presentationGeneration &+= 1
        visibilityRecoveryGeneration &+= 1
        isVisibilityRecoveryActive = false
        isReattachingToActiveSpace = false
        isPresenting = false
        isDismissing = true
        let generation = presentationGeneration
        stopOutsideClickMonitoring()
        panel.makeFirstResponder(nil)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.08
            ctx.timingFunction = CAMediaTimingFunction(name: .linear)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            DispatchQueue.main.async {
                guard let self,
                      self.presentationGeneration == generation,
                      self.isDismissing else { return }
                panel.orderOut(nil)
                self.finishHiding()
            }
        })
    }

    func windowDidResignKey(_ notification: Notification) {
        guard !isPresenting,
              !isReattachingToActiveSpace,
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

    private func attachToActiveSpaceForPresentation(_ panel: NSWindow) {
        isReattachingToActiveSpace = true
        applyPresentationLevel(to: panel)
        panel.collectionBehavior = Self.activeSpaceRecoveryCollectionBehavior
        activeSpaceReattachmentObserver?()
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.makeFirstResponder(nil)
    }

    private func applyPresentationLevel(to panel: NSWindow) {
        // AppKit resets a panel to the floating level when this flag changes.
        (panel as? NSPanel)?.isFloatingPanel = true
        panel.canHide = false
        panel.hidesOnDeactivate = false
        panel.level = Self.presentationLevel
    }

    private func restorePresentationPolicyAndOrdering() {
        guard let panel = window, panel.isVisible else { return }
        applyPresentationLevel(to: panel)
        panel.collectionBehavior = Self.normalCollectionBehavior
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func isPanelOnScreen() -> Bool {
        guard let panel = window, panel.isVisible else { return false }
        let windowID = CGWindowID(panel.windowNumber)
        if let panelOnScreenProvider {
            return panelOnScreenProvider(windowID)
        }
        guard windowID != kCGNullWindowID,
              let windowInfo = CGWindowListCopyWindowInfo(
                .optionIncludingWindow,
                windowID
              )
                as? [[String: Any]],
              let panelInfo = windowInfo.first(where: {
                  ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == windowID
              }) else {
            return false
        }
        return (panelInfo[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue == true
    }

    func shouldHideForToggle() -> Bool {
        guard let panel = window,
              panel.isVisible,
              isPanelOnScreen() else { return false }
        return panel.isKeyWindow
            || AssistantPopoverController.shared.isPresented
            || ClipPreviewWindowController.shared.owns(NSApp.keyWindow)
    }

    private func beginVisibilityRecovery(
        restart: Bool = false,
        reassertImmediately: Bool = true
    ) {
        guard window?.isVisible == true,
              !isDismissing,
              !isReattachingToActiveSpace else { return }
        if reassertImmediately {
            restorePresentationPolicyAndOrdering()
        }
        guard restart || !isVisibilityRecoveryActive else { return }
        isVisibilityRecoveryActive = true
        visibilityRecoveryGeneration &+= 1
        runVisibilityRecoveryCheck(
            at: 0,
            recoveryGeneration: visibilityRecoveryGeneration,
            presentationGeneration: presentationGeneration
        )
    }

    private func runVisibilityRecoveryCheck(
        at index: Int,
        recoveryGeneration: UInt,
        presentationGeneration: UInt
    ) {
        guard index < visibilityRecoveryIntervals.count else {
            if visibilityRecoveryGeneration == recoveryGeneration,
               self.presentationGeneration == presentationGeneration {
                isVisibilityRecoveryActive = false
            }
            return
        }
        DispatchQueue.main.asyncAfter(
            deadline: .now() + visibilityRecoveryIntervals[index]
        ) { [weak self] in
            guard let self,
                  self.window?.isVisible == true,
                  !self.isDismissing,
                  self.visibilityRecoveryGeneration == recoveryGeneration,
                  self.presentationGeneration == presentationGeneration else {
                return
            }
            guard !self.isPanelOnScreen() else {
                self.isVisibilityRecoveryActive = false
                return
            }

            if index == 0 {
                self.restorePresentationPolicyAndOrdering()
            } else {
                self.reattachToActiveSpace(
                    recoveryGeneration: recoveryGeneration,
                    presentationGeneration: presentationGeneration
                )
            }
            self.runVisibilityRecoveryCheck(
                at: index + 1,
                recoveryGeneration: recoveryGeneration,
                presentationGeneration: presentationGeneration
            )
        }
    }

    private func reattachToActiveSpace(
        recoveryGeneration: UInt,
        presentationGeneration: UInt
    ) {
        guard let panel = window, !isReattachingToActiveSpace else { return }
        Self.logger.notice(
            "Clipboard panel window \(panel.windowNumber, privacy: .public) remains off screen; reattaching to the active Space"
        )
        let preservedFrame = panel.frame
        isReattachingToActiveSpace = true
        panel.orderOut(nil)

        DispatchQueue.main.async { [weak self] in
            guard let self,
                  let panel = self.window,
                  !self.isDismissing,
                  self.visibilityRecoveryGeneration == recoveryGeneration,
                  self.presentationGeneration == presentationGeneration else {
                self?.isReattachingToActiveSpace = false
                return
            }
            self.applyPresentationLevel(to: panel)
            panel.collectionBehavior = Self.activeSpaceRecoveryCollectionBehavior
            panel.setFrame(preservedFrame, display: false)
            self.activeSpaceReattachmentObserver?()
            panel.orderFrontRegardless()
            panel.makeKey()
            panel.makeFirstResponder(nil)

            DispatchQueue.main.async { [weak self] in
                guard let self,
                      !self.isDismissing,
                      self.visibilityRecoveryGeneration == recoveryGeneration,
                      self.presentationGeneration == presentationGeneration else {
                    self?.isReattachingToActiveSpace = false
                    return
                }
                self.restorePresentationPolicyAndOrdering()
                self.isReattachingToActiveSpace = false
            }
        }
    }

    @objc private func handleActiveSpaceChange() {
        guard window?.isVisible == true, !isDismissing else { return }
        beginVisibilityRecovery(restart: true)
    }

    @objc private func handleApplicationActivation() {
        guard window?.isVisible == true, !isDismissing else { return }
        beginVisibilityRecovery()
    }

    @objc private func handleWindowOcclusionChange() {
        guard let panel = window,
              panel.isVisible,
              !isDismissing,
              !isReattachingToActiveSpace,
              !panel.occlusionState.contains(.visible) else { return }
        beginVisibilityRecovery(restart: true)
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }
}
