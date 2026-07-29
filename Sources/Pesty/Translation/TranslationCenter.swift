import Foundation
import Observation
import SwiftUI

#if canImport(Translation)
@_weakLinked import Translation
#endif

enum TranslationBoardStatus: Equatable {
    case idle
    case translating
    case translated
    case unavailable(String)
    case failed(String)
}

struct TranslationInput: Equatable {
    let id: UUID
    let text: String
    let source: TranslationLanguage
    let target: TranslationLanguage
}

@Observable
@MainActor
final class TranslationCenter {
    static let shared = TranslationCenter()

    private(set) var isPresented = false
    private(set) var sourceText = ""
    private(set) var translatedText = ""
    private(set) var detectedSourceLanguage: String?
    private(set) var providerName = ""
    private(set) var status: TranslationBoardStatus = .idle
    /// Sanitized transport/provider error metadata for diagnostics. Never contains input text,
    /// translated text, credentials, or response bodies.
    private(set) var failureDiagnostic: String?
    private(set) var appleTranslationRequest: TranslationInput?
    private var activeRequestID: UUID?

    private init() {}

    var sourceLanguage: TranslationLanguage {
        Settings.shared.translationSourceLanguage
    }

    var targetLanguage: TranslationLanguage {
        Settings.shared.translationTargetLanguage
    }

    var appleTranslationSupported: Bool { Self.supportsAppleTranslation }

    var doubaoTranslationConfigured: Bool {
        Settings.shared.doubaoTranslationConfigured
    }

    func toggle(for item: ClipItem?) {
        if isPresented {
            dismiss()
        } else {
            present(for: item)
        }
    }

    func present(for item: ClipItem?) {
        guard let text = item?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            isPresented = true
            sourceText = ""
            translatedText = ""
            detectedSourceLanguage = nil
            providerName = ""
            status = .unavailable(L10n.noTranslatableText)
            return
        }
        isPresented = true
        sourceText = text
        translatedText = ""
        detectedSourceLanguage = nil
        translateCurrentText()
    }

    func dismiss() {
        AssistantPopoverController.shared.dismiss(kind: .translation)
        isPresented = false
        sourceText = ""
        translatedText = ""
        detectedSourceLanguage = nil
        providerName = ""
        failureDiagnostic = nil
        status = .idle
        appleTranslationRequest = nil
        activeRequestID = nil
    }

    func setSourceLanguage(_ language: TranslationLanguage) {
        Settings.shared.translationSourceLanguage = language
        restartIfPresented()
    }

    func setTargetLanguage(_ language: TranslationLanguage) {
        guard language != .automatic else { return }
        Settings.shared.translationTargetLanguage = language
        restartIfPresented()
    }

    func setService(_ service: TranslationService) {
        Settings.shared.translationService = service
        restartIfPresented()
    }

    func retry() {
        guard !sourceText.isEmpty else { return }
        translateCurrentText()
    }

    func showAutomatedPreview(source: String, translation: String) {
        guard ProcessInfo.processInfo.environment["PESTY_AUTOMATED_UI_TEST"] != nil else {
            return
        }
        isPresented = true
        sourceText = source
        translatedText = translation
        detectedSourceLanguage = "English"
        providerName = "Automated preview"
        status = .translated
        appleTranslationRequest = nil
        activeRequestID = nil
    }

    private func restartIfPresented() {
        guard isPresented, !sourceText.isEmpty else { return }
        translateCurrentText()
    }

    private func translateCurrentText() {
        let input = TranslationInput(
            id: UUID(),
            text: sourceText,
            source: Settings.shared.translationSourceLanguage,
            target: Settings.shared.translationTargetLanguage
        )
        translatedText = ""
        detectedSourceLanguage = nil
        failureDiagnostic = nil
        status = .translating
        appleTranslationRequest = nil
        activeRequestID = input.id

        let resolution = TranslationProviderResolver.resolve(
            selected: Settings.shared.translationService,
            hasDoubaoConfiguration: Settings.shared.doubaoTranslationConfigured,
            supportsAppleTranslation: Self.supportsAppleTranslation
        )
        switch resolution {
        case .apple:
            providerName = "Apple Translate"
            appleTranslationRequest = input
        case .doubao:
            providerName = L10n.doubaoTranslation
            startDoubaoTranslation(input)
        case .unavailable(let message):
            providerName = ""
            status = .unavailable(message)
        }
    }

    private func startDoubaoTranslation(_ input: TranslationInput) {
        guard let apiKey = Settings.shared.doubaoTranslationAPIKey(),
              !apiKey.isEmpty,
              !Settings.shared.doubaoTranslationModelID.isEmpty else {
            status = .unavailable(L10n.doubaoTranslationNeedsConfiguration)
            return
        }
        let modelID = Settings.shared.doubaoTranslationModelID
        DoubaoTranslationClient.translate(
            text: input.text,
            source: input.source,
            target: input.target,
            modelID: modelID,
            apiKey: apiKey
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let translation):
                    self.completeDoubaoTranslation(translation, for: input.id)
                case .failure(let error):
                    self.failTranslation(error, for: input.id)
                }
            }
        }
    }

    private func completeDoubaoTranslation(_ translation: String, for inputID: UUID) {
        guard isCurrent(inputID) else { return }
        translatedText = translation
        if Settings.shared.translationSourceLanguage != .automatic {
            detectedSourceLanguage = Settings.shared.translationSourceLanguage.displayName
        }
        status = .translated
    }

    private func failTranslation(_ error: Error, for inputID: UUID) {
        guard isCurrent(inputID) else { return }
        let nsError = error as NSError
        failureDiagnostic = "\(nsError.domain):\(nsError.code)"
        status = .failed(
            (error as? LocalizedError)?.errorDescription
                ?? L10n.translationFailed
        )
    }

    private func isCurrent(_ inputID: UUID) -> Bool {
        guard isPresented else { return false }
        return activeRequestID == inputID
    }

    private static var supportsAppleTranslation: Bool {
        if #available(macOS 15.0, *) { return true }
        return false
    }
}

#if canImport(Translation)
@available(macOS 15.0, *)
extension TranslationCenter {
    func performAppleTranslation(using session: TranslationSession) async {
        guard let input = appleTranslationRequest,
              let targetIdentifier = input.target.localeIdentifier else {
            return
        }
        do {
            let target = Locale.Language(identifier: targetIdentifier)
            let availability = LanguageAvailability()
            let availabilityStatus = try await availability.status(
                for: input.text,
                to: target
            )
            guard availabilityStatus != .unsupported else {
                completeAppleTranslation(
                    result: .failure(TranslationServiceError.appleLanguagePairUnavailable),
                    for: input.id
                )
                return
            }
            let response = try await session.translate(input.text)
            completeAppleTranslation(result: .success(response.targetText), for: input.id)
        } catch {
            completeAppleTranslation(result: .failure(error), for: input.id)
        }
    }

    private func completeAppleTranslation(
        result: Result<String, Error>,
        for inputID: UUID
    ) {
        guard isPresented, appleTranslationRequest?.id == inputID else { return }
        switch result {
        case .success(let text):
            translatedText = text
            status = .translated
        case .failure(let error):
            status = .failed(
                (error as? LocalizedError)?.errorDescription
                    ?? L10n.translationFailed
            )
        }
    }
}

@available(macOS 15.0, *)
private struct AppleTranslationTaskModifier: ViewModifier {
    @Bindable var center: TranslationCenter
    @State private var configuration: TranslationSession.Configuration?

    func body(content: Content) -> some View {
        content
            .onAppear { configure(for: center.appleTranslationRequest) }
            .onChange(of: center.appleTranslationRequest) { _, request in
                configure(for: request)
            }
            .translationTask(configuration) { session in
                await center.performAppleTranslation(using: session)
            }
    }

    private func configure(for request: TranslationInput?) {
        guard let request,
              let targetIdentifier = request.target.localeIdentifier else {
            configuration = nil
            return
        }
        let source = request.source.localeIdentifier.map(Locale.Language.init(identifier:))
        let target = Locale.Language(identifier: targetIdentifier)
        if var existing = configuration,
           existing.source == source,
           existing.target == target {
            existing.invalidate()
            configuration = existing
        } else {
            configuration = TranslationSession.Configuration(source: source, target: target)
        }
    }
}

extension View {
    @ViewBuilder
    func attachAppleTranslationTask(_ center: TranslationCenter) -> some View {
        if #available(macOS 15.0, *) {
            modifier(AppleTranslationTaskModifier(center: center))
        } else {
            self
        }
    }
}
#else
extension View {
    func attachAppleTranslationTask(_ center: TranslationCenter) -> some View { self }
}
#endif

private extension String {
    var htmlUnescaped: String {
        replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}
