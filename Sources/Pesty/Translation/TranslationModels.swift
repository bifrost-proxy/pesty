import AppKit
import Carbon.HIToolbox
import Foundation

enum TranslationService: String, CaseIterable, Codable, Identifiable {
    case automatic
    case apple
    case doubao

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic: return L10n.automatic
        case .apple: return "Apple Translate"
        case .doubao: return L10n.doubaoTranslation
        }
    }
}

enum TranslationLanguage: String, CaseIterable, Codable, Identifiable {
    case automatic
    case english
    case simplifiedChinese
    case japanese
    case korean
    case french
    case german
    case spanish

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic: return L10n.automatic
        case .english: return L10n.english
        case .simplifiedChinese: return L10n.simplifiedChinese
        case .japanese: return L10n.japanese
        case .korean: return L10n.korean
        case .french: return L10n.french
        case .german: return L10n.german
        case .spanish: return L10n.spanish
        }
    }

    var localeIdentifier: String? {
        switch self {
        case .automatic: return nil
        case .english: return "en"
        case .simplifiedChinese: return "zh-Hans"
        case .japanese: return "ja"
        case .korean: return "ko"
        case .french: return "fr"
        case .german: return "de"
        case .spanish: return "es"
        }
    }

    static func detectedLanguage(identifier: String) -> TranslationLanguage? {
        let normalized = identifier
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
        if normalized == "en" || normalized.hasPrefix("en-") { return .english }
        if normalized == "zh" || normalized.hasPrefix("zh-") {
            return .simplifiedChinese
        }
        if normalized == "ja" || normalized.hasPrefix("ja-") { return .japanese }
        if normalized == "ko" || normalized.hasPrefix("ko-") { return .korean }
        if normalized == "fr" || normalized.hasPrefix("fr-") { return .french }
        if normalized == "de" || normalized.hasPrefix("de-") { return .german }
        if normalized == "es" || normalized.hasPrefix("es-") { return .spanish }
        return nil
    }
}

enum AppleAutomaticSourceResolution: Equatable {
    case source(identifier: String)
    case alreadyInTarget(identifier: String)
    case unidentified
}

enum AppleAutomaticSourceResolver {
    static func resolve(
        detectedIdentifier: String?,
        target: TranslationLanguage
    ) -> AppleAutomaticSourceResolution {
        guard let detectedIdentifier,
              !detectedIdentifier.isEmpty,
              let targetIdentifier = target.localeIdentifier else {
            return .unidentified
        }
        if Locale.Language(identifier: detectedIdentifier)
            == Locale.Language(identifier: targetIdentifier) {
            return .alreadyInTarget(identifier: detectedIdentifier)
        }
        return .source(identifier: detectedIdentifier)
    }
}

enum AIProviderKind: String, CaseIterable, Codable, Identifiable {
    case openAICompatible

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAICompatible: return L10n.openAICompatible
        }
    }
}

/// Public, non-secret metadata for a reusable AI provider. The corresponding
/// API key is kept separately in Keychain and is never written to preferences
/// or the synchronized clipboard store.
struct AIProviderProfile: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var kind: AIProviderKind
    var endpoint: String
    var model: String

    init(
        id: UUID = UUID(),
        name: String,
        kind: AIProviderKind = .openAICompatible,
        endpoint: String,
        model: String
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.endpoint = endpoint
        self.model = model
    }

    var credentialAccount: String { "ai-provider-api-key-\(id.uuidString)" }
}

enum TranslationResolution: Equatable {
    case apple
    case doubao
    case unavailable(String)
}

enum AppleTranslationReadiness: Equatable {
    case installed
    case downloadRequired
    case unsupported
}

struct AppleTranslationPackRequirement: Equatable, Identifiable {
    enum Kind: Equatable {
        case baseline
        case selected
    }

    let source: TranslationLanguage
    let target: TranslationLanguage
    let kind: Kind

    var id: String {
        [source.rawValue, target.rawValue].sorted().joined(separator: "-")
    }
}

enum AppleTranslationPackPlanner {
    static func requirements(
        source: TranslationLanguage,
        target: TranslationLanguage
    ) -> [AppleTranslationPackRequirement] {
        let baseline = AppleTranslationPackRequirement(
            source: .english,
            target: .simplifiedChinese,
            kind: .baseline
        )
        let selectedSource = source == .automatic
            ? automaticCheckSource(for: target)
            : source
        let selected = AppleTranslationPackRequirement(
            source: selectedSource,
            target: target,
            kind: .selected
        )
        guard selected.id != baseline.id else { return [baseline] }
        return [baseline, selected]
    }

    private static func automaticCheckSource(
        for target: TranslationLanguage
    ) -> TranslationLanguage {
        target == .english ? .simplifiedChinese : .english
    }
}

enum TranslationProviderResolver {
    static func resolve(
        selected: TranslationService,
        hasDoubaoConfiguration: Bool,
        supportsAppleTranslation: Bool
    ) -> TranslationResolution {
        switch selected {
        case .automatic:
            if supportsAppleTranslation { return .apple }
            if hasDoubaoConfiguration { return .doubao }
            return .unavailable(L10n.translationNeedsService)
        case .apple:
            return supportsAppleTranslation
                ? .apple
                : .unavailable(L10n.appleTranslationRequiresMacOS15)
        case .doubao:
            return hasDoubaoConfiguration
                ? .doubao
                : .unavailable(L10n.doubaoTranslationNeedsConfiguration)
        }
    }

    static func shouldFallbackFromApple(
        selected: TranslationService,
        hasDoubaoConfiguration: Bool
    ) -> Bool {
        selected == .automatic && hasDoubaoConfiguration
    }

    static func resolveAppleReadiness(
        selected: TranslationService,
        hasDoubaoConfiguration: Bool,
        readiness: AppleTranslationReadiness
    ) -> TranslationResolution {
        switch readiness {
        case .installed:
            return .apple
        case .downloadRequired:
            if shouldFallbackFromApple(
                selected: selected,
                hasDoubaoConfiguration: hasDoubaoConfiguration
            ) {
                return .doubao
            }
            return .unavailable(
                L10n.appleTranslationLanguagePacksNotInstalled
            )
        case .unsupported:
            if shouldFallbackFromApple(
                selected: selected,
                hasDoubaoConfiguration: hasDoubaoConfiguration
            ) {
                return .doubao
            }
            return .unavailable(L10n.appleLanguagePairUnavailable)
        }
    }
}

enum TranslationShortcut {
    static let defaultKeyCode = kVK_ANSI_T
    static let defaultModifiers = cmdKey

    static func matches(
        keyCode: Int,
        flags: NSEvent.ModifierFlags,
        expectedKeyCode: Int,
        expectedModifiers: Int
    ) -> Bool {
        let relevant: NSEvent.ModifierFlags = [
            .command, .control, .option, .shift,
        ]
        let eventModifiers = flags.intersection(relevant)
        var expected: NSEvent.ModifierFlags = []
        if expectedModifiers & cmdKey != 0 { expected.insert(.command) }
        if expectedModifiers & controlKey != 0 { expected.insert(.control) }
        if expectedModifiers & optionKey != 0 { expected.insert(.option) }
        if expectedModifiers & shiftKey != 0 { expected.insert(.shift) }
        return keyCode == expectedKeyCode && eventModifiers == expected
    }
}

enum TranslationLanguageSwapShortcut {
    static let defaultKeyCode = kVK_ANSI_T

    static func matches(
        keyCode: Int,
        flags: NSEvent.ModifierFlags
    ) -> Bool {
        let disallowedModifiers: NSEvent.ModifierFlags = [
            .command, .control, .option, .shift,
        ]
        return keyCode == defaultKeyCode
            && flags.intersection(disallowedModifiers).isEmpty
    }
}
