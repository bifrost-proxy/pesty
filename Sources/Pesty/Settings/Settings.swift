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
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyModifiers = "hotkeyModifiers"
        static let launchAtLogin = "launchAtLogin"
        static let showMenuBarIcon = "showMenuBarIcon"
        static let pasteDirectly = "pasteDirectly"
        static let playSound = "playSound"
        static let ignoreConcealed = "ignoreConcealed"
        static let barHeight = "barHeight"
        static let onboarded = "onboarded"
        static let iCloudSync = "iCloudSync"
        static let language = "language"
    }

    var historyLimit: Int {
        didSet {
            guard isLoaded else { return }
            let normalized = HistoryRetentionPolicy.normalized(historyLimit)
            if historyLimit != normalized { historyLimit = normalized; return }
            d.set(historyLimit, forKey: Keys.historyLimit)
            ClipboardStore.shared.historyRetentionDidChange()
        }
    }

    var historyLimitUnlimited: Bool {
        didSet {
            guard isLoaded else { return }
            d.set(historyLimitUnlimited, forKey: Keys.historyLimitUnlimited)
            ClipboardStore.shared.historyRetentionDidChange()
        }
    }

    private(set) var historyLimitTrimAfter: Date?

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

    private init() {
        if let suiteName = ProcessInfo.processInfo.environment[
            "PESTY_AUTOMATED_TEST_DEFAULTS_SUITE"
        ], !suiteName.isEmpty, let testDefaults = UserDefaults(suiteName: suiteName) {
            d = testDefaults
        } else {
            d = .standard
        }
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
            Keys.barHeight: 430.0,
            Keys.onboarded: false,
            Keys.iCloudSync: false,
            Keys.language: AppLanguage.systemDefault.rawValue
        ])
        historyLimit = HistoryRetentionPolicy.normalized(d.integer(forKey: Keys.historyLimit))
        historyLimitUnlimited = d.bool(forKey: Keys.historyLimitUnlimited)
        historyLimitTrimAfter = d.object(forKey: Keys.historyLimitTrimAfter) as? Date
        hotkeyKeyCode = d.integer(forKey: Keys.hotkeyKeyCode)
        hotkeyModifiers = d.integer(forKey: Keys.hotkeyModifiers)
        launchAtLogin = d.bool(forKey: Keys.launchAtLogin)
        showMenuBarIcon = d.bool(forKey: Keys.showMenuBarIcon)
        pasteDirectly = d.bool(forKey: Keys.pasteDirectly)
        playSound = d.bool(forKey: Keys.playSound)
        ignoreConcealed = d.bool(forKey: Keys.ignoreConcealed)
        barHeight = d.double(forKey: Keys.barHeight)
        onboarded = d.bool(forKey: Keys.onboarded)
        iCloudSync = d.bool(forKey: Keys.iCloudSync)
        language = AppLanguage(rawValue: d.string(forKey: Keys.language) ?? "") ?? .systemDefault
        isLoaded = true
    }

    var hotkeyDisplay: String {
        HotKeyCenter.describe(keyCode: hotkeyKeyCode, modifiers: hotkeyModifiers)
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

    func setHistoryRetentionSliderPosition(_ position: Double) {
        if let limit = HistoryRetentionPolicy.selection(at: position) {
            historyLimit = limit
            historyLimitUnlimited = false
        } else {
            historyLimitUnlimited = true
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
