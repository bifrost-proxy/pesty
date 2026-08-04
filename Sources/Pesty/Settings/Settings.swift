import AppKit
import Carbon.HIToolbox
import Observation

enum HistoryRetentionPolicy {
    static let defaultLimit = 5_000
    static let minimumLimit = 100
    static let stepThreshold = 1_000
    static let maximumFiniteLimit = 10_000
    static let unlimitedSliderPosition = 19.0
    static let trimDelay: TimeInterval = 10

    static func normalized(_ value: Int) -> Int {
        min(maximumFiniteLimit, max(minimumLimit, value))
    }

    static func sliderPosition(limit: Int, unlimited: Bool) -> Double {
        if unlimited { return unlimitedSliderPosition }
        let value = normalized(limit)
        if value <= stepThreshold {
            return Double(max(0, min(9, Int(round(Double(value) / 100.0)) - 1)))
        }
        return Double(max(10, min(18, Int(round(Double(value) / 1_000.0)) + 8)))
    }

    static func selection(at sliderPosition: Double) -> Int? {
        let position = max(0, min(19, Int(round(sliderPosition))))
        if position == 19 {
            return nil
        }
        if position <= 9 {
            return (position + 1) * 100
        }
        return (position - 8) * 1_000
    }

    static func retainedPrefix<Element>(
        of items: [Element],
        limit: Int?
    ) -> [Element] {
        guard let limit else { return items }
        return Array(items.prefix(limit))
    }
}

struct SyncedHistoryRetentionConfiguration: Codable, Equatable, Sendable {
    var limit: Int
    var unlimited: Bool
    var updatedAt: Date
    var effectiveAt: Date?
    var revisionID: UUID

    func normalized() -> Self {
        var copy = self
        copy.limit = HistoryRetentionPolicy.normalized(limit)
        if unlimited {
            copy.effectiveAt = nil
        }
        return copy
    }

    func supersedes(_ other: Self) -> Bool {
        if updatedAt != other.updatedAt {
            return updatedAt > other.updatedAt
        }
        return revisionID.uuidString > other.revisionID.uuidString
    }
}

struct SyncedConfiguration: Codable, Equatable, Sendable {
    var historyRetention: SyncedHistoryRetentionConfiguration
}

enum BarLayoutPolicy {
    static let defaultHeight = 350.0
}

@Observable
@MainActor
final class Settings {
    static let shared = Settings()

    @ObservationIgnored private let d: UserDefaults
    @ObservationIgnored private var isLoaded = false

    enum Keys {
        static let historyLimit = "historyLimit"
        static let historyLimitUnlimited = "historyLimitUnlimited"
        static let historyLimitTrimAfter = "historyLimitTrimAfter"
        static let historyRetentionUpdatedAt = "historyRetentionUpdatedAt"
        static let historyRetentionEffectiveAt = "historyRetentionEffectiveAt"
        static let historyRetentionRevisionID = "historyRetentionRevisionID"
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyModifiers = "hotkeyModifiers"
        static let launchAtLogin = "launchAtLogin"
        static let showMenuBarIcon = "showMenuBarIcon"
        static let pasteDirectly = "pasteDirectly"
        static let playSound = "playSound"
        static let ignoreConcealed = "ignoreConcealed"
        static let barHeight = "barHeight"
        static let panelLayoutVersion = "panelLayoutVersion"
        static let onboarded = "onboarded"
        static let accessibilityAuthorizedBuild = "accessibilityAuthorizedBuild"
        static let iCloudSync = "iCloudSync"
        static let language = "language"
        static let translationService = "translationService"
        static let translationSourceLanguage = "translationSourceLanguage"
        static let translationTargetLanguage = "translationTargetLanguage"
        static let translationHotkeyKeyCode = "translationHotkeyKeyCode"
        static let translationHotkeyModifiers = "translationHotkeyModifiers"
        static let translationHotkeyDefaultMigrationVersion =
            "translationHotkeyDefaultMigrationVersion"
        static let explanationHotkeyKeyCode = "explanationHotkeyKeyCode"
        static let explanationHotkeyModifiers = "explanationHotkeyModifiers"
        static let explanationHotkeyDefaultMigrationVersion =
            "explanationHotkeyDefaultMigrationVersion"
        static let doubaoTranslationEndpointID = "doubaoTranslationEndpointID"
        static let doubaoTranslationModelID = "doubaoTranslationModelID"
        static let aiProviderProfiles = "aiProviderProfiles"
    }

    private(set) var historyLimit: Int
    private(set) var historyLimitUnlimited: Bool

    private(set) var historyLimitTrimAfter: Date?
    @ObservationIgnored private var syncedHistoryRetentionStorage:
        SyncedHistoryRetentionConfiguration?

    var hotkeyKeyCode: Int {
        didSet { guard isLoaded else { return }
            d.set(hotkeyKeyCode, forKey: Keys.hotkeyKeyCode); HotKeyCenter.shared.reload() }
    }

    var hotkeyModifiers: Int {
        didSet { guard isLoaded else { return }
            d.set(hotkeyModifiers, forKey: Keys.hotkeyModifiers); HotKeyCenter.shared.reload() }
    }

    var launchAtLogin: Bool {
        didSet { guard isLoaded else { return }
            d.set(launchAtLogin, forKey: Keys.launchAtLogin); LaunchAtLogin.set(enabled: launchAtLogin) }
    }

    var showMenuBarIcon: Bool {
        didSet {
            guard isLoaded else { return }
            d.set(showMenuBarIcon, forKey: Keys.showMenuBarIcon)
            NotificationCenter.default.post(name: .pestyMenuBarIconVisibilityDidChange, object: nil)
        }
    }

    var pasteDirectly: Bool {
        didSet { guard isLoaded else { return }; d.set(pasteDirectly, forKey: Keys.pasteDirectly) }
    }

    var playSound: Bool {
        didSet { guard isLoaded else { return }; d.set(playSound, forKey: Keys.playSound) }
    }

    var ignoreConcealed: Bool {
        didSet { guard isLoaded else { return }; d.set(ignoreConcealed, forKey: Keys.ignoreConcealed) }
    }

    var barHeight: Double {
        didSet {
            guard isLoaded else { return }
            let clamped = min(720, max(240, barHeight))
            if clamped != barHeight { barHeight = clamped; return }
            d.set(barHeight, forKey: Keys.barHeight)
        }
    }

    var onboarded: Bool {
        didSet { guard isLoaded else { return }; d.set(onboarded, forKey: Keys.onboarded) }
    }

    private(set) var accessibilityAuthorizedBuild: String?

    var iCloudSync: Bool {
        didSet { guard isLoaded else { return }; d.set(iCloudSync, forKey: Keys.iCloudSync) }
    }

    var language: AppLanguage {
        didSet {
            guard isLoaded else { return }
            d.set(language.rawValue, forKey: Keys.language)
            NotificationCenter.default.post(name: .pestyLanguageDidChange, object: nil)
        }
    }

    var translationService: TranslationService {
        didSet {
            guard isLoaded else { return }
            d.set(translationService.rawValue, forKey: Keys.translationService)
        }
    }

    var translationSourceLanguage: TranslationLanguage {
        didSet {
            guard isLoaded else { return }
            d.set(translationSourceLanguage.rawValue, forKey: Keys.translationSourceLanguage)
        }
    }

    var translationTargetLanguage: TranslationLanguage {
        didSet {
            guard isLoaded else { return }
            if translationTargetLanguage == .automatic {
                translationTargetLanguage = .simplifiedChinese
                return
            }
            d.set(translationTargetLanguage.rawValue, forKey: Keys.translationTargetLanguage)
        }
    }

    var translationHotkeyKeyCode: Int {
        didSet {
            guard isLoaded else { return }
            d.set(translationHotkeyKeyCode, forKey: Keys.translationHotkeyKeyCode)
            HotKeyCenter.shared.reload()
        }
    }

    var translationHotkeyModifiers: Int {
        didSet {
            guard isLoaded else { return }
            d.set(translationHotkeyModifiers, forKey: Keys.translationHotkeyModifiers)
            HotKeyCenter.shared.reload()
        }
    }

    var explanationHotkeyKeyCode: Int {
        didSet {
            guard isLoaded else { return }
            d.set(explanationHotkeyKeyCode, forKey: Keys.explanationHotkeyKeyCode)
            HotKeyCenter.shared.reload()
        }
    }

    var explanationHotkeyModifiers: Int {
        didSet {
            guard isLoaded else { return }
            d.set(explanationHotkeyModifiers, forKey: Keys.explanationHotkeyModifiers)
            HotKeyCenter.shared.reload()
        }
    }

    private(set) var doubaoTranslationModelID: String
    private(set) var doubaoTranslationConfigured: Bool
    private(set) var aiProviderProfiles: [AIProviderProfile]
    @ObservationIgnored private var hasDoubaoCredential: Bool

    private init() {
        if let suiteName = ProcessInfo.processInfo.environment[
            "PESTY_AUTOMATED_TEST_DEFAULTS_SUITE"
        ], !suiteName.isEmpty, let testDefaults = UserDefaults(suiteName: suiteName) {
            d = testDefaults
        } else {
            d = .standard
        }
        let storedBarHeight = (d.object(forKey: Keys.barHeight) as? NSNumber)?.doubleValue
        let storedPanelLayoutVersion = d.object(forKey: Keys.panelLayoutVersion) as? NSNumber
        d.register(defaults: [
            Keys.historyLimit: HistoryRetentionPolicy.defaultLimit,
            Keys.historyLimitUnlimited: false,
            Keys.hotkeyKeyCode: kVK_ANSI_V,
            Keys.hotkeyModifiers: cmdKey | shiftKey,
            Keys.launchAtLogin: false,
            Keys.showMenuBarIcon: true,
            Keys.pasteDirectly: true,
            Keys.playSound: false,
            Keys.ignoreConcealed: true,
            Keys.barHeight: BarLayoutPolicy.defaultHeight,
            Keys.onboarded: false,
            Keys.iCloudSync: false,
            Keys.language: AppLanguage.systemDefault.rawValue,
            Keys.translationService: TranslationService.automatic.rawValue,
            Keys.translationSourceLanguage: TranslationLanguage.automatic.rawValue,
            Keys.translationTargetLanguage: TranslationLanguage.simplifiedChinese.rawValue,
            Keys.translationHotkeyKeyCode: TranslationShortcut.defaultKeyCode,
            Keys.translationHotkeyModifiers: TranslationShortcut.defaultModifiers,
            Keys.explanationHotkeyKeyCode: ExplanationShortcut.defaultKeyCode,
            Keys.explanationHotkeyModifiers: ExplanationShortcut.defaultModifiers
        ])
        let loadedHistoryLimit = HistoryRetentionPolicy.normalized(
            d.integer(forKey: Keys.historyLimit)
        )
        let loadedHistoryLimitUnlimited = d.bool(forKey: Keys.historyLimitUnlimited)
        historyLimit = loadedHistoryLimit
        historyLimitUnlimited = loadedHistoryLimitUnlimited
        historyLimitTrimAfter = d.object(forKey: Keys.historyLimitTrimAfter) as? Date
        if let updatedAt = d.object(forKey: Keys.historyRetentionUpdatedAt) as? Date,
           let revisionValue = d.string(forKey: Keys.historyRetentionRevisionID),
           let revisionID = UUID(uuidString: revisionValue) {
            syncedHistoryRetentionStorage = SyncedHistoryRetentionConfiguration(
                limit: loadedHistoryLimit,
                unlimited: loadedHistoryLimitUnlimited,
                updatedAt: updatedAt,
                effectiveAt: d.object(forKey: Keys.historyRetentionEffectiveAt) as? Date,
                revisionID: revisionID
            ).normalized()
        } else {
            syncedHistoryRetentionStorage = nil
        }
        hotkeyKeyCode = d.integer(forKey: Keys.hotkeyKeyCode)
        hotkeyModifiers = d.integer(forKey: Keys.hotkeyModifiers)
        launchAtLogin = d.bool(forKey: Keys.launchAtLogin)
        showMenuBarIcon = d.bool(forKey: Keys.showMenuBarIcon)
        pasteDirectly = d.bool(forKey: Keys.pasteDirectly)
        playSound = d.bool(forKey: Keys.playSound)
        ignoreConcealed = d.bool(forKey: Keys.ignoreConcealed)
        if storedPanelLayoutVersion == nil,
           storedBarHeight == nil || abs((storedBarHeight ?? 430) - 430) < 0.5 {
            barHeight = BarLayoutPolicy.defaultHeight
            d.set(BarLayoutPolicy.defaultHeight, forKey: Keys.barHeight)
        } else {
            barHeight = storedBarHeight ?? d.double(forKey: Keys.barHeight)
        }
        d.set(1, forKey: Keys.panelLayoutVersion)
        onboarded = d.bool(forKey: Keys.onboarded)
        accessibilityAuthorizedBuild = d.string(
            forKey: Keys.accessibilityAuthorizedBuild
        )
        iCloudSync = d.bool(forKey: Keys.iCloudSync)
        language = AppLanguage(rawValue: d.string(forKey: Keys.language) ?? "") ?? .systemDefault
        let storedTranslationService = d.string(forKey: Keys.translationService) ?? ""
        let loadedTranslationService = TranslationService(rawValue: storedTranslationService) ?? .automatic
        translationService = loadedTranslationService
        if TranslationService(rawValue: storedTranslationService) == nil {
            d.set(loadedTranslationService.rawValue, forKey: Keys.translationService)
        }
        translationSourceLanguage = TranslationLanguage(
            rawValue: d.string(forKey: Keys.translationSourceLanguage) ?? ""
        ) ?? .automatic
        let loadedTranslationTargetLanguage = TranslationLanguage(
            rawValue: d.string(forKey: Keys.translationTargetLanguage) ?? ""
        ) ?? .simplifiedChinese
        translationTargetLanguage = loadedTranslationTargetLanguage == .automatic
            ? .simplifiedChinese
            : loadedTranslationTargetLanguage
        Settings.migrateTranslationShortcutDefaultIfNeeded(defaults: d)
        translationHotkeyKeyCode = d.integer(
            forKey: Keys.translationHotkeyKeyCode
        )
        translationHotkeyModifiers = d.integer(
            forKey: Keys.translationHotkeyModifiers
        )
        Settings.migrateExplanationShortcutDefaultIfNeeded(defaults: d)
        explanationHotkeyKeyCode = d.integer(forKey: Keys.explanationHotkeyKeyCode)
        explanationHotkeyModifiers = d.integer(forKey: Keys.explanationHotkeyModifiers)
        let legacyDoubaoEndpointID = d.string(
            forKey: Keys.doubaoTranslationEndpointID
        ) ?? ""
        let storedDoubaoModelID = d.string(forKey: Keys.doubaoTranslationModelID) ?? ""
        let loadedDoubaoModelID: String
        if !storedDoubaoModelID.isEmpty {
            loadedDoubaoModelID = storedDoubaoModelID
        } else if legacyDoubaoEndpointID.hasPrefix("ep-") {
            // Seed Evolving is invoked by its model ID. Preserve the legacy endpoint
            // setting, but migrate this translation integration to the supported ID.
            loadedDoubaoModelID = "doubao-seed-evolving"
            d.set(loadedDoubaoModelID, forKey: Keys.doubaoTranslationModelID)
        } else {
            loadedDoubaoModelID = legacyDoubaoEndpointID
        }
        doubaoTranslationModelID = loadedDoubaoModelID
        // Startup needs only the configuration state. Query Keychain metadata
        // without requesting or decrypting the credential itself.
        hasDoubaoCredential = Self.skipsCredentialLookupForAutomatedUITest
            ? false
            : ((try? SecureCredentialStore.contains(account: "doubao-ark-api-key")) == true)
        doubaoTranslationConfigured = hasDoubaoCredential
            && !loadedDoubaoModelID.isEmpty
        aiProviderProfiles = Self.loadAIProviderProfiles(from: d)
        isLoaded = true
    }

    private static var skipsCredentialLookupForAutomatedUITest: Bool {
        guard let phase = ProcessInfo.processInfo.environment["PESTY_AUTOMATED_UI_TEST"] else {
            return false
        }
        return !["doubao-live", "explanation-live", "doubao-prompt-diagnosis"].contains(phase)
    }

    var hotkeyDisplay: String {
        HotKeyCenter.describe(keyCode: hotkeyKeyCode, modifiers: hotkeyModifiers)
    }

    var translationHotkeyDisplay: String {
        HotKeyCenter.describe(
            keyCode: translationHotkeyKeyCode,
            modifiers: translationHotkeyModifiers
        )
    }

    var explanationHotkeyDisplay: String {
        HotKeyCenter.describe(
            keyCode: explanationHotkeyKeyCode,
            modifiers: explanationHotkeyModifiers
        )
    }

    /// Move only the previous shipped default from Command-T to the new global
    /// Command-Shift-T shortcut. User-customized shortcuts remain untouched.
    private static func migrateTranslationShortcutDefaultIfNeeded(
        defaults: UserDefaults
    ) {
        let migrationVersion = defaults.integer(
            forKey: Keys.translationHotkeyDefaultMigrationVersion
        )
        let keyCode = defaults.integer(forKey: Keys.translationHotkeyKeyCode)
        let modifiers = defaults.integer(
            forKey: Keys.translationHotkeyModifiers
        )
        guard TranslationShortcut.shouldMigratePreviousDefault(
            migrationVersion: migrationVersion,
            keyCode: keyCode,
            modifiers: modifiers
        ) else {
            return
        }
        defaults.set(
            TranslationShortcut.defaultKeyCode,
            forKey: Keys.translationHotkeyKeyCode
        )
        defaults.set(
            TranslationShortcut.defaultModifiers,
            forKey: Keys.translationHotkeyModifiers
        )
        defaults.set(
            1,
            forKey: Keys.translationHotkeyDefaultMigrationVersion
        )
    }

    /// Move only shipped explanation defaults to the current global shortcut.
    /// All other user choices remain intact.
    private static func migrateExplanationShortcutDefaultIfNeeded(defaults: UserDefaults) {
        let migrationVersion = defaults.integer(forKey: Keys.explanationHotkeyDefaultMigrationVersion)
        let keyCode = defaults.integer(forKey: Keys.explanationHotkeyKeyCode)
        let modifiers = defaults.integer(forKey: Keys.explanationHotkeyModifiers)
        guard shouldMigrateExplanationShortcutDefault(
            migrationVersion: migrationVersion,
            keyCode: keyCode,
            modifiers: modifiers
        ) else {
            return
        }
        defaults.set(ExplanationShortcut.defaultKeyCode, forKey: Keys.explanationHotkeyKeyCode)
        defaults.set(ExplanationShortcut.defaultModifiers, forKey: Keys.explanationHotkeyModifiers)
        defaults.set(ExplanationShortcut.migrationVersion, forKey: Keys.explanationHotkeyDefaultMigrationVersion)
    }

    static func shouldMigrateExplanationShortcutDefault(
        migrationVersion: Int,
        keyCode: Int,
        modifiers: Int
    ) -> Bool {
        guard migrationVersion < ExplanationShortcut.migrationVersion else {
            return false
        }
        return ExplanationShortcut.shippedDefaults.contains {
            keyCode == $0.keyCode && modifiers == $0.modifiers
        }
    }

    func doubaoTranslationAPIKey() -> String? {
        (try? SecureCredentialStore.read(account: "doubao-ark-api-key")) ?? nil
    }

    var explanationConfigured: Bool {
        configuredExplanationProvider() != nil
    }

    func configuredExplanationProvider() -> ExplanationProvider? {
        for profile in aiProviderProfiles {
            let endpoint = profile.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            let model = profile.model.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !endpoint.isEmpty, !model.isEmpty,
                  let apiKey = (try? SecureCredentialStore.read(
                    account: profile.credentialAccount
                  )) ?? nil,
                  !apiKey.isEmpty else {
                continue
            }
            return .openAICompatible(profile: profile, apiKey: apiKey)
        }
        guard doubaoTranslationConfigured,
              let apiKey = doubaoTranslationAPIKey(),
              !apiKey.isEmpty else {
            return nil
        }
        return .doubao(modelID: doubaoTranslationModelID, apiKey: apiKey)
    }

    func saveDoubaoTranslationAPIKey(_ apiKey: String) throws {
        try SecureCredentialStore.save(apiKey, account: "doubao-ark-api-key")
        hasDoubaoCredential = !apiKey.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty
        updateDoubaoTranslationConfigurationState()
    }

    func saveDoubaoTranslationModelID(_ modelID: String) {
        doubaoTranslationModelID = modelID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        d.set(doubaoTranslationModelID, forKey: Keys.doubaoTranslationModelID)
        updateDoubaoTranslationConfigurationState()
    }

    private func updateDoubaoTranslationConfigurationState() {
        doubaoTranslationConfigured = hasDoubaoCredential
            && !doubaoTranslationModelID.isEmpty
    }

    func addAIProviderProfile(_ profile: AIProviderProfile, apiKey: String) throws {
        try SecureCredentialStore.save(apiKey, account: profile.credentialAccount)
        aiProviderProfiles.append(profile)
        persistAIProviderProfiles()
    }

    func removeAIProviderProfile(_ profile: AIProviderProfile) throws {
        try SecureCredentialStore.delete(account: profile.credentialAccount)
        aiProviderProfiles.removeAll { $0.id == profile.id }
        persistAIProviderProfiles()
    }

    private func persistAIProviderProfiles() {
        guard let data = try? JSONEncoder().encode(aiProviderProfiles) else { return }
        d.set(data, forKey: Keys.aiProviderProfiles)
    }

    private static func loadAIProviderProfiles(from defaults: UserDefaults) -> [AIProviderProfile] {
        guard let data = defaults.data(forKey: Keys.aiProviderProfiles),
              let profiles = try? JSONDecoder().decode([AIProviderProfile].self, from: data) else {
            return []
        }
        return profiles
    }

    var retainedHistoryLimit: Int? {
        historyLimitUnlimited ? nil : historyLimit
    }

    var historyRetentionSliderPosition: Double {
        HistoryRetentionPolicy.sliderPosition(
            limit: historyLimit,
            unlimited: historyLimitUnlimited
        )
    }

    func markAccessibilityOnboardingCompleted(for build: String) {
        accessibilityAuthorizedBuild = build
        d.set(build, forKey: Keys.accessibilityAuthorizedBuild)
        onboarded = true
    }

    func setHistoryRetentionSliderPosition(_ position: Double) {
        let selection = HistoryRetentionPolicy.selection(at: position)
        let newLimit = selection ?? historyLimit
        let newUnlimited = selection == nil
        guard newLimit != historyLimit || newUnlimited != historyLimitUnlimited else {
            return
        }

        let updatedAt = Date()
        let configuration = SyncedHistoryRetentionConfiguration(
            limit: newLimit,
            unlimited: newUnlimited,
            updatedAt: updatedAt,
            effectiveAt: newUnlimited
                ? nil
                : updatedAt.addingTimeInterval(HistoryRetentionPolicy.trimDelay),
            revisionID: UUID()
        ).normalized()
        storeHistoryRetention(configuration)
        ClipboardStore.shared.historyRetentionDidChange(
            effectiveAt: configuration.effectiveAt,
            configurationChanged: true
        )
    }

    var syncedHistoryRetention: SyncedHistoryRetentionConfiguration? {
        syncedHistoryRetentionStorage
    }

    @discardableResult
    func ensureSyncedHistoryRetention(effectiveAt: Date? = nil) -> Bool {
        guard syncedHistoryRetentionStorage == nil else { return false }
        let configuration = SyncedHistoryRetentionConfiguration(
            limit: historyLimit,
            unlimited: historyLimitUnlimited,
            updatedAt: Date(),
            effectiveAt: historyLimitUnlimited
                ? nil
                : (effectiveAt ?? historyLimitTrimAfter),
            revisionID: UUID()
        ).normalized()
        storeHistoryRetention(configuration)
        return true
    }

    @discardableResult
    func publishCurrentHistoryRetention(
        effectiveAt: Date?
    ) -> SyncedHistoryRetentionConfiguration {
        let configuration = SyncedHistoryRetentionConfiguration(
            limit: historyLimit,
            unlimited: historyLimitUnlimited,
            updatedAt: Date(),
            effectiveAt: historyLimitUnlimited ? nil : effectiveAt,
            revisionID: UUID()
        ).normalized()
        storeHistoryRetention(configuration)
        return configuration
    }

    @discardableResult
    func adoptSyncedHistoryRetention(
        _ incoming: SyncedHistoryRetentionConfiguration
    ) -> Bool {
        let normalized = incoming.normalized()
        if let current = syncedHistoryRetentionStorage,
           !normalized.supersedes(current) {
            return false
        }
        storeHistoryRetention(normalized)
        return true
    }

    private func storeHistoryRetention(
        _ configuration: SyncedHistoryRetentionConfiguration
    ) {
        historyLimit = configuration.limit
        historyLimitUnlimited = configuration.unlimited
        syncedHistoryRetentionStorage = configuration
        d.set(historyLimit, forKey: Keys.historyLimit)
        d.set(historyLimitUnlimited, forKey: Keys.historyLimitUnlimited)
        d.set(configuration.updatedAt, forKey: Keys.historyRetentionUpdatedAt)
        d.set(configuration.revisionID.uuidString, forKey: Keys.historyRetentionRevisionID)
        if let effectiveAt = configuration.effectiveAt {
            d.set(effectiveAt, forKey: Keys.historyRetentionEffectiveAt)
        } else {
            d.removeObject(forKey: Keys.historyRetentionEffectiveAt)
        }
    }

    func deferHistoryLimitTrim(until date: Date) {
        historyLimitTrimAfter = date
        d.set(date, forKey: Keys.historyLimitTrimAfter)
    }

    func clearDeferredHistoryLimitTrim() {
        historyLimitTrimAfter = nil
        d.removeObject(forKey: Keys.historyLimitTrimAfter)
    }
}
