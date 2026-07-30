import AppKit
import Foundation
import Observation
import SwiftUI

#if canImport(Translation)
@_weakLinked import Translation
#endif

enum TranslationBoardStatus: Equatable {
    case idle
    case checkingService
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
    private(set) var itemID: UUID?
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
    @ObservationIgnored private var appleAvailabilityTask:
        Task<Void, Never>?

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
        appleAvailabilityTask?.cancel()
        appleAvailabilityTask = nil
        appleTranslationRequest = nil
        activeRequestID = nil
        itemID = item?.id
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
        itemID = nil
        sourceText = ""
        translatedText = ""
        detectedSourceLanguage = nil
        providerName = ""
        failureDiagnostic = nil
        status = .idle
        appleTranslationRequest = nil
        activeRequestID = nil
        appleAvailabilityTask?.cancel()
        appleAvailabilityTask = nil
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

    func showAutomatedPreview(
        source: String,
        translation: String,
        itemID: UUID? = nil
    ) {
        guard ProcessInfo.processInfo.environment["PESTY_AUTOMATED_UI_TEST"] != nil else {
            return
        }
        isPresented = true
        self.itemID = itemID
        sourceText = source
        translatedText = translation
        detectedSourceLanguage = "English"
        providerName = "Automated preview"
        status = .translated
        appleTranslationRequest = nil
        activeRequestID = nil
        appleAvailabilityTask?.cancel()
        appleAvailabilityTask = nil
    }

    func showAutomatedProcessing(for item: ClipItem) {
        guard ProcessInfo.processInfo.environment["PESTY_AUTOMATED_UI_TEST"] != nil,
              let text = item.text else {
            return
        }
        isPresented = true
        itemID = item.id
        sourceText = text
        translatedText = ""
        detectedSourceLanguage = nil
        providerName = "Automated preview"
        failureDiagnostic = nil
        status = .translating
        appleTranslationRequest = nil
        activeRequestID = nil
        appleAvailabilityTask?.cancel()
        appleAvailabilityTask = nil
    }

    @discardableResult
    func copyResult(to pasteboard: NSPasteboard = .general) -> Bool {
        guard status == .translated, !translatedText.isEmpty else { return false }
        pasteboard.clearContents()
        return pasteboard.setString(translatedText, forType: .string)
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
        status = .checkingService
        appleTranslationRequest = nil
        activeRequestID = input.id
        appleAvailabilityTask?.cancel()
        appleAvailabilityTask = nil

        let resolution = TranslationProviderResolver.resolve(
            selected: Settings.shared.translationService,
            hasDoubaoConfiguration: Settings.shared.doubaoTranslationConfigured,
            supportsAppleTranslation: Self.supportsAppleTranslation
        )
        switch resolution {
        case .apple:
            providerName = "Apple Translate"
            startAppleAvailabilityCheck(input)
        case .doubao:
            providerName = L10n.doubaoTranslation
            status = .translating
            startDoubaoTranslation(input)
        case .unavailable(let message):
            providerName = ""
            status = .unavailable(message)
        }
    }

    private func startAppleAvailabilityCheck(
        _ input: TranslationInput
    ) {
        #if canImport(Translation)
        if #available(macOS 15.0, *) {
            appleAvailabilityTask = Task { [weak self] in
                guard let self else { return }
                await self.checkAppleAvailability(for: input)
            }
            return
        }
        #endif
        status = .unavailable(L10n.appleTranslationRequiresMacOS15)
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
    private func checkAppleAvailability(
        for input: TranslationInput
    ) async {
        do {
            let readiness = try await appleReadiness(for: input)
            guard isCurrent(input.id) else { return }
            applyAppleReadiness(readiness, to: input)
        } catch is CancellationError {
            return
        } catch {
            guard isCurrent(input.id) else { return }
            if TranslationProviderResolver.shouldFallbackFromApple(
                selected: Settings.shared.translationService,
                hasDoubaoConfiguration:
                    Settings.shared.doubaoTranslationConfigured
            ) {
                providerName = L10n.doubaoTranslation
                status = .translating
                startDoubaoTranslation(input)
                return
            }
            let nsError = error as NSError
            failureDiagnostic = "\(nsError.domain):\(nsError.code)"
            status = .unavailable(
                L10n.appleTranslationCurrentlyUnavailable
            )
        }
    }

    private func appleReadiness(
        for input: TranslationInput
    ) async throws -> AppleTranslationReadiness {
        guard let targetIdentifier = input.target.localeIdentifier else {
            return .unsupported
        }
        let target = Locale.Language(identifier: targetIdentifier)
        let availability = LanguageAvailability()
        let availabilityStatus: LanguageAvailability.Status
        if let sourceIdentifier = input.source.localeIdentifier {
            availabilityStatus = await availability.status(
                from: Locale.Language(identifier: sourceIdentifier),
                to: target
            )
        } else {
            availabilityStatus = try await availability.status(
                for: input.text,
                to: target
            )
        }
        switch availabilityStatus {
        case .installed:
            return .installed
        case .supported:
            return .downloadRequired
        case .unsupported:
            return .unsupported
        @unknown default:
            return .unsupported
        }
    }

    private func applyAppleReadiness(
        _ readiness: AppleTranslationReadiness,
        to input: TranslationInput
    ) {
        let resolution = TranslationProviderResolver.resolveAppleReadiness(
            selected: Settings.shared.translationService,
            hasDoubaoConfiguration:
                Settings.shared.doubaoTranslationConfigured,
            readiness: readiness
        )
        switch resolution {
        case .apple:
            status = .translating
            appleTranslationRequest = input
        case .doubao:
            providerName = L10n.doubaoTranslation
            status = .translating
            appleTranslationRequest = nil
            startDoubaoTranslation(input)
        case .unavailable(let message):
            appleTranslationRequest = nil
            status = .unavailable(message)
        }
    }

    func performAppleTranslation(using session: TranslationSession) async {
        guard let input = appleTranslationRequest else {
            return
        }
        do {
            let readiness = try await appleReadiness(for: input)
            guard readiness == .installed else {
                completeAppleUnavailable(
                    readiness: readiness,
                    for: input
                )
                return
            }
            let response = try await session.translate(input.text)
            completeAppleTranslation(result: .success(response.targetText), for: input.id)
        } catch {
            if let readiness = try? await appleReadiness(for: input),
               readiness != .installed {
                completeAppleUnavailable(
                    readiness: readiness,
                    for: input
                )
                return
            }
            completeAppleTranslation(result: .failure(error), for: input.id)
        }
    }

    private func completeAppleUnavailable(
        readiness: AppleTranslationReadiness,
        for input: TranslationInput
    ) {
        guard isPresented,
              appleTranslationRequest?.id == input.id else {
            return
        }
        let resolution = TranslationProviderResolver.resolveAppleReadiness(
            selected: Settings.shared.translationService,
            hasDoubaoConfiguration:
                Settings.shared.doubaoTranslationConfigured,
            readiness: readiness
        )
        switch resolution {
        case .doubao:
            appleTranslationRequest = nil
            providerName = L10n.doubaoTranslation
            status = .translating
            startDoubaoTranslation(input)
        case .unavailable(let message):
            appleTranslationRequest = nil
            status = .unavailable(message)
        case .apple:
            break
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
            if TranslationProviderResolver.shouldFallbackFromApple(
                selected: Settings.shared.translationService,
                hasDoubaoConfiguration:
                    Settings.shared.doubaoTranslationConfigured
            ),
               let input = appleTranslationRequest,
               input.id == inputID {
                appleTranslationRequest = nil
                providerName = L10n.doubaoTranslation
                startDoubaoTranslation(input)
                return
            }
            let nsError = error as NSError
            failureDiagnostic = "\(nsError.domain):\(nsError.code)"
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
