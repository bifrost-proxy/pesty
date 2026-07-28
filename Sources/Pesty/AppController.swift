import AppKit
import SwiftUI
import Carbon.HIToolbox

@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    static let shared = AppController()

    let store = ClipboardStore.shared
    let monitor = ClipboardMonitor()

    private var barController: BarWindowController?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private let settingsWindowState = SettingsWindowState()
    private var keyMonitor: Any?
    private var languageObserver: NSObjectProtocol?
    private var updateObserver: NSObjectProtocol?
    private var presentedUpdateError: String?

    private(set) var previousApp: NSRunningApplication?
    private(set) var lastActiveApp: NSRunningApplication?
    #if !MAS
    private var previousFocusedElement: AXUIElement?
    #endif

    var suppressAutoHide = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if ProcessInfo.processInfo.environment["PESTY_AUTOMATED_UI_TEST"] == nil {
            barController = BarWindowController()
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)

        monitor.start()

        if ProcessInfo.processInfo.environment["PESTY_AUTOMATED_UI_TEST"] != nil {
            AutomatedUITestRunner.start(controller: self)
            return
        }

        HotKeyCenter.shared.onTrigger = { [weak self] in self?.toggleBar() }
        HotKeyCenter.shared.start()

        updateStatusItemVisibility()
        languageObserver = NotificationCenter.default.addObserver(
            forName: .pestyLanguageDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.rebuildStatusItemMenu()
                self?.settingsWindow?.title = L10n.settingsWindowTitle
            }
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(statusItemVisibilityDidChange),
            name: .pestyMenuBarIconVisibilityDidChange,
            object: nil
        )
        updateObserver = NotificationCenter.default.addObserver(
            forName: .pestyUpdateStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateStatusItemAppearance()
                self?.rebuildStatusItemMenu()
                self?.presentInstallationErrorIfNeeded()
            }
        }

        if Settings.shared.launchAtLogin { LaunchAtLogin.set(enabled: true) }

        if CommandLine.arguments.contains("--verify-settings-access") {
            verifySettingsAccessAndExit()
            return
        }

        #if !MAS
        if ProcessInfo.processInfo.environment[
            "PESTY_AUTOMATED_ACCESSIBILITY_GUIDE"
        ] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                PasteService.openAccessibilitySettings(forceGuide: true)
            }
            return
        }
        #endif

        UpdateManager.shared.start()

        if ProcessInfo.processInfo.environment["PESTY_UPDATE_ROLLBACK"] == "1" {
            DispatchQueue.main.async { [weak self] in
                self?.showUpdateAlert(
                    title: L10n.updateInstallFailed,
                    message: L10n.updateRestoredPreviousVersion
                )
            }
        }

        if CommandLine.arguments.contains("--demo") {
            store.seedDemo()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showBar()
            }
            return
        }

        #if MAS
        let accessibilityOnboardingReason:
            AccessibilityOnboardingReason? = nil
        #else
        let accessibilityOnboardingReason = AccessibilityOnboardingPolicy.reason(
            hasPreviouslyOnboarded: Settings.shared.onboarded,
            completedBuild: Settings.shared.accessibilityAuthorizedBuild,
            currentBuild: Bundle.main.appVersion,
            isUpdateRelaunch: ProcessInfo.processInfo.environment[
                "PESTY_UPDATE_HEALTH_MARKER"
            ] != nil
        )
        #endif

        if let accessibilityOnboardingReason {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.showSettings(
                    accessibilityOnboarding: accessibilityOnboardingReason
                )
            }
        } else if !Settings.shared.onboarded {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.showSettings()
            }
            Settings.shared.onboarded = true
        } else if shouldShowSettingsAfterLaunch(
            launchedAsLoginItem: wasLaunchedAsLoginItem
        ) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.showSettings()
            }
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if CommandLine.arguments.contains("--demo") {
            showBar()
            return false
        }
        showSettings()
        return false
    }

    @objc private func appActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        if app.bundleIdentifier != Bundle.main.bundleIdentifier {
            lastActiveApp = app
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
#if !MAS
        AccessibilitySettingsGuideController.shared.dismiss()
#endif
        store.saveNow()
    }

    private func setupStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            configureStatusItemButton(button)
        }
        statusItem = item
        rebuildStatusItemMenu()
    }

    private func updateStatusItemVisibility() {
        if Settings.shared.showMenuBarIcon {
            setupStatusItem()
        } else if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private var wasLaunchedAsLoginItem: Bool {
        NSAppleEventManager.shared().currentAppleEvent?
            .attributeDescriptor(forKeyword: AEKeyword(keyAELaunchedAsLogInItem)) != nil
    }

    private func shouldShowSettingsAfterLaunch(launchedAsLoginItem: Bool) -> Bool {
        !Settings.shared.showMenuBarIcon && !launchedAsLoginItem
    }

    @objc private func statusItemVisibilityDidChange() {
        updateStatusItemVisibility()
        updateStatusItemAppearance()
        rebuildStatusItemMenu()
    }

    private func rebuildStatusItemMenu() {
        guard let item = statusItem else { return }
        let menu = NSMenu()
        if let release = UpdateManager.shared.availableRelease {
            let update = menu.addItem(
                withTitle: updateActionTitle(for: release),
                action: UpdateManager.shared.isInstalling ? nil : #selector(menuInstallUpdate),
                keyEquivalent: ""
            )
            update.target = self
            update.image = NSImage(
                systemSymbolName: "arrow.down.circle.fill",
                accessibilityDescription: L10n.updateAvailable
            )
            menu.addItem(.separator())
        }
        menu.addItem(withTitle: "\(L10n.openPesty)   \(Settings.shared.hotkeyDisplay)",
                     action: #selector(menuOpen), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.settings, action: #selector(menuSettings), keyEquivalent: ",").target = self
        let check = menu.addItem(
            withTitle: L10n.checkForUpdates,
            action: #selector(menuCheckForUpdates),
            keyEquivalent: ""
        )
        check.target = self
        check.isEnabled = UpdateManager.shared.activity != .checking
            && !UpdateManager.shared.isInstalling
        menu.addItem(withTitle: L10n.clearHistory, action: #selector(menuClear), keyEquivalent: "").target = self
        menu.addItem(.separator())
        let about = menu.addItem(withTitle: L10n.aboutPesty, action: #selector(menuAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(withTitle: L10n.quitPesty, action: #selector(menuQuit), keyEquivalent: "q").target = self
        item.menu = menu
    }

    @objc private func menuOpen() { showBar() }
    @objc private func menuSettings() { showSettings() }
    @objc private func menuClear() { requestClearHistoryConfirmation() }
    @objc private func menuQuit() { NSApp.terminate(nil) }
    @objc private func menuAbout() { showAbout() }
    @objc private func menuInstallUpdate() { UpdateManager.shared.installAvailableUpdate() }
    @objc private func menuCheckForUpdates() { checkForUpdatesManually() }

    func checkForUpdatesManually() {
        Task {
            let outcome = await UpdateManager.shared.checkForUpdates()
            switch outcome {
            case .updateAvailable(let release):
                let alert = NSAlert()
                alert.messageText = L10n.updateAvailable
                alert.informativeText = L10n.updateAvailableMessage(release.version)
                alert.addButton(withTitle: L10n.installAndRestart)
                alert.addButton(withTitle: L10n.later)
                NSApp.activate(ignoringOtherApps: true)
                if alert.runModal() == .alertFirstButtonReturn {
                    UpdateManager.shared.installAvailableUpdate()
                }
            case .upToDate:
                showUpdateAlert(
                    title: L10n.upToDate,
                    message: L10n.upToDateMessage(Bundle.main.shortVersion)
                )
            case .failed(let message):
                showUpdateAlert(title: L10n.updateCheckFailed, message: message)
            }
        }
    }

    func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Pesty",
            .applicationVersion: Bundle.main.appVersion,
            .credits: NSAttributedString(
                string: L10n.aboutDescription,
                attributes: [.font: NSFont.systemFont(ofSize: 11)])
        ])
    }

    func requestClearHistoryConfirmation() {
        suppressAutoHide = true
        defer { suppressAutoHide = false }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.clearHistoryConfirmationTitle
        alert.informativeText = L10n.clearHistoryConfirmationMessage
        alert.addButton(withTitle: L10n.clearHistory)
        alert.addButton(withTitle: L10n.cancel)
        alert.buttons.first?.hasDestructiveAction = true

        NSApp.activate(ignoringOtherApps: true)
        resolveClearHistoryConfirmation(
            confirmed: alert.runModal() == .alertFirstButtonReturn
        )
    }

    func resolveClearHistoryConfirmation(confirmed: Bool) {
        guard confirmed else { return }
        store.clearHistory()
    }

    func toggleICloudSync() {
        let enabling = !Settings.shared.iCloudSync
        if enabling && !ClipboardStore.shared.iCloudAvailable {
            let alert = NSAlert()
            alert.messageText = L10n.iCloudUnavailable
            alert.informativeText = L10n.iCloudUnavailableMessage
            alert.runModal()
            return
        }
        Settings.shared.iCloudSync = enabling
        ClipboardStore.shared.setICloudSync(enabling)
    }

    static func restart() {
        let path = Bundle.main.bundlePath
        let pid = String(ProcessInfo.processInfo.processIdentifier)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.environment = restartEnvironment()
        task.arguments = [
            "-c",
            """
            old_pid="$1"
            app_path="$2"
            while /bin/kill -0 "$old_pid" 2>/dev/null; do
              /bin/sleep 0.1
            done
            /usr/bin/open -n "$app_path"
            """,
            "--",
            pid,
            path,
        ]
        do {
            try task.run()
            NSApp.terminate(nil)
        } catch {
            NSLog(
                "Pesty restart helper failed to start: %@",
                error.localizedDescription
            )
        }
    }

    private static func restartEnvironment(
        from environment: [String: String] =
            ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var environment = environment
        environment.removeValue(forKey: "PESTY_UPDATE_HEALTH_MARKER")
        return environment
    }

    func toggleBar() {
        if let bar = barController, bar.window?.isVisible == true {
            hideBar()
        } else {
            showBar()
        }
    }

    func showBar() {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = front
            #if !MAS
            previousFocusedElement = front.flatMap {
                PasteService.captureFocusedElement(in: $0)
            }
            #endif
        }
        store.reconcileFromDisk()
        store.searchText = ""
        store.source = .history
        store.selectFirst()

        if barController == nil {
            barController = BarWindowController()
        }
        barController?.show()
        if ProcessInfo.processInfo.environment["PESTY_AUTOMATED_UI_TEST"] == nil {
            startKeyMonitor()
        }
    }

    func hideBar(completion: (() -> Void)? = nil) {
        stopKeyMonitor()
        guard let barController else {
            completion?()
            return
        }
        barController.hide(completion: completion)
    }

    func pasteSelected() {
        guard let item = store.selectedItem else { return }
        pasteItem(item)
    }

    func pasteItem(_ item: ClipItem) {
        pasteItem(item, promoteAfterHiding: false)
    }

    func quickPasteItem(_ item: ClipItem) {
        pasteItem(item, promoteAfterHiding: true)
    }

    private func pasteItem(
        _ item: ClipItem,
        promoteAfterHiding: Bool
    ) {
        let targetApp = previousApp ?? lastActiveApp
        #if !MAS
        let focusedElement = previousFocusedElement
        #endif
        hideBar { [weak self] in
            guard let self else { return }
            if promoteAfterHiding {
                self.store.promoteToFront(item)
            }
            #if MAS
            PasteService.paste(item, into: targetApp, monitor: self.monitor)
            #else
            PasteService.paste(
                item,
                into: targetApp,
                focusedElement: focusedElement,
                forceDirectPaste: promoteAfterHiding,
                monitor: self.monitor
            )
            #endif
        }
    }

    func setPasteTargetForAutomatedTest(_ app: NSRunningApplication) {
        guard ProcessInfo.processInfo.environment["PESTY_AUTOMATED_UI_TEST"] != nil else { return }
        previousApp = app
        #if !MAS
        previousFocusedElement = PasteService.captureFocusedElement(in: app)
        #endif
    }

    func copyItem(_ item: ClipItem) {
        let change = PasteService.copy(item)
        monitor.suppressUntilChangeCount = change
        hideBar()
    }

    func showSettings(
        accessibilityOnboarding reason: AccessibilityOnboardingReason? = nil
    ) {
        NSApp.activate(ignoringOtherApps: true)
        if let reason {
            settingsWindowState.presentAccessibilityOnboarding(reason: reason)
        }
        if let win = settingsWindow {
            win.makeKeyAndOrderFront(nil)
            return
        }
        let view = SettingsView(state: settingsWindowState)
        let host = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: host)
        win.title = L10n.settingsWindowTitle
        win.styleMask = [
            .titled,
            .closable,
            .resizable,
            .fullSizeContentView,
        ]
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.titlebarSeparatorStyle = .none
        win.isMovableByWindowBackground = true
        win.backgroundColor = .clear
        win.contentMinSize = NSSize(
            width: SettingsWindowLayout.width,
            height: SettingsWindowLayout.minimumHeight
        )
        win.contentMaxSize = NSSize(
            width: SettingsWindowLayout.width,
            height: .greatestFiniteMagnitude
        )
        win.setContentSize(
            NSSize(
                width: SettingsWindowLayout.width,
                height: SettingsWindowLayout.initialHeight
            )
        )
        win.center()
        win.isReleasedWhenClosed = false
        settingsWindow = win
        win.makeKeyAndOrderFront(nil)
    }

    private func verifySettingsAccessAndExit() {
        do {
            try verifySettingsAccess()
        } catch {
            verificationFailed(String(describing: error))
        }

        print("Settings access verification passed")
        NSApp.terminate(nil)
    }

    private func verifySettingsAccess() throws {
        let previousVisibility = Settings.shared.showMenuBarIcon
        defer {
            Settings.shared.showMenuBarIcon = previousVisibility
            settingsWindow?.orderOut(nil)
        }

#if !MAS
        let resetCommand = PasteService.accessibilityResetCommand()
        guard resetCommand.executable == "/usr/bin/tccutil",
              resetCommand.arguments == [
                  "reset",
                  "Accessibility",
                  "com.bifrostproxy.pesty",
              ] else {
            throw SettingsAccessVerificationFailure(
                description: "Accessibility repair did not target only Pesty"
            )
        }

        guard AccessibilityOnboardingPolicy.reason(
            hasPreviouslyOnboarded: false,
            completedBuild: nil,
            currentBuild: "2.0.0 (20)",
            isUpdateRelaunch: false
        ) == .firstInstall,
        AccessibilityOnboardingPolicy.reason(
            hasPreviouslyOnboarded: true,
            completedBuild: "1.9.0 (19)",
            currentBuild: "2.0.0 (20)",
            isUpdateRelaunch: false
        ) == .update,
        AccessibilityOnboardingPolicy.reason(
            hasPreviouslyOnboarded: true,
            completedBuild: "2.0.0 (20)",
            currentBuild: "2.0.0 (20)",
            isUpdateRelaunch: false
        ) == nil,
        AccessibilityOnboardingPolicy.reason(
            hasPreviouslyOnboarded: true,
            completedBuild: "2.0.0 (20)",
            currentBuild: "2.0.0 (20)",
            isUpdateRelaunch: true
        ) == nil,
        AccessibilityOnboardingPolicy.reason(
            hasPreviouslyOnboarded: true,
            completedBuild: "1.9.0 (19)",
            currentBuild: "2.0.0 (20)",
            isUpdateRelaunch: true
        ) == .update else {
            throw SettingsAccessVerificationFailure(
                description: "Accessibility onboarding launch policy is incomplete"
            )
        }

        let restartEnvironment = Self.restartEnvironment(from: [
            "PATH": "/usr/bin",
            "PESTY_UPDATE_HEALTH_MARKER": "/tmp/launch-healthy",
        ])
        guard restartEnvironment["PATH"] == "/usr/bin",
              restartEnvironment["PESTY_UPDATE_HEALTH_MARKER"] == nil else {
            throw SettingsAccessVerificationFailure(
                description: "Pesty restart retained the update health marker"
            )
        }

        let exactGuide =
            AccessibilitySettingsGuideLayout.presentation(
                in: AccessibilitySettingsGuideLayout.referenceWindowSize
            )
        let fallbackGuide =
            AccessibilitySettingsGuideLayout.presentation(
                in: CGSize(width: 980, height: 620)
            )
        guard exactGuide.mode == .exactPestyRow,
              abs(exactGuide.highlightFrame.minX - 237.87) < 0.5,
              abs(exactGuide.highlightFrame.minY - 406.8) < 0.5,
              exactGuide.highlightFrame.height == 46,
              fallbackGuide.mode == .applicationList,
              fallbackGuide.highlightFrame.width >= 260,
              fallbackGuide.highlightFrame.height >= 260 else {
            throw SettingsAccessVerificationFailure(
                description: "Accessibility Settings guide layout is invalid"
            )
        }
#endif

        UpdateManager.shared.injectAvailableReleaseForVerification(version: "99.0.0")
        Settings.shared.showMenuBarIcon = false
        guard statusItem == nil else {
            throw SettingsAccessVerificationFailure(
                description: "menu bar icon remained visible after hiding it"
            )
        }
        guard UpdateManager.shared.showInClipboardBar,
              !UpdateManager.shared.showInMenuBar else {
            throw SettingsAccessVerificationFailure(
                description: "hidden menu icon did not move the update indicator into the clipboard bar"
            )
        }
        guard shouldShowSettingsAfterLaunch(launchedAsLoginItem: false),
              !shouldShowSettingsAfterLaunch(launchedAsLoginItem: true) else {
            throw SettingsAccessVerificationFailure(
                description: "hidden-icon launch handling did not distinguish a login item"
            )
        }

        Settings.shared.showMenuBarIcon = true
        guard statusItem != nil else {
            throw SettingsAccessVerificationFailure(
                description: "menu bar icon did not return after showing it"
            )
        }
        guard UpdateManager.shared.showInMenuBar,
              !UpdateManager.shared.showInClipboardBar,
              statusItem?.menu?.items.contains(where: {
                  $0.action == #selector(menuInstallUpdate)
              }) == true else {
            throw SettingsAccessVerificationFailure(
                description: "visible menu icon did not expose the immediate update action"
            )
        }

        Settings.shared.showMenuBarIcon = false
        let shouldUseDefaultReopenBehavior = applicationShouldHandleReopen(
            NSApp,
            hasVisibleWindows: false
        )
        guard let settingsWindow,
              let contentView = settingsWindow.contentView else {
            throw SettingsAccessVerificationFailure(
                description: "reopening Pesty did not create the Settings window"
            )
        }
        let initialContentSize = contentView.frame.size
        guard !shouldUseDefaultReopenBehavior,
              settingsWindow.isVisible,
              initialContentSize.width == SettingsWindowLayout.width,
              initialContentSize.height >= SettingsWindowLayout.minimumHeight,
              settingsWindow.styleMask.contains(.resizable),
              settingsWindow.contentMinSize == NSSize(
                  width: SettingsWindowLayout.width,
                  height: SettingsWindowLayout.minimumHeight
              ),
              settingsWindow.contentMaxSize.width
                  == SettingsWindowLayout.width,
              settingsWindow.styleMask.contains(.fullSizeContentView),
              settingsWindow.titleVisibility == .hidden,
              settingsWindow.titlebarAppearsTransparent else {
            throw SettingsAccessVerificationFailure(
                description:
                    "reopening Pesty did not show the fixed-width, vertically resizable Settings window"
            )
        }

        let resizedHeight = initialContentSize.height
            > SettingsWindowLayout.minimumHeight + 40
            ? max(
                SettingsWindowLayout.minimumHeight,
                initialContentSize.height - 80
            )
            : min(
                SettingsWindowLayout.initialHeight,
                initialContentSize.height + 80
            )
        settingsWindow.setContentSize(
            NSSize(
                width: SettingsWindowLayout.width,
                height: resizedHeight
            )
        )
        guard contentView.frame.size == NSSize(
            width: SettingsWindowLayout.width,
            height: resizedHeight
        ) else {
            throw SettingsAccessVerificationFailure(
                description: "Settings window did not resize vertically"
            )
        }
    }

    private func verificationFailed(_ message: String) -> Never {
        fputs("Settings access verification failed: \(message)\n", stderr)
        exit(EXIT_FAILURE)
    }

    private struct SettingsAccessVerificationFailure: Error, CustomStringConvertible {
        let description: String
    }

    private func configureStatusItemButton(_ button: NSStatusBarButton) {
        let hasUpdate = UpdateManager.shared.showInMenuBar
        button.image = NSImage(
            systemSymbolName: hasUpdate ? "arrow.down.circle.fill" : "doc.on.clipboard",
            accessibilityDescription: hasUpdate ? L10n.updateAvailable : "Pesty"
        )
        button.image?.isTemplate = !hasUpdate
        button.contentTintColor = hasUpdate ? .systemBlue : nil
        button.toolTip = hasUpdate
            ? L10n.updateAvailableMessage(UpdateManager.shared.availableRelease?.version ?? "")
            : "Pesty"
    }

    private func updateStatusItemAppearance() {
        guard let button = statusItem?.button else { return }
        configureStatusItemButton(button)
    }

    private func updateActionTitle(for release: AppRelease) -> String {
        switch UpdateManager.shared.activity {
        case .downloading:
            return L10n.downloadingUpdate(release.version)
        case .installing:
            return L10n.installingUpdate(release.version)
        default:
            return L10n.updateToVersion(release.version)
        }
    }

    private func presentInstallationErrorIfNeeded() {
        guard let message = UpdateManager.shared.lastInstallationError,
              message != presentedUpdateError else { return }
        presentedUpdateError = message
        showUpdateAlert(title: L10n.updateInstallFailed, message: message)
    }

    private func showUpdateAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: L10n.ok)
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func startKeyMonitor() {
        stopKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKey(event)
        }
    }

    private func stopKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    func handleKey(_ event: NSEvent) -> NSEvent? {
        let code = Int(event.keyCode)
        let flags = event.modifierFlags
        let cmd = flags.contains(.command)
        let ctrl = flags.contains(.control)
        let textEditor = NSApp.keyWindow?.firstResponder as? NSTextView
        let isComposingText = textEditor?.hasMarkedText() == true

        if isComposingText {
            return event
        }
        if textEditor?.isFieldEditor == true {
            return event
        }

        if cmd, code == kVK_ANSI_F {
            SearchInputBridge.shared.requestActivation()
            return nil
        }

        if cmd, let chars = event.charactersIgnoringModifiers, let n = Int(chars), (1...9).contains(n) {
            let items = store.visibleItems
            if n <= items.count { pasteItem(items[n - 1]) }
            return nil
        }

        switch code {
        case kVK_Escape:
            if !store.searchText.isEmpty { store.searchText = ""; store.selectFirst() }
            else { hideBar() }
            return nil
        case kVK_Return, kVK_ANSI_KeypadEnter:
            pasteSelected(); return nil
        case kVK_LeftArrow, kVK_UpArrow:
            store.moveSelection(by: -1); return nil
        case kVK_RightArrow, kVK_DownArrow:
            store.moveSelection(by: 1); return nil
        case kVK_Delete:
            if cmd {
                store.deleteSelectedItem()
                return nil
            }
            if textEditor != nil {
                return event
            }
            if !store.searchText.isEmpty {
                store.searchText.removeLast()
                store.selectFirst()
                return nil
            }
            return nil
        case kVK_ForwardDelete:
            return textEditor == nil ? nil : event
        default:
            break
        }

        if textEditor != nil {
            return event
        }

        if !cmd && !ctrl {
            SearchInputBridge.shared.requestActivation(replaying: event)
            return nil
        }
        return event
    }
}

extension Bundle {
    var shortVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    var appVersion: String {
        let short = shortVersion
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}
