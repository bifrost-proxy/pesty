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
