import AppKit

@main
struct PestyMain {
    static func main() {
        UpdateInstaller.markUpdateLaunchHealthyIfNeeded()

        if CommandLine.arguments.contains("--verify-localization") {
            do {
                try LocalizationVerifier.run()
                print("Localization verification passed")
            } catch {
                fputs("Localization verification failed: \(error)\n", stderr)
                exit(EXIT_FAILURE)
            }
            return
        }

        if CommandLine.arguments.contains("--verify-updater") {
            do {
                try UpdaterVerifier.run()
                print("Updater verification passed")
            } catch {
                fputs("Updater verification failed: \(error)\n", stderr)
                exit(EXIT_FAILURE)
            }
            return
        }

        if CommandLine.arguments.contains("--verify-appearance") {
            _ = NSApplication.shared
            do {
                try AppearanceVerifier.run()
                print("Appearance verification passed")
            } catch {
                fputs("Appearance verification failed: \(error)\n", stderr)
                exit(EXIT_FAILURE)
            }
            return
        }

        if CommandLine.arguments.contains("--verify-history-settings") {
            do {
                try HistorySettingsVerifier.run()
                print("History settings verification passed")
            } catch {
                fputs("History settings verification failed: \(error)\n", stderr)
                exit(EXIT_FAILURE)
            }
            return
        }

        if CommandLine.arguments.contains("--verify-translation") {
            do {
                try TranslationVerifier.run()
                print("Translation verification passed")
            } catch {
                fputs("Translation verification failed: \(error)\n", stderr)
                exit(EXIT_FAILURE)
            }
            return
        }

        let app = NSApplication.shared
        StandardApplicationMenus.install(on: app)
        let delegate = AppController.shared
        app.delegate = delegate
        app.run()
    }
}

/// LSUIElement applications do not receive standard application menus
/// automatically. Install the common window and editing commands so Settings
/// behaves like a regular macOS window.
@MainActor
enum StandardApplicationMenus {
    static func install(on application: NSApplication) {
        let mainMenu = NSMenu()

        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu()
        applicationMenu.addItem(
            item(
                title: L10n.text("Quit Pesty", "退出 Pesty"),
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )
        applicationItem.submenu = applicationMenu
        mainMenu.addItem(applicationItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: L10n.text("File", "文件"))
        fileMenu.addItem(
            item(
                title: L10n.text("Close Window", "关闭窗口"),
                action: #selector(NSWindow.performClose(_:)),
                keyEquivalent: "w"
            )
        )
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: L10n.text("Edit", "编辑"))
        editMenu.addItem(
            item(
                title: L10n.text("Undo", "撤销"),
                action: Selector(("undo:")),
                keyEquivalent: "z"
            )
        )
        let redo = item(
            title: L10n.text("Redo", "重做"),
            action: Selector(("redo:")),
            keyEquivalent: "z"
        )
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(
            item(
                title: L10n.text("Cut", "剪切"),
                action: #selector(NSText.cut(_:)),
                keyEquivalent: "x"
            )
        )
        editMenu.addItem(
            item(
                title: L10n.text("Copy", "复制"),
                action: #selector(NSText.copy(_:)),
                keyEquivalent: "c"
            )
        )
        editMenu.addItem(
            item(
                title: L10n.text("Paste", "粘贴"),
                action: #selector(NSText.paste(_:)),
                keyEquivalent: "v"
            )
        )
        editMenu.addItem(.separator())
        editMenu.addItem(
            item(
                title: L10n.text("Select All", "全选"),
                action: #selector(NSText.selectAll(_:)),
                keyEquivalent: "a"
            )
        )
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: L10n.text("Window", "窗口"))
        windowMenu.addItem(
            item(
                title: L10n.text("Minimize", "最小化"),
                action: #selector(NSWindow.performMiniaturize(_:)),
                keyEquivalent: "m"
            )
        )
        windowMenu.addItem(
            item(
                title: L10n.text("Zoom", "缩放"),
                action: #selector(NSWindow.performZoom(_:)),
                keyEquivalent: ""
            )
        )
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)
        application.windowsMenu = windowMenu

        application.mainMenu = mainMenu
    }

    private static func item(
        title: String,
        action: Selector,
        keyEquivalent: String
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: action,
            keyEquivalent: keyEquivalent
        )
        item.keyEquivalentModifierMask = [.command]
        return item
    }
}
