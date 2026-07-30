import AppKit
import Carbon.HIToolbox
import Foundation

/// An in-memory explanation provider. The API key is intentionally never Codable
/// and is read from macOS Keychain only when a request is about to be made.
enum ExplanationProvider {
    case doubao(modelID: String, apiKey: String)
    case openAICompatible(profile: AIProviderProfile, apiKey: String)

    var displayName: String {
        switch self {
        case .doubao:
            return L10n.doubaoTranslation
        case .openAICompatible(let profile, _):
            return profile.name
        }
    }
}

enum ExplanationShortcut {
    static let defaultKeyCode = kVK_ANSI_D
    static let defaultModifiers = cmdKey | shiftKey
    static let migrationVersion = 2
    static let previousDefaultKeyCode = kVK_ANSI_E
    static let previousDefaultModifiers = cmdKey
    static let shippedDefaults: [(keyCode: Int, modifiers: Int)] = [
        (kVK_ANSI_E, cmdKey),
        (kVK_ANSI_D, cmdKey),
    ]

    static func matches(
        keyCode: Int,
        flags: NSEvent.ModifierFlags,
        expectedKeyCode: Int,
        expectedModifiers: Int
    ) -> Bool {
        TranslationShortcut.matches(
            keyCode: keyCode,
            flags: flags,
            expectedKeyCode: expectedKeyCode,
            expectedModifiers: expectedModifiers
        )
    }
}

enum ExplanationError: LocalizedError {
    case noText
    case providerNotConfigured
    case invalidEndpoint
    case invalidResponse
    case requestFailed(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .noText: return L10n.noExplainableText
        case .providerNotConfigured: return L10n.explanationNeedsConfiguration
        case .invalidEndpoint: return L10n.aiProviderInvalidEndpoint
        case .invalidResponse: return L10n.explanationInvalidResponse
        case .requestFailed(let statusCode): return L10n.explanationRequestFailed(statusCode)
        }
    }
}
