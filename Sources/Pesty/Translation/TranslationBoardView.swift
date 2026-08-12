import AppKit
import SwiftUI

struct TranslationBoardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable private var center = TranslationCenter.shared

    private var palette: ThemePalette { Theme.palette(for: colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.45)
            translationContent
        }
        .frame(
            width: AssistantPopoverLayout.width,
            height: AssistantPopoverLayout.preferredTranslationHeight(
                translation: center.translatedText
            )
        )
        .attachAppleTranslationTask(center)
        .accessibilityIdentifier("pesty-translation-board")
        .onAppear {
            updatePopoverHeight()
            AutomatedUITestProbe.recordTranslationBoard()
        }
        .onChange(of: center.translatedText) { updatePopoverHeight() }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "character.bubble")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.10), in: Circle())
            languageMenu(
                selected: center.sourceLanguage,
                title: L10n.sourceLanguage,
                acceptsAutomatic: true,
                action: center.setSourceLanguage
            )
            Image(systemName: "arrow.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.textTertiary.swiftUIColor)
            languageMenu(
                selected: center.targetLanguage,
                title: L10n.targetLanguage,
                acceptsAutomatic: false,
                action: center.setTargetLanguage
            )
            Button {
                center.swapLanguages()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                    Text("T")
                        .font(.system(size: 9, weight: .semibold))
                        .monospaced()
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(
                            palette.fieldBackground.swiftUIColor,
                            in: RoundedRectangle(cornerRadius: 4)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(
                                    palette.textTertiary.swiftUIColor
                                        .opacity(0.35),
                                    lineWidth: 0.5
                                )
                        }
                }
                .frame(height: 28)
                .padding(.horizontal, 4)
            }
            .buttonStyle(.plain)
            .foregroundStyle(
                center.canSwapLanguages
                    ? palette.textSecondary.swiftUIColor
                    : palette.textTertiary.swiftUIColor
            )
            .disabled(!center.canSwapLanguages)
            .help(L10n.swapTranslationLanguagesShortcut)
            .accessibilityLabel(L10n.swapTranslationLanguages)
            .accessibilityIdentifier("pesty-translation-language-swap")
            Spacer(minLength: 4)
            if !center.providerName.isEmpty {
                Text(center.providerName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.textTertiary.swiftUIColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: 76, alignment: .trailing)
                    .help(center.providerName)
                    .accessibilityIdentifier(
                        "pesty-translation-header-provider"
                    )
            }
            moreMenu
            Button {
                center.dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.textSecondary.swiftUIColor)
            .help(L10n.closeTranslation)
            .accessibilityIdentifier("pesty-translation-close")
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
    }

    private func languageMenu(
        selected: TranslationLanguage,
        title: String,
        acceptsAutomatic: Bool,
        action: @escaping (TranslationLanguage) -> Void
    ) -> some View {
        Menu {
            ForEach(TranslationLanguage.allCases) { language in
                if acceptsAutomatic || language != .automatic {
                    Button {
                        action(language)
                    } label: {
                        HStack {
                            Text(language.displayName)
                            if language == selected { Image(systemName: "checkmark") }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selected.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textPrimary.swiftUIColor)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(palette.textTertiary.swiftUIColor)
            }
            .frame(minWidth: 66, maxWidth: 86, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(palette.fieldBackground.swiftUIColor, in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .accessibilityLabel(title)
    }

    private var moreMenu: some View {
        Menu {
            Menu(L10n.translationService) {
                ForEach(TranslationService.allCases) { service in
                    Button {
                        center.setService(service)
                    } label: {
                        HStack {
                            Text(service.displayName)
                            if Settings.shared.translationService == service {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            Divider()
            Button(L10n.translationSettings) {
                AppController.shared.showSettings(pane: .translation)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(palette.textSecondary.swiftUIColor)
                .frame(width: 28, height: 28)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help(L10n.moreTranslationOptions)
        .accessibilityIdentifier("pesty-translation-more")
    }

    @ViewBuilder
    private var translationContent: some View {
        switch center.status {
        case .translated:
            translationResult
        case .alreadyInTarget(let message):
            alreadyInTargetState(message: message)
        case .checkingService:
            progressState(label: L10n.checkingTranslationService)
        case .translating:
            progressState(label: L10n.translating)
        case .unavailable(let message):
            unavailableState(message: message)
        case .failed(let message):
            messageState(
                symbol: "exclamationmark.triangle",
                message: message,
                showsSettings: false
            )
        case .idle:
            EmptyView()
        }
    }

    private func alreadyInTargetState(message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Color.accentColor)
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(palette.textSecondary.swiftUIColor)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var translationResult: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                ExplanationMarkdownView(
                    markdown: center.translatedText,
                    foregroundColor: palette.textPrimary.swiftUIColor,
                    fontSize: 15,
                    preservesLineBreaks: true
                )
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            HStack {
                Spacer()
                Button(L10n.copyTranslation) { center.copyResult() }
                    .buttonStyle(.borderless)
                    .font(.system(size: 12, weight: .medium))
                    .accessibilityIdentifier("pesty-translation-copy")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { AutomatedUITestProbe.recordTranslationPreview() }
    }

    private func progressState(label: String) -> some View {
        VStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(palette.textSecondary.swiftUIColor)
            if !center.providerName.isEmpty {
                Text(center.providerName)
                    .font(.caption)
                    .foregroundStyle(palette.textTertiary.swiftUIColor)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func unavailableState(message: String) -> some View {
        if center.sourceText.isEmpty {
            VStack(spacing: 14) {
                Image(systemName: "text.badge.xmark")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(
                        palette.textSecondary.swiftUIColor
                    )
                Text(message)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(
                        palette.textSecondary.swiftUIColor
                    )
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 390)
                #if !MAS
                if message == L10n.globalTranslationAccessibilityRequired {
                    Button(L10n.openAccessibilitySettings) {
                        PasteService.openAccessibilitySettings(
                            forceGuide: true
                        )
                    }
                    .font(.system(size: 12, weight: .medium))
                }
                #endif
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Label(L10n.translationServiceUnavailable, systemImage: "exclamationmark.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textPrimary.swiftUIColor)
                if !center.appleTranslationSupported {
                    availabilityRow(
                        title: "Apple Translate",
                        detail: L10n.appleTranslationRequiresMacOS15,
                        symbol: "macbook"
                    )
                }
                Text(message)
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary.swiftUIColor)
                    .lineLimit(2)
                HStack {
                    Spacer()
                    Button(L10n.openTranslationSettings) {
                        AppController.shared.showSettings(pane: .translation)
                    }
                    .font(.system(size: 12, weight: .medium))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private func availabilityRow(title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.textTertiary.swiftUIColor)
                .frame(width: 16)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 104, alignment: .leading)
            Text(detail)
                .font(.caption)
                .foregroundStyle(palette.textSecondary.swiftUIColor)
                .lineLimit(1)
        }
    }

    private func messageState(
        symbol: String,
        message: String,
        showsSettings: Bool
    ) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(palette.textTertiary.swiftUIColor)
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(palette.textSecondary.swiftUIColor)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            HStack(spacing: 12) {
                if showsSettings {
                    Button(L10n.openTranslationSettings) {
                        AppController.shared.showSettings(pane: .translation)
                    }
                }
                if !showsSettings {
                    Button(L10n.retryTranslation) { center.retry() }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func updatePopoverHeight() {
        AssistantPopoverController.shared.updatePreferredHeight(
            AssistantPopoverLayout.preferredTranslationHeight(
                translation: center.translatedText
            ),
            for: .translation
        )
    }
}
