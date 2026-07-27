import AppKit
import Darwin

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

        let app = NSApplication.shared
        let delegate = AppController.shared
        app.delegate = delegate
        app.run()
    }
}
