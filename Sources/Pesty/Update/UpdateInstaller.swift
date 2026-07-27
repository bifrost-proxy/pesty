import CryptoKit
import Foundation

struct UpdateInstallationPlan: Sendable {
    let helperURL: URL
    let arguments: [String]

    func launch() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [helperURL.path] + arguments
        try process.run()
    }
}

enum UpdateInstaller {
    enum Failure: LocalizedError {
        case invalidDownload
        case checksumMismatch
        case diskImageFailure(String)
        case missingApp
        case invalidBundle
        case invalidVersion(String)
        case invalidArchitecture
        case invalidSignature(String)
        case appNotWritable
        case helperCreationFailed

        var errorDescription: String? {
            switch self {
            case .invalidDownload:
                return L10n.updateDownloadFailed
            case .checksumMismatch:
                return L10n.updateChecksumFailed
            case .diskImageFailure(let detail):
                return L10n.updateDiskImageFailed(detail)
            case .missingApp:
                return L10n.updateMissingApp
            case .invalidBundle:
                return L10n.updateInvalidBundle
            case .invalidVersion(let version):
                return L10n.updateVersionMismatch(version)
            case .invalidArchitecture:
                return L10n.updateInvalidArchitecture
            case .invalidSignature(let detail):
                return L10n.updateSignatureFailed(detail)
            case .appNotWritable:
                return L10n.updateAppNotWritable
            case .helperCreationFailed:
                return L10n.updateHelperFailed
            }
        }
    }

    private struct CommandResult {
        let status: Int32
        let stdout: Data
        let stderr: Data
    }

    static func prepare(release: AppRelease) async throws -> UpdateInstallationPlan {
        try await Task.detached(priority: .userInitiated) {
            try await prepareOffMain(release: release)
        }.value
    }

    static func markUpdateLaunchHealthyIfNeeded() {
        guard let marker = ProcessInfo.processInfo.environment["PESTY_UPDATE_HEALTH_MARKER"],
              !marker.isEmpty else { return }
        let markerURL = URL(fileURLWithPath: marker).standardizedFileURL
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let allowedRoot = caches
            .appendingPathComponent("Pesty/Updates", isDirectory: true)
            .standardizedFileURL
        guard markerURL.lastPathComponent == "launch-healthy",
              markerURL.path.hasPrefix(allowedRoot.path + "/") else { return }
        FileManager.default.createFile(
            atPath: markerURL.path,
            contents: Data("ready".utf8)
        )
    }

    private static func prepareOffMain(
        release: AppRelease
    ) async throws -> UpdateInstallationPlan {
        let currentApp = Bundle.main.bundleURL.standardizedFileURL
        guard currentApp.pathExtension == "app",
              Bundle.main.bundleIdentifier == "com.bifrostproxy.pesty",
              FileManager.default.isWritableFile(atPath: currentApp.deletingLastPathComponent().path)
        else {
            throw Failure.appNotWritable
        }

        let root = try makeUpdateDirectory()
        let dmgURL = root.appendingPathComponent("Pesty-\(release.version).dmg")
        let stagedApp = root.appendingPathComponent("Pesty.app", isDirectory: true)

        var request = URLRequest(url: release.downloadURL)
        request.timeoutInterval = 120
        request.setValue("Pesty/\(Bundle.main.shortVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw Failure.invalidDownload
        }

        let digest = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        guard digest == release.sha256 else {
            throw Failure.checksumMismatch
        }
        try data.write(to: dmgURL, options: [.atomic])

        let mountPoint = try attach(dmgURL)
        defer { _ = try? run("/usr/bin/hdiutil", ["detach", mountPoint.path]) }

        let sourceApp = mountPoint.appendingPathComponent("Pesty.app", isDirectory: true)
        guard FileManager.default.fileExists(atPath: sourceApp.path) else {
            throw Failure.missingApp
        }
        let copy = try run("/usr/bin/ditto", [sourceApp.path, stagedApp.path])
        guard copy.status == 0 else {
            throw Failure.diskImageFailure(text(copy.stderr))
        }
        _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", stagedApp.path])

        try verify(stagedApp, expectedVersion: release.version)
        return try makePlan(root: root, stagedApp: stagedApp, currentApp: currentApp)
    }

    private static func makeUpdateDirectory() throws -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let root = caches
            .appendingPathComponent("Pesty/Updates", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return root
    }

    private static func attach(_ dmgURL: URL) throws -> URL {
        let result = try run(
            "/usr/bin/hdiutil",
            ["attach", dmgURL.path, "-nobrowse", "-readonly", "-plist"]
        )
        guard result.status == 0 else {
            throw Failure.diskImageFailure(text(result.stderr))
        }
        guard let plist = try PropertyListSerialization.propertyList(
            from: result.stdout,
            options: [],
            format: nil
        ) as? [String: Any],
        let entities = plist["system-entities"] as? [[String: Any]],
        let path = entities.compactMap({ $0["mount-point"] as? String }).first
        else {
            throw Failure.diskImageFailure(L10n.updateMountPointMissing)
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private static func verify(_ appURL: URL, expectedVersion: String) throws {
        guard let bundle = Bundle(url: appURL),
              bundle.bundleIdentifier == "com.bifrostproxy.pesty" else {
            throw Failure.invalidBundle
        }
        guard bundle.shortVersion == expectedVersion else {
            throw Failure.invalidVersion(bundle.shortVersion)
        }

        let signature = try run(
            "/usr/bin/codesign",
            ["--verify", "--deep", "--strict", "--verbose=2", appURL.path]
        )
        guard signature.status == 0 else {
            throw Failure.invalidSignature(text(signature.stderr))
        }

        guard let executable = bundle.executableURL else {
            throw Failure.invalidBundle
        }
        let architectures = try run("/usr/bin/lipo", ["-archs", executable.path])
        let values = Set(text(architectures.stdout).split(whereSeparator: \.isWhitespace).map(String.init))
        guard architectures.status == 0,
              values.contains("arm64"),
              values.contains("x86_64") else {
            throw Failure.invalidArchitecture
        }
    }

    private static func makePlan(
        root: URL,
        stagedApp: URL,
        currentApp: URL
    ) throws -> UpdateInstallationPlan {
        let helper = root.appendingPathComponent("install-update.zsh")
        let backup = currentApp.deletingLastPathComponent()
            .appendingPathComponent(".Pesty-update-backup-\(UUID().uuidString).app")
        let marker = root.appendingPathComponent("launch-healthy")
        let logBase = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Pesty", isDirectory: true)
        try FileManager.default.createDirectory(
            at: logBase,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let log = logBase.appendingPathComponent("update.log")

        let script = """
        #!/bin/zsh
        set -u
        old_pid="$1"
        current_app="$2"
        staged_app="$3"
        backup_app="$4"
        marker="$5"
        update_root="$6"
        log_file="$7"
        exec >>"$log_file" 2>&1

        while /bin/kill -0 "$old_pid" 2>/dev/null; do
          /bin/sleep 0.2
        done

        restore_previous() {
          /bin/rm -rf "$current_app"
          if [[ -d "$backup_app" ]]; then
            /bin/mv "$backup_app" "$current_app"
            /usr/bin/open -n \
              --env "PESTY_UPDATE_ROLLBACK=1" \
              "$current_app"
          fi
          /bin/rm -rf "$update_root"
        }

        if ! /bin/mv "$current_app" "$backup_app"; then
          /usr/bin/open -n \
            --env "PESTY_UPDATE_ROLLBACK=1" \
            "$current_app"
          /bin/rm -rf "$update_root"
          exit 1
        fi
        if ! /usr/bin/ditto "$staged_app" "$current_app"; then
          restore_previous
          exit 1
        fi
        /usr/bin/xattr -dr com.apple.quarantine "$current_app" 2>/dev/null || true
        if ! /usr/bin/codesign --verify --deep --strict "$current_app"; then
          restore_previous
          exit 1
        fi
        if ! /usr/bin/open -n --env "PESTY_UPDATE_HEALTH_MARKER=$marker" "$current_app"; then
          restore_previous
          exit 1
        fi

        for attempt in {1..100}; do
          if [[ -f "$marker" ]]; then
            /bin/rm -rf "$backup_app" "$update_root"
            exit 0
          fi
          /bin/sleep 0.2
        done

        if ! /usr/bin/pgrep -x Pesty >/dev/null; then
          restore_previous
        fi
        exit 1
        """

        do {
            try Data(script.utf8).write(to: helper, options: [.atomic])
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: helper.path
            )
        } catch {
            throw Failure.helperCreationFailed
        }

        return UpdateInstallationPlan(
            helperURL: helper,
            arguments: [
                String(ProcessInfo.processInfo.processIdentifier),
                currentApp.path,
                stagedApp.path,
                backup.path,
                marker.path,
                root.path,
                log.path
            ]
        )
    }

    private static func run(_ executable: String, _ arguments: [String]) throws -> CommandResult {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        return CommandResult(
            status: process.terminationStatus,
            stdout: stdout.fileHandleForReading.readDataToEndOfFile(),
            stderr: stderr.fileHandleForReading.readDataToEndOfFile()
        )
    }

    private static func text(_ data: Data) -> String {
        String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? L10n.updateUnknownError
    }
}
