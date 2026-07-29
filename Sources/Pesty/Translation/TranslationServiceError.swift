import Foundation

enum TranslationServiceError: LocalizedError {
    case noTranslatableText
    case targetLanguageRequired
    case doubaoEndpointRequired
    case invalidDoubaoResponse
    case doubaoRequestFailed(statusCode: Int)
    case appleLanguagePairUnavailable

    var errorDescription: String? {
        switch self {
        case .noTranslatableText:
            return L10n.noTranslatableText
        case .targetLanguageRequired:
            return L10n.targetLanguageRequired
        case .doubaoEndpointRequired:
            return L10n.doubaoTranslationNeedsConfiguration
        case .invalidDoubaoResponse:
            return L10n.translationServiceReturnedInvalidResponse
        case .doubaoRequestFailed(let statusCode):
            return L10n.doubaoTranslationRequestFailed(statusCode)
        case .appleLanguagePairUnavailable:
            return L10n.appleLanguagePairUnavailable
        }
    }
}
