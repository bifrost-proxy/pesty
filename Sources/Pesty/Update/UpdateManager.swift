import AppKit
import Darwin
import Foundation
import Observation

struct AppRelease: Equatable, Sendable {
    let version: String
    let downloadURL: URL
    let sha256: String
    let channel: ReleaseChannel
}

enum ReleaseChannel: String, Equatable, Sendable {
    case stable
    case beta

    static func forVersion(_ value: String) -> ReleaseChannel? {
        guard let version = SemanticVersion(value) else { return nil }
        return version.betaNumber == nil ? .stable : .beta
    }
}

enum UpdateActivity: Equatable {
    case idle
    case checking
    case downloading
    case installing
    case failed(String)
}

enum UpdateCheckOutcome: Equatable {
    case updateAvailable(AppRelease)
    case upToDate
    case failed(String)
}

enum UpdatePresentation {
    static func showInMenuBar(hasUpdate: Bool, showsMenuBarIcon: Bool) -> Bool {
        hasUpdate && showsMenuBarIcon
    }

    static func showInClipboardBar(hasUpdate: Bool, showsMenuBarIcon: Bool) -> Bool {
        hasUpdate && !showsMenuBarIcon
    }
}

@Observable
@MainActor
final class UpdateManager {
    static let shared = UpdateManager()
    nonisolated static let automaticCheckInterval: TimeInterval = 60 * 60

    private(set) var availableRelease: AppRelease?
    private(set) var activity: UpdateActivity = .idle
    private(set) var lastInstallationError: String?

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var checkInProgress = false

    var hasUpdate: Bool { availableRelease != nil }
    var isInstalling: Bool {
        activity == .downloading || activity == .installing
    }

    var showInMenuBar: Bool {
        UpdatePresentation.showInMenuBar(
            hasUpdate: hasUpdate,
            showsMenuBarIcon: Settings.shared.showMenuBarIcon
        )
    }

    var showInClipboardBar: Bool {
        UpdatePresentation.showInClipboardBar(
            hasUpdate: hasUpdate,
            showsMenuBarIcon: Settings.shared.showMenuBarIcon
        )
    }

    private init() {}

    func start() {
        guard timer == nil else { return }
        guard ProcessInfo.processInfo.environment["PESTY_SKIP_UPDATE_CHECK"] == nil else {
            return
        }

        let timer = Timer(
            timeInterval: Self.automaticCheckInterval,
            repeats: true
        ) { _ in
            Task { @MainActor in
                _ = await UpdateManager.shared.checkForUpdates()
            }
        }
        timer.tolerance = 5 * 60
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        Task {
            let outcome = await checkForUpdates()
            if ProcessInfo.processInfo.environment["PESTY_AUTOMATED_UPDATE_CHECK_ONLY"] == "1" {
                writeAutomatedCheckResult(outcome)
                exit(outcome.isFailure ? EXIT_FAILURE : EXIT_SUCCESS)
            }
            if case .updateAvailable = outcome,
               ProcessInfo.processInfo.environment["PESTY_AUTOMATED_UPDATE_INSTALL"] == "1" {
                installAvailableUpdate()
            }
        }
    }

    @discardableResult
    func checkForUpdates() async -> UpdateCheckOutcome {
        guard !checkInProgress, !isInstalling else {
            if let availableRelease {
                return .updateAvailable(availableRelease)
            }
            return .failed(L10n.updateAlreadyInProgress)
        }

        checkInProgress = true
        activity = .checking
        notifyStateChanged()
        defer { checkInProgress = false }

        do {
            let release = try await UpdateService.fetchLatestRelease()
            if UpdateService.isNewer(
                release.version,
                than: UpdateService.currentVersion
            ) {
                availableRelease = release
                activity = .idle
                notifyStateChanged()
                return .updateAvailable(release)
            }

            availableRelease = nil
            activity = .idle
            notifyStateChanged()
            return .upToDate
        } catch {
            let message = error.localizedDescription
            activity = .failed(message)
            notifyStateChanged()
            return .failed(message)
        }
    }

    func installAvailableUpdate() {
        guard let release = availableRelease, !isInstalling else { return }
        lastInstallationError = nil
        activity = .downloading
        notifyStateChanged()

        Task {
            do {
                let plan = try await UpdateInstaller.prepare(release: release)
                activity = .installing
                notifyStateChanged()
                try plan.launch()
                NSApp.terminate(nil)
            } catch {
                let message = error.localizedDescription
                lastInstallationError = message
                activity = .failed(message)
                notifyStateChanged()
            }
        }
    }

    func injectAvailableReleaseForVerification(version: String) {
        availableRelease = AppRelease(
            version: version,
            downloadURL: URL(string: "https://github.com/\(Repository.current)/releases/download/v\(version)/Pesty-\(version).dmg")!,
            sha256: String(repeating: "0", count: 64),
            channel: ReleaseChannel.forVersion(version) ?? .stable
        )
        activity = .idle
        notifyStateChanged()
    }

    private func notifyStateChanged() {
        NotificationCenter.default.post(name: .pestyUpdateStateDidChange, object: nil)
    }

    private func writeAutomatedCheckResult(_ outcome: UpdateCheckOutcome) {
        struct Result: Encodable {
            let currentVersion: String
            let channel: String
            let outcome: String
            let availableVersion: String?
        }

        let outcomeName: String
        let availableVersion: String?
        switch outcome {
        case .updateAvailable(let release):
            outcomeName = "updateAvailable"
            availableVersion = release.version
        case .upToDate:
            outcomeName = "upToDate"
            availableVersion = nil
        case .failed:
            outcomeName = "failed"
            availableVersion = nil
        }
        let result = Result(
            currentVersion: UpdateService.currentVersion,
            channel: UpdateService.currentChannel.rawValue,
            outcome: outcomeName,
            availableVersion: availableVersion
        )
        guard let data = try? JSONEncoder().encode(result) else { return }
        FileHandle.standardOutput.write(Data("AUTOMATED_UPDATE_CHECK_RESULT ".utf8))
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}

private extension UpdateCheckOutcome {
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}

enum UpdateService {
    struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: URL
            let digest: String?

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
                case digest
            }
        }

        let tagName: String
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case draft
            case prerelease
            case assets
        }
    }

    enum Failure: LocalizedError {
        case invalidResponse
        case invalidRelease
        case missingAsset(String)
        case missingDigest
        case untrustedDownloadURL

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return L10n.updateInvalidResponse
            case .invalidRelease:
                return L10n.updateInvalidRelease
            case .missingAsset(let name):
                return L10n.updateMissingAsset(name)
            case .missingDigest:
                return L10n.updateMissingDigest
            case .untrustedDownloadURL:
                return L10n.updateUntrustedURL
            }
        }
    }

    static var currentVersion: String {
        ProcessInfo.processInfo.environment["PESTY_UPDATE_CURRENT_VERSION"]
            ?? Bundle.main.shortVersion
    }

    static var customFeedURL: URL? {
        if let value = ProcessInfo.processInfo.environment["PESTY_UPDATE_FEED_URL"],
           let url = URL(string: value) {
            return url
        }
        return nil
    }

    static var atomFeedURL: URL {
        URL(string: "https://github.com/\(Repository.current)/releases.atom")!
    }

    static var currentChannel: ReleaseChannel {
        ReleaseChannel.forVersion(currentVersion) ?? .stable
    }

    static func fetchLatestRelease() async throws -> AppRelease {
        if let customFeedURL {
            return try await fetchJSONRelease(from: customFeedURL)
        }
        return try await fetchAtomRelease()
    }

    private static func fetchJSONRelease(from url: URL) async throws -> AppRelease {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("Pesty/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw Failure.invalidResponse
        }
        switch currentChannel {
        case .stable:
            return try decodeRelease(data, requiredChannel: .stable)
        case .beta:
            return try decodeReleaseList(data, requiredChannel: .beta)
        }
    }

    private static func fetchAtomRelease() async throws -> AppRelease {
        var request = URLRequest(url: atomFeedURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        request.setValue("application/atom+xml", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("Pesty/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw Failure.invalidResponse
        }
        return try decodeAtomFeed(data, requiredChannel: currentChannel)
    }

    static func decodeRelease(
        _ data: Data,
        requiredChannel: ReleaseChannel
    ) throws -> AppRelease {
        let payload = try JSONDecoder().decode(GitHubRelease.self, from: data)
        return try makeRelease(payload, requiredChannel: requiredChannel)
    }

    static func decodeReleaseList(
        _ data: Data,
        requiredChannel: ReleaseChannel
    ) throws -> AppRelease {
        let payloads = try JSONDecoder().decode([GitHubRelease].self, from: data)
        let releases = payloads.compactMap {
            try? makeRelease($0, requiredChannel: requiredChannel)
        }
        guard let release = releases.max(by: {
            guard let lhs = SemanticVersion($0.version),
                  let rhs = SemanticVersion($1.version) else { return false }
            return lhs < rhs
        }) else {
            throw Failure.invalidRelease
        }
        return release
    }

    static func decodeAtomFeed(
        _ data: Data,
        requiredChannel: ReleaseChannel
    ) throws -> AppRelease {
        let releases = try ReleaseAtomParser.parse(data).compactMap { entry -> AppRelease? in
            guard entry.tag.hasPrefix("v") else { return nil }
            let version = String(entry.tag.dropFirst())
            guard ReleaseChannel.forVersion(version) == requiredChannel else {
                return nil
            }
            let expectedReleaseURL = URL(
                string: "https://github.com/\(Repository.current)/releases/tag/v\(version)"
            )!
            guard entry.releaseURL == expectedReleaseURL,
                  let hash = firstSHA256(in: entry.content) else {
                return nil
            }
            let downloadURL = URL(
                string: "https://github.com/\(Repository.current)/releases/download/v\(version)/Pesty-\(version).dmg"
            )!
            guard isTrustedDownloadURL(downloadURL) else { return nil }
            return AppRelease(
                version: version,
                downloadURL: downloadURL,
                sha256: hash,
                channel: requiredChannel
            )
        }
        guard let release = releases.max(by: {
            guard let lhs = SemanticVersion($0.version),
                  let rhs = SemanticVersion($1.version) else { return false }
            return lhs < rhs
        }) else {
            throw Failure.invalidRelease
        }
        return release
    }

    private static func makeRelease(
        _ payload: GitHubRelease,
        requiredChannel: ReleaseChannel
    ) throws -> AppRelease {
        guard !payload.draft, payload.tagName.hasPrefix("v") else {
            throw Failure.invalidRelease
        }
        let version = String(payload.tagName.dropFirst())
        guard let channel = ReleaseChannel.forVersion(version),
              channel == requiredChannel,
              payload.prerelease == (channel == .beta) else {
            throw Failure.invalidRelease
        }

        let expectedName = "Pesty-\(version).dmg"
        guard let asset = payload.assets.first(where: { $0.name == expectedName }) else {
            throw Failure.missingAsset(expectedName)
        }
        guard isTrustedDownloadURL(asset.browserDownloadURL) else {
            throw Failure.untrustedDownloadURL
        }
        guard let digest = asset.digest, digest.hasPrefix("sha256:") else {
            throw Failure.missingDigest
        }
        let hash = digest.dropFirst("sha256:".count)
        let hex = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        guard hash.count == 64,
              hash.unicodeScalars.allSatisfy(hex.contains) else {
            throw Failure.missingDigest
        }

        return AppRelease(
            version: version,
            downloadURL: asset.browserDownloadURL,
            sha256: String(hash).lowercased(),
            channel: channel
        )
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let candidate = SemanticVersion(candidate),
              let current = SemanticVersion(current) else {
            return false
        }
        return candidate > current
    }

    private static func isTrustedDownloadURL(_ url: URL) -> Bool {
        if ProcessInfo.processInfo.environment["PESTY_UPDATE_ALLOW_INSECURE_TEST_FEED"] == "1",
           url.host == "127.0.0.1" || url.host == "localhost" {
            return true
        }

        let expectedPrefix = "/\(Repository.current)/releases/download/"
        return url.scheme == "https"
            && url.host == "github.com"
            && url.path.hasPrefix(expectedPrefix)
    }

    private static func firstSHA256(in value: String) -> String? {
        guard let expression = try? NSRegularExpression(
            pattern: #"(?i)SHA-256:\s*(?:<[^>]+>\s*)*([0-9a-f]{64})(?![0-9a-f])"#
        ) else { return nil }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = expression.firstMatch(in: value, range: range),
              let swiftRange = Range(match.range(at: 1), in: value) else {
            return nil
        }
        return String(value[swiftRange]).lowercased()
    }
}

struct SemanticVersion: Comparable, Equatable {
    let major: Int
    let minor: Int
    let patch: Int
    let betaNumber: Int?

    init?(_ value: String) {
        let sections = value.split(
            separator: "-",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        guard !sections.isEmpty else { return nil }
        let parts = sections[0].split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let major = Int(parts[0]),
              let minor = Int(parts[1]),
              let patch = Int(parts[2]),
              major >= 0, minor >= 0, patch >= 0 else {
            return nil
        }

        let betaNumber: Int?
        if sections.count == 1 {
            betaNumber = nil
        } else {
            let prerelease = sections[1].split(
                separator: ".",
                omittingEmptySubsequences: false
            )
            guard prerelease.count == 2,
                  prerelease[0] == "beta",
                  let value = Int(prerelease[1]),
                  value > 0 else {
                return nil
            }
            betaNumber = value
        }
        self.major = major
        self.minor = minor
        self.patch = patch
        self.betaNumber = betaNumber
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        switch (lhs.betaNumber, rhs.betaNumber) {
        case (.none, .none):
            return false
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case let (.some(lhs), .some(rhs)):
            return lhs < rhs
        }
    }
}
