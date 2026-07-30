import AppKit
import Foundation
import NaturalLanguage
import Observation
import OSLog
import SwiftUI

#if canImport(Translation)
@_weakLinked import Translation
#endif

enum TranslationBoardStatus: Equatable {
    case idle
    case checkingService
    case translating
    case translated
    case alreadyInTarget(String)
    case unavailable(String)
    case failed(String)
}

struct TranslationInput: Equatable {
    let id: UUID
    let text: String
    let source: TranslationLanguage
    let target: TranslationLanguage
    let resolvedSourceIdentifier: String?

    init(
        id: UUID,
        text: String,
        source: TranslationLanguage,
        target: TranslationLanguage,
        resolvedSourceIdentifier: String? = nil
    ) {
        self.id = id
        self.text = text
        self.source = source
        self.target = target
        self.resolvedSourceIdentifier = resolvedSourceIdentifier
    }

    var appleSourceIdentifier: String? {
        source.localeIdentifier ?? resolvedSourceIdentifier
    }
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
    @ObservationIgnored private var appleWorkTask: Task<Void, Never>?
    @ObservationIgnored private var appleTimeoutTask: Task<Void, Never>?

    @ObservationIgnored private static let logger = Logger(
        subsystem: "com.bifrostproxy.pesty",
        category: "translation"
    )
    private static let appleTranslationTimeoutNanoseconds: UInt64 =
        15_000_000_000

    private init() {}

    var sourceLanguage: TranslationLanguage {
        Settings.shared.translationSourceLanguage
    }

    var targetLanguage: TranslationLanguage {
        Settings.shared.translationTargetLanguage
    }

    var canSwapLanguages: Bool {
        let source = Settings.shared.translationSourceLanguage
        let target = Settings.shared.translationTargetLanguage
        return source != .automatic
            && target != .automatic
            && source != target
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
        itemID = item?.id
        present(text: item?.text, preservesItemID: true)
    }

    func present(text: String?) {
        itemID = nil
        present(text: text, preservesItemID: false)
    }

    func presentUnavailable(_ message: String) {
        cancelAppleTasks()
        appleTranslationRequest = nil
        activeRequestID = nil
        itemID = nil
        isPresented = true
        sourceText = ""
        translatedText = ""
        detectedSourceLanguage = nil
        providerName = ""
        failureDiagnostic = nil
        status = .unavailable(message)
    }

    private func present(
        text: String?,
        preservesItemID: Bool
    ) {
        cancelAppleTasks()
        appleTranslationRequest = nil
        activeRequestID = nil
        if !preservesItemID {
            itemID = nil
        }
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines),
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
        cancelAppleTasks()
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

    @discardableResult
    func swapLanguages() -> Bool {
        guard canSwapLanguages else { return false }
        let source = Settings.shared.translationSourceLanguage
        let target = Settings.shared.translationTargetLanguage
        Settings.shared.translationSourceLanguage = target
        Settings.shared.translationTargetLanguage = source
        Self.logger.notice(
            "phase=languages-swapped source=\(target.rawValue, privacy: .public) target=\(source.rawValue, privacy: .public)"
        )
        restartIfPresented()
        return true
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
        cancelAppleTasks()
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
        cancelAppleTasks()
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
        cancelAppleTasks()

        let resolution = TranslationProviderResolver.resolve(
            selected: Settings.shared.translationService,
            hasDoubaoConfiguration: Settings.shared.doubaoTranslationConfigured,
            supportsAppleTranslation: Self.supportsAppleTranslation
        )
        switch resolution {
        case .apple:
            providerName = "Apple Translate"
            Self.logger.notice(
                "phase=availability-start request=\(input.id.uuidString, privacy: .public) source=\(input.source.rawValue, privacy: .public) target=\(input.target.rawValue, privacy: .public)"
            )
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
            appleWorkTask = Task { [weak self] in
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

    private func cancelAppleTasks() {
        appleWorkTask?.cancel()
        appleWorkTask = nil
        appleTimeoutTask?.cancel()
        appleTimeoutTask = nil
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
        let preparedInput: TranslationInput
        switch prepareAppleInput(input) {
        case .translate(let resolvedInput):
            preparedInput = resolvedInput
        case .alreadyInTarget(let language):
            guard isCurrent(input.id) else { return }
            appleTranslationRequest = nil
            let languageName = displayName(
                forDetectedIdentifier: language
            )
            detectedSourceLanguage = languageName
            status = .alreadyInTarget(
                L10n.translationAlreadyInTargetLanguage(
                    languageName
                )
            )
            Self.logger.notice(
                "phase=already-in-target request=\(input.id.uuidString, privacy: .public) language=\(language, privacy: .public)"
            )
            return
        case .unidentified:
            guard isCurrent(input.id) else { return }
            Self.logger.error(
                "phase=source-unidentified request=\(input.id.uuidString, privacy: .public)"
            )
            fallbackOrShowAppleUnavailable(
                input: input,
                message: L10n.appleTranslationSourceLanguageUnidentified,
                diagnostic: "AppleSourceLanguage:unidentified"
            )
            return
        }

        do {
            let readiness = try await appleReadiness(for: preparedInput)
            guard isCurrent(input.id) else { return }
            Self.logger.notice(
                "phase=availability-complete request=\(input.id.uuidString, privacy: .public) readiness=\(String(describing: readiness), privacy: .public)"
            )
            applyAppleReadiness(readiness, to: preparedInput)
        } catch is CancellationError {
            return
        } catch {
            guard isCurrent(input.id) else { return }
            let nsError = error as NSError
            Self.logger.error(
                "phase=availability-failed request=\(input.id.uuidString, privacy: .public) domain=\(nsError.domain, privacy: .public) code=\(nsError.code)"
            )
            fallbackOrShowAppleUnavailable(
                input: preparedInput,
                message: L10n.appleTranslationCurrentlyUnavailable,
                diagnostic: "\(nsError.domain):\(nsError.code)"
            )
        }
    }

    private enum PreparedAppleInput {
        case translate(TranslationInput)
        case alreadyInTarget(String)
        case unidentified
    }

    private func prepareAppleInput(
        _ input: TranslationInput
    ) -> PreparedAppleInput {
        guard input.source == .automatic else {
            return input.source == input.target
                ? .alreadyInTarget(
                    input.source.localeIdentifier
                        ?? input.source.rawValue
                )
                : .translate(input)
        }
        let detectedIdentifier =
            NLLanguageRecognizer.dominantLanguage(for: input.text)?.rawValue
        switch AppleAutomaticSourceResolver.resolve(
            detectedIdentifier: detectedIdentifier,
            target: input.target
        ) {
        case .source(let identifier):
            detectedSourceLanguage = displayName(
                forDetectedIdentifier: identifier
            )
            return .translate(
                TranslationInput(
                    id: input.id,
                    text: input.text,
                    source: input.source,
                    target: input.target,
                    resolvedSourceIdentifier: identifier
                )
            )
        case .alreadyInTarget(let identifier):
            return .alreadyInTarget(identifier)
        case .unidentified:
            return .unidentified
        }
    }

    private func displayName(
        forDetectedIdentifier identifier: String
    ) -> String {
        if let language = TranslationLanguage.detectedLanguage(
            identifier: identifier
        ) {
            return language.displayName
        }
        return Locale.current.localizedString(
            forIdentifier: identifier
        ) ?? identifier
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
        if let sourceIdentifier = input.appleSourceIdentifier {
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
            startAppleTimeout(for: input)
            if #available(macOS 26.0, *) {
                startInstalledAppleTranslation(input)
            }
        case .doubao:
            providerName = L10n.doubaoTranslation
            status = .translating
            appleTranslationRequest = nil
            appleTimeoutTask?.cancel()
            appleTimeoutTask = nil
            startDoubaoTranslation(input)
        case .unavailable(let message):
            appleTranslationRequest = nil
            appleTimeoutTask?.cancel()
            appleTimeoutTask = nil
            status = .unavailable(message)
        }
    }

    @available(macOS 26.0, *)
    private func startInstalledAppleTranslation(
        _ input: TranslationInput
    ) {
        guard let sourceIdentifier = input.appleSourceIdentifier,
              let targetIdentifier = input.target.localeIdentifier else {
            fallbackOrShowAppleUnavailable(
                input: input,
                message: L10n.appleTranslationSourceLanguageUnidentified,
                diagnostic: "AppleSourceLanguage:missing"
            )
            return
        }
        appleWorkTask?.cancel()
        appleWorkTask = Task { [weak self] in
            guard let self else { return }
            do {
                let session = TranslationSession(
                    installedSource:
                        Locale.Language(identifier: sourceIdentifier),
                    target: Locale.Language(identifier: targetIdentifier)
                )
                Self.logger.notice(
                    "phase=session-created request=\(input.id.uuidString, privacy: .public) mode=direct"
                )
                let response = try await withTaskCancellationHandler {
                    try await session.translate(input.text)
                } onCancel: {
                    session.cancel()
                }
                guard !Task.isCancelled else { return }
                completeAppleTranslation(
                    result: .success(response.targetText),
                    for: input.id
                )
            } catch is CancellationError {
                return
            } catch {
                completeAppleTranslation(
                    result: .failure(error),
                    for: input.id
                )
            }
        }
    }

    private func startAppleTimeout(for input: TranslationInput) {
        appleTimeoutTask?.cancel()
        appleTimeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(
                    nanoseconds:
                        TranslationCenter.appleTranslationTimeoutNanoseconds
                )
            } catch {
                return
            }
            guard let self,
                  self.isCurrent(input.id),
                  self.status == .translating else {
                return
            }
            self.appleWorkTask?.cancel()
            self.appleWorkTask = nil
            self.appleTranslationRequest = nil
            self.failureDiagnostic = "AppleTranslationTimeout:1"
            self.status = .failed(L10n.appleTranslationTimedOut)
            Self.logger.error(
                "phase=timeout request=\(input.id.uuidString, privacy: .public)"
            )
        }
    }

    private func fallbackOrShowAppleUnavailable(
        input: TranslationInput,
        message: String,
        diagnostic: String
    ) {
        appleTranslationRequest = nil
        appleTimeoutTask?.cancel()
        appleTimeoutTask = nil
        failureDiagnostic = diagnostic
        if TranslationProviderResolver.shouldFallbackFromApple(
            selected: Settings.shared.translationService,
            hasDoubaoConfiguration:
                Settings.shared.doubaoTranslationConfigured
        ) {
            providerName = L10n.doubaoTranslation
            status = .translating
            startDoubaoTranslation(input)
        } else {
            status = .unavailable(message)
        }
    }

    func performAppleTranslation(using session: TranslationSession) async {
        guard let input = appleTranslationRequest else {
            return
        }
        Self.logger.notice(
            "phase=session-created request=\(input.id.uuidString, privacy: .public) mode=swiftui"
        )
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
            appleTimeoutTask?.cancel()
            appleTimeoutTask = nil
            providerName = L10n.doubaoTranslation
            status = .translating
            startDoubaoTranslation(input)
        case .unavailable(let message):
            appleTranslationRequest = nil
            appleTimeoutTask?.cancel()
            appleTimeoutTask = nil
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
        appleTimeoutTask?.cancel()
        appleTimeoutTask = nil
        appleWorkTask = nil
        switch result {
        case .success(let text):
            translatedText = text
            status = .translated
            Self.logger.notice(
                "phase=completed request=\(inputID.uuidString, privacy: .public) outputLength=\(text.count)"
            )
        case .failure(let error):
            let nsError = error as NSError
            Self.logger.error(
                "phase=failed request=\(inputID.uuidString, privacy: .public) domain=\(nsError.domain, privacy: .public) code=\(nsError.code)"
            )
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
        let source = request.appleSourceIdentifier.map(
            Locale.Language.init(identifier:)
        )
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
        if #available(macOS 26.0, *) {
            self
        } else if #available(macOS 15.0, *) {
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
