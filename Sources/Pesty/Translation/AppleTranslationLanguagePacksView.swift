import SwiftUI

#if canImport(Translation)
@_weakLinked import Translation
#endif

struct AppleTranslationLanguagePacksView: View {
    let source: TranslationLanguage
    let target: TranslationLanguage

    private var requirements: [AppleTranslationPackRequirement] {
        AppleTranslationPackPlanner.requirements(
            source: source,
            target: target
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.appleTranslationLanguagePacks)
                    .font(.callout.weight(.medium))
                Text(L10n.appleTranslationLanguagePacksDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(requirements) { requirement in
                AppleTranslationLanguagePackRow(
                    requirement: requirement
                )
            }

            if source == .automatic {
                Label(
                    L10n.appleTranslationLanguagePacksAutomaticSourceNote,
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("pesty-apple-translation-language-packs")
        .onAppear {
            AutomatedUITestProbe.recordAppleLanguagePackSettings()
        }
    }
}

private struct AppleTranslationLanguagePackRow: View {
    let requirement: AppleTranslationPackRequirement

    var body: some View {
        Group {
            #if canImport(Translation)
            if #available(macOS 15.0, *) {
                AvailableAppleTranslationLanguagePackRow(
                    requirement: requirement
                )
            } else {
                unavailableForSystem
            }
            #else
            unavailableForSystem
            #endif
        }
        .padding(10)
        .background(
            Color.primary.opacity(0.035),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
    }

    private var unavailableForSystem: some View {
        HStack(alignment: .top, spacing: 10) {
            pairDescription
            Spacer(minLength: 12)
            Label(
                L10n.appleTranslationRequiresMacOS15,
                systemImage: "exclamationmark.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    fileprivate var pairDescription: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(
                requirement.kind == .baseline
                    ? L10n.appleTranslationBaselinePack
                    : L10n.appleTranslationSelectedPack
            )
            .font(.caption.weight(.semibold))
            Text(
                "\(requirement.source.displayName) → "
                    + requirement.target.displayName
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

#if canImport(Translation)
@available(macOS 15.0, *)
private struct AvailableAppleTranslationLanguagePackRow: View {
    private enum PackState: Equatable {
        case checking
        case installed
        case downloadRequired
        case downloading
        case unsupported
        case failed(String)
    }

    let requirement: AppleTranslationPackRequirement

    @State private var state: PackState = .checking
    @State private var configuration:
        TranslationSession.Configuration?
    @State private var downloadRequested = false

    private var taskID: String {
        "\(requirement.source.rawValue)>\(requirement.target.rawValue)"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            AppleTranslationLanguagePackRow(
                requirement: requirement
            ).pairDescription
            Spacer(minLength: 12)
            statusContent
        }
        .task(id: taskID) {
            configuration = nil
            downloadRequested = false
            await refreshStatus()
        }
        .translationTask(configuration) { session in
            guard downloadRequested else { return }
            await prepareTranslation(using: session)
        }
    }

    @ViewBuilder
    private var statusContent: some View {
        switch state {
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(L10n.appleTranslationLanguagePacksChecking)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        case .installed:
            Label(
                L10n.appleTranslationLanguagePacksInstalled,
                systemImage: "checkmark.circle.fill"
            )
            .font(.caption)
            .foregroundStyle(.green)
        case .downloadRequired:
            HStack(spacing: 8) {
                Text(L10n.appleTranslationLanguagePacksDownloadRequired)
                    .font(.caption)
                    .foregroundStyle(.orange)
                Button(L10n.appleTranslationLanguagePacksDownload) {
                    requestDownload()
                }
                .controlSize(.small)
            }
        case .downloading:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(L10n.appleTranslationLanguagePacksDownloading)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        case .unsupported:
            Label(
                L10n.appleLanguagePairUnavailable,
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.caption)
            .foregroundStyle(.red)
        case .failed(let message):
            VStack(alignment: .trailing, spacing: 5) {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.trailing)
                Button(L10n.appleTranslationLanguagePacksRetry) {
                    requestDownload()
                }
                .controlSize(.small)
            }
        }
    }

    private func requestDownload() {
        guard
            let sourceIdentifier =
                requirement.source.localeIdentifier,
            let targetIdentifier =
                requirement.target.localeIdentifier
        else {
            state = .unsupported
            return
        }
        downloadRequested = true
        state = .downloading
        let source = Locale.Language(identifier: sourceIdentifier)
        let target = Locale.Language(identifier: targetIdentifier)
        if var existing = configuration,
           existing.source == source,
           existing.target == target {
            existing.invalidate()
            configuration = existing
        } else {
            configuration = TranslationSession.Configuration(
                source: source,
                target: target
            )
        }
    }

    private func refreshStatus() async {
        guard
            let sourceIdentifier =
                requirement.source.localeIdentifier,
            let targetIdentifier =
                requirement.target.localeIdentifier
        else {
            state = .unsupported
            return
        }
        state = .checking
        let availability = LanguageAvailability()
        let status = await availability.status(
            from: Locale.Language(identifier: sourceIdentifier),
            to: Locale.Language(identifier: targetIdentifier)
        )
        guard !Task.isCancelled else { return }
        apply(status)
    }

    private func prepareTranslation(
        using session: TranslationSession
    ) async {
        do {
            try await session.prepareTranslation()
            guard !Task.isCancelled else { return }
            await waitForInstallation()
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed(
                L10n.appleTranslationLanguagePacksDownloadFailed(
                    error.localizedDescription
                )
            )
        }
    }

    private func waitForInstallation() async {
        guard
            let sourceIdentifier =
                requirement.source.localeIdentifier,
            let targetIdentifier =
                requirement.target.localeIdentifier
        else {
            state = .unsupported
            return
        }
        let availability = LanguageAvailability()
        let source = Locale.Language(identifier: sourceIdentifier)
        let target = Locale.Language(identifier: targetIdentifier)

        for _ in 0..<300 {
            guard !Task.isCancelled else { return }
            let status = await availability.status(
                from: source,
                to: target
            )
            switch status {
            case .installed:
                state = .installed
                downloadRequested = false
                return
            case .unsupported:
                state = .unsupported
                downloadRequested = false
                return
            case .supported:
                state = .downloading
            @unknown default:
                state = .failed(
                    L10n.appleTranslationLanguagePacksDownloadFailed(
                        L10n.translationServiceUnavailable
                    )
                )
                downloadRequested = false
                return
            }
            try? await Task.sleep(for: .seconds(1))
        }

        downloadRequested = false
        await refreshStatus()
    }

    private func apply(_ status: LanguageAvailability.Status) {
        switch status {
        case .installed:
            state = .installed
        case .supported:
            state = .downloadRequired
        case .unsupported:
            state = .unsupported
        @unknown default:
            state = .failed(
                L10n.appleTranslationLanguagePacksDownloadFailed(
                    L10n.translationServiceUnavailable
                )
            )
        }
    }
}
#endif
