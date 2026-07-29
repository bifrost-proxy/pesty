import AppKit
import SwiftUI

struct ExplanationBoardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable private var center = ExplanationCenter.shared

    private var palette: ThemePalette { Theme.palette(for: colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.45)
            content
        }
        .frame(
            width: AssistantPopoverLayout.width,
            height: AssistantPopoverLayout.preferredExplanationHeight(
                sourceText: center.sourceText,
                explanation: center.explanationText
            )
        )
        .background(opaqueBoardSurface)
        .accessibilityIdentifier("pesty-explanation-board")
        .onAppear {
            updatePopoverHeight()
            AutomatedUITestProbe.recordExplanationBoard()
        }
        .onChange(of: center.sourceText) { updatePopoverHeight() }
        .onChange(of: center.explanationText) { updatePopoverHeight() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text(L10n.explanation)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.textPrimary.swiftUIColor)
            Spacer()
            Menu {
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
            .help(L10n.moreExplanationOptions)
            Button {
                center.dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.textSecondary.swiftUIColor)
            .help(L10n.closeExplanation)
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
    }

    @ViewBuilder
    private var content: some View {
        switch center.status {
        case .explained:
            result
        case .explaining:
            progress
        case .unavailable(let message):
            unavailable(message)
        case .failed(let message):
            messageState(symbol: "exclamationmark.triangle", text: message, canRetry: true)
        case .idle:
            EmptyView()
        }
    }

    private var result: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(center.sourceText)
                .font(.system(size: 10.5))
                .foregroundStyle(palette.textSecondary.swiftUIColor)
                .lineLimit(1)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.fieldBackground.swiftUIColor, in: RoundedRectangle(cornerRadius: 7))
            HStack {
                Text(L10n.explanation)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Spacer()
                Text(center.providerName)
                    .font(.system(size: 10))
                    .foregroundStyle(palette.textTertiary.swiftUIColor)
            }
            ScrollView {
                ExplanationMarkdownView(
                    markdown: center.explanationText,
                    foregroundColor: palette.textPrimary.swiftUIColor
                )
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            HStack {
                Spacer()
                Button(L10n.copyExplanation) { copyExplanation() }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11, weight: .medium))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { AutomatedUITestProbe.recordExplanationPreview() }
    }

    private var progress: some View {
        VStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(L10n.explaining)
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

    private func unavailable(_ text: String) -> some View {
        messageState(symbol: "cpu", text: text, canRetry: false)
    }

    private func messageState(symbol: String, text: String, canRetry: Bool) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(palette.textTertiary.swiftUIColor)
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(palette.textSecondary.swiftUIColor)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            HStack(spacing: 12) {
                if canRetry {
                    Button(L10n.retryExplanation) { center.retry() }
                }
                Button(L10n.openTranslationSettings) {
                    AppController.shared.showSettings(pane: .translation)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var opaqueBoardSurface: Color {
        Color(
            .sRGB,
            red: palette.cardBody.red,
            green: palette.cardBody.green,
            blue: palette.cardBody.blue,
            opacity: 1
        )
    }

    private func copyExplanation() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(center.explanationText, forType: .string)
    }

    private func updatePopoverHeight() {
        AssistantPopoverController.shared.updatePreferredHeight(
            AssistantPopoverLayout.preferredExplanationHeight(
                sourceText: center.sourceText,
                explanation: center.explanationText
            ),
            for: .explanation
        )
    }
}
