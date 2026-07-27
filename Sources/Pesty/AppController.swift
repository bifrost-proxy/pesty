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
    private var keyMonitor: Any?
    private var languageObserver: NSObjectProtocol?
    private var updateObserver: NSObjectProtocol?
    private var presentedUpdateError: String?

    private(set) var previousApp: NSRunningApplication?
    private(set) var lastActiveApp: NSRunningApplication?

    var suppressAutoHide = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

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

        if !Settings.shared.onboarded {
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
    @objc private func menuClear() { store.clearHistory() }
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
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", path]
        try? task.run()
        NSApp.terminate(nil)
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

    func hideBar() {
        stopKeyMonitor()
        barController?.hide()
    }

    func pasteSelected() {
        guard let item = store.selectedItem else { return }
        hideBar()
        PasteService.paste(item, into: previousApp, monitor: monitor)
    }

    func pasteItem(_ item: ClipItem) {
        hideBar()
        PasteService.paste(item, into: previousApp, monitor: monitor)
    }

    func copyItem(_ item: ClipItem) {
        let change = PasteService.copy(item)
        monitor.suppressUntilChangeCount = change
        hideBar()
    }

    func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if let win = settingsWindow {
            win.makeKeyAndOrderFront(nil)
            return
        }
        let view = SettingsView()
        let host = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: host)
        win.title = L10n.settingsWindowTitle
        win.styleMask = [.titled, .closable, .miniaturizable]
        win.setContentSize(NSSize(width: 520, height: 560))
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
        guard !shouldUseDefaultReopenBehavior, settingsWindow?.isVisible == true else {
            throw SettingsAccessVerificationFailure(
                description: "reopening Pesty did not show Settings"
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

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        let code = Int(event.keyCode)
        let flags = event.modifierFlags
        let cmd = flags.contains(.command)
        let ctrl = flags.contains(.control)
        let opt = flags.contains(.option)

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
            if cmd, let sel = store.selectedItem { store.delete(sel); return nil }
            if !store.searchText.isEmpty {
                store.searchText.removeLast(); store.selectFirst(); return nil
            }
            return nil
        case kVK_ForwardDelete:
            if let sel = store.selectedItem { store.delete(sel) }
            return nil
        default:
            break
        }

        if !cmd && !ctrl && !opt,
           let chars = event.characters, chars.count == 1,
           let scalar = chars.unicodeScalars.first,
           scalar.value >= 32, scalar.value != 127 {
            store.searchText.append(chars)
            store.selectFirst()
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
