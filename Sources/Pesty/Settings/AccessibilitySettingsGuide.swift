#if !MAS
import AppKit
import SwiftUI

struct AccessibilitySettingsGuidePresentation: Equatable {
    let highlightFrame: CGRect
}

enum AccessibilitySettingsGuideLayout {
    static let referenceWindowSize = CGSize(width: 723, height: 470)

    static func presentation(
        in windowSize: CGSize
    ) -> AccessibilitySettingsGuidePresentation {
        return AccessibilitySettingsGuidePresentation(
            highlightFrame: applicationListFrame(in: windowSize)
        )
    }

    static func applicationListFrame(in windowSize: CGSize) -> CGRect {
        let x = min(max(220, windowSize.width * 0.3085), 290)
        return CGRect(
            x: x,
            y: 52,
            width: max(260, windowSize.width - x - 12),
            height: max(260, windowSize.height - 64)
        )
    }
}

@MainActor
final class AccessibilitySettingsGuideController: NSObject {
    static let shared = AccessibilitySettingsGuideController()

    private static let systemSettingsBundleIdentifiers: Set<String> = [
        "com.apple.systempreferences",
        "com.apple.SystemSettings",
    ]

    private var panel: NSPanel?
    private var timer: Timer?
    private var expiresAt = Date.distantPast
    private var forcePresentation = false

    private(set) var isPresenting = false

    func present(force: Bool = false) {
        guard force || !AXIsProcessTrusted() else {
            dismiss()
            return
        }

        forcePresentation = force
        expiresAt = Date().addingTimeInterval(180)
        ensurePanel()
        startTracking()
        refresh()
    }

    func dismiss() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        isPresenting = false
        forcePresentation = false
    }

    private func ensurePanel() {
        if let panel {
            panel.contentView = NSHostingView(
                rootView: AccessibilitySettingsGuideOverlay()
            )
            return
        }

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]
        panel.contentView = NSHostingView(
            rootView: AccessibilitySettingsGuideOverlay()
        )
        self.panel = panel
    }

    private func startTracking() {
        guard timer == nil else { return }
        let timer = Timer(
            timeInterval: 0.06,
            target: self,
            selector: #selector(refresh),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    @objc private func refresh() {
        if Date() >= expiresAt
            || (!forcePresentation && AXIsProcessTrusted()) {
            dismiss()
            return
        }

        guard let frontmostBundleIdentifier =
                NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
              Self.systemSettingsBundleIdentifiers.contains(
                  frontmostBundleIdentifier
              ),
              let frame = Self.systemSettingsWindowFrame() else {
            panel?.orderOut(nil)
            isPresenting = false
            return
        }

        panel?.setFrame(frame, display: true)
        panel?.orderFrontRegardless()
        isPresenting = true
    }

    private static func systemSettingsWindowFrame() -> NSRect? {
        let options: CGWindowListOption = [
            .optionOnScreenOnly,
            .excludeDesktopElements,
        ]
        guard let windows = CGWindowListCopyWindowInfo(
            options,
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        let candidates = windows.compactMap { window -> CGRect? in
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t,
                  let application = NSRunningApplication(
                      processIdentifier: ownerPID
                  ),
                  let bundleIdentifier = application.bundleIdentifier,
                  systemSettingsBundleIdentifiers.contains(bundleIdentifier),
                  let bounds = window[kCGWindowBounds as String]
                    as? NSDictionary,
                  let frame = CGRect(
                      dictionaryRepresentation: bounds
                  ),
                  frame.width >= 520,
                  frame.height >= 400 else {
                return nil
            }
            return frame
        }

        guard let quartzFrame = candidates.max(by: {
            $0.width * $0.height < $1.width * $1.height
        }) else {
            return nil
        }
        return appKitFrame(for: quartzFrame)
    }

    private static func appKitFrame(for quartzFrame: CGRect) -> NSRect? {
        let center = CGPoint(x: quartzFrame.midX, y: quartzFrame.midY)

        for screen in NSScreen.screens {
            let key = NSDeviceDescriptionKey("NSScreenNumber")
            guard let number = screen.deviceDescription[key] as? NSNumber else {
                continue
            }
            let displayBounds = CGDisplayBounds(
                CGDirectDisplayID(number.uint32Value)
            )
            guard displayBounds.contains(center) else { continue }

            return NSRect(
                x: screen.frame.minX
                    + quartzFrame.minX
                    - displayBounds.minX,
                y: screen.frame.maxY
                    - (quartzFrame.minY - displayBounds.minY)
                    - quartzFrame.height,
                width: quartzFrame.width,
                height: quartzFrame.height
            )
        }
        return nil
    }
}

private struct AccessibilitySettingsGuideOverlay: View {
    @Bindable private var settings = Settings.shared

    var body: some View {
        GeometryReader { proxy in
            let presentation =
                AccessibilitySettingsGuideLayout.presentation(
                    in: proxy.size
                )
            let highlight = presentation.highlightFrame
            let prompt = L10n.accessibilityGuideListPrompt(
                language: settings.language
            )

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(nsColor: .systemBlue), lineWidth: 3)
                    .background(
                        RoundedRectangle(
                            cornerRadius: 8,
                            style: .continuous
                        )
                        .fill(Color(nsColor: .systemBlue).opacity(0.06))
                    )
                    .shadow(
                        color: Color(nsColor: .systemBlue).opacity(0.35),
                        radius: 8
                    )
                    .frame(
                        width: highlight.width,
                        height: highlight.height
                    )
                    .position(
                        x: highlight.midX,
                        y: highlight.midY
                    )

                HStack(spacing: 10) {
                    Image(systemName: "cursorarrow.click")
                        .font(.title3)
                    Text(prompt)
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Color(nsColor: .systemBlue),
                    in: RoundedRectangle(
                        cornerRadius: 10,
                        style: .continuous
                    )
                )
                .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
                .fixedSize()
                .position(
                    x: min(
                        max(highlight.midX, 190),
                        proxy.size.width - 190
                    ),
                    y: max(28, highlight.minY - 22)
                )
            }
        }
        .allowsHitTesting(false)
    }
}
#endif
