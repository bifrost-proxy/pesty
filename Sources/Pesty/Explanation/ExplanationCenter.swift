import Foundation
import Observation

enum ExplanationBoardStatus: Equatable {
    case idle
    case explaining
    case explained
    case unavailable(String)
    case failed(String)
}

@Observable
@MainActor
final class ExplanationCenter {
    static let shared = ExplanationCenter()

    private(set) var isPresented = false
    private(set) var sourceText = ""
    private(set) var explanationText = ""
    private(set) var providerName = ""
    private(set) var status: ExplanationBoardStatus = .idle
    /// Sanitized provider/transport metadata only. Never includes clipboard text,
    /// generated output, credentials, or raw responses.
    private(set) var failureDiagnostic: String?
    private var activeRequestID: UUID?

    private init() {}

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
            explanationText = ""
            providerName = ""
            failureDiagnostic = nil
            status = .unavailable(L10n.noExplainableText)
            return
        }

        isPresented = true
        sourceText = text
        explanationText = ""
        failureDiagnostic = nil
        explainCurrentText()
    }

    func dismiss() {
        AssistantPopoverController.shared.dismiss(kind: .explanation)
        isPresented = false
        sourceText = ""
        explanationText = ""
        providerName = ""
        failureDiagnostic = nil
        status = .idle
        activeRequestID = nil
    }

    func retry() {
        guard !sourceText.isEmpty else { return }
        explainCurrentText()
    }

    func showAutomatedPreview(source: String, explanation: String) {
        guard ProcessInfo.processInfo.environment["PESTY_AUTOMATED_UI_TEST"] != nil else {
            return
        }
        isPresented = true
        sourceText = source
        explanationText = explanation
        providerName = "Automated preview"
        failureDiagnostic = nil
        activeRequestID = nil
        status = .explained
    }

    private func explainCurrentText() {
        let requestID = UUID()
        explanationText = ""
        failureDiagnostic = nil
        activeRequestID = requestID
        guard let provider = Settings.shared.configuredExplanationProvider() else {
            providerName = ""
            status = .unavailable(L10n.explanationNeedsConfiguration)
            return
        }
        providerName = provider.displayName
        status = .explaining
        ExplanationClient.explain(text: sourceText, provider: provider) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.isPresented, self.activeRequestID == requestID else { return }
                switch result {
                case .success(let explanation):
                    self.explanationText = explanation
                    self.status = .explained
                case .failure(let error):
                    let nsError = error as NSError
                    self.failureDiagnostic = "\(nsError.domain):\(nsError.code)"
                    self.status = .failed(
                        (error as? LocalizedError)?.errorDescription ?? L10n.explanationFailed
                    )
                }
            }
        }
    }
}
