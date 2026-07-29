import Carbon.HIToolbox
import SwiftUI

@MainActor
struct ContextMenuShortcut {
    let keyEquivalent: KeyEquivalent
    let modifiers: SwiftUI.EventModifiers
    let display: String

    init?(keyCode: Int, carbonModifiers: Int) {
        let keyName = HotKeyCenter.keyName(for: keyCode)
        switch keyName {
        case "Space":
            keyEquivalent = .space
        case "↩":
            keyEquivalent = .return
        case "⎋":
            keyEquivalent = .escape
        default:
            guard keyName.count == 1, let character = keyName.lowercased().first else {
                return nil
            }
            keyEquivalent = KeyEquivalent(character)
        }
        display = HotKeyCenter.describe(keyCode: keyCode, modifiers: carbonModifiers)

        var eventModifiers: SwiftUI.EventModifiers = []
        if carbonModifiers & controlKey != 0 { eventModifiers.insert(.control) }
        if carbonModifiers & optionKey != 0 { eventModifiers.insert(.option) }
        if carbonModifiers & shiftKey != 0 { eventModifiers.insert(.shift) }
        if carbonModifiers & cmdKey != 0 { eventModifiers.insert(.command) }
        modifiers = eventModifiers
    }
}

struct ClipCardView: View {
    @Environment(\.colorScheme) private var colorScheme
    let item: ClipItem
    let index: Int
    let selected: Bool
    let previewText: String
    let characterCount: Int
    let displayTitle: String

    @State private var hovering = false
    @Bindable private var translationCenter = TranslationCenter.shared
    @Bindable private var explanationCenter = ExplanationCenter.shared
    private var store: ClipboardStore { ClipboardStore.shared }
    @Bindable private var settings = Settings.shared
    private var headerColor: Color { SourceColor.color(for: item.sourceBundleID) }
    private var palette: ThemePalette { Theme.palette(for: colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            header
            body_
        }
        .frame(width: Theme.cardWidth)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                .strokeBorder(selected
                    ? palette.selection.swiftUIColor
                    : palette.cardBorder.swiftUIColor,
                              lineWidth: selected ? 2.5 : 1)
        )
        .overlay {
            if let processingLabel {
                AssistantProcessingOverlay(label: processingLabel, itemID: item.id)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .allowsHitTesting(false)
            }
        }
        .shadow(color: .black.opacity(selected ? 0.35 : 0.18),
                radius: selected ? 12 : 5, y: selected ? 5 : 2)
        .scaleEffect(hovering && !selected ? 1.015 : 1.0)
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: selected)
        .animation(.easeOut(duration: 0.14), value: hovering)
        .animation(.easeOut(duration: 0.18), value: processingLabel)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu { menu }
        .id(settings.language)
        .onChange(of: item.id, initial: true) {
            hovering = false
            AutomatedUITestProbe.record(item)
        }
    }

    private var processingLabel: String? {
        if translationCenter.itemID == item.id,
           translationCenter.status == .translating {
            return L10n.translating
        }
        if explanationCenter.itemID == item.id,
           explanationCenter.status == .explaining {
            return L10n.explaining
        }
        return nil
    }

    private var header: some View {
        ZStack {
            headerColor
            LinearGradient(
                colors: [
                    Color.white.opacity(0.16),
                    Color.clear,
                    Color.black.opacity(0.055),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.type.label)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.headerText)
                    Text(item.createdAt.clipRelativeLong)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.headerSubText)
                }
                .lineLimit(1)
                Spacer(minLength: 4)
                appIconTile
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
        .frame(height: Theme.headerHeight)
    }

    private var appIconTile: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(Color.black.opacity(0.22))
            .frame(width: 38, height: 38)
            .overlay(
                Image(nsImage: AppIconProvider.icon(forBundleID: item.sourceBundleID))
                    .resizable()
                    .frame(width: 28, height: 28)
            )
    }

    private var body_: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            footer
        }
        .padding(.horizontal, 13)
        .padding(.top, 11)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                palette.cardBody.swiftUIColor
                LinearGradient(
                    colors: [
                        Color.white.opacity(colorScheme == .dark ? 0.035 : 0.08),
                        Color.clear,
                    ],
                    startPoint: .top,
                    endPoint: .center
                )
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch item.type {
        case .image:
            ClipThumbnailView(item: item)
        case .color:
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color(hex: item.colorHex ?? "#000") ?? .black)
                Text(item.colorHex ?? "")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white).shadow(radius: 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .file:
            VStack(spacing: 9) {
                Image(systemName: "doc.fill").font(.system(size: 32))
                    .foregroundStyle(headerColor)
                Text(displayTitle).font(.system(size: 12))
                    .foregroundStyle(palette.textSecondary.swiftUIColor).lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .link:
            VStack(alignment: .leading, spacing: 10) {
                Label {
                    Text(displayTitle)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: "link")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(headerColor)

                Text(previewText)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(palette.textPrimary.swiftUIColor.opacity(0.9))
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
            }
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        default:
            Text(previewText)
                .font(.system(size: 12.5))
                .foregroundStyle(palette.textPrimary.swiftUIColor.opacity(0.9))
                .lineLimit(10)
                .multilineTextAlignment(.leading)
        }
    }

    private func placeholder(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 30))
            .foregroundStyle(palette.textTertiary.swiftUIColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 3) {
            if item.type == .link {
                Text(displayTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textPrimary.swiftUIColor).lineLimit(1)
            }
            HStack(spacing: 6) {
                Text(metaLeft)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary.swiftUIColor)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if index < 9 {
                    HStack(spacing: 3) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 9, weight: .semibold))
                        Text("\(index + 1)")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(palette.textTertiary.swiftUIColor)
                }
            }
        }
        .padding(.top, 8)
    }

    private var metaLeft: String {
        switch item.type {
        case .text, .richText:
            return L10n.characterCount(characterCount)
        case .link:
            return L10n.characterCount(characterCount)
        case .file:
            return L10n.fileCount(item.fileURLs.count)
        case .image:
            return L10n.image
        case .color:
            return item.colorHex ?? L10n.color
        }
    }

    @ViewBuilder
    private var menu: some View {
        Button(L10n.paste) { AppController.shared.pasteItem(item) }
        Button(L10n.copy) { AppController.shared.copyItem(item) }
        if let text = item.text?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            assistantMenuButton(
                L10n.translate,
                keyCode: settings.translationHotkeyKeyCode,
                modifiers: settings.translationHotkeyModifiers
            ) {
                AppController.shared.showTranslationBoard(for: item)
            }
            assistantMenuButton(
                L10n.explanation,
                keyCode: settings.explanationHotkeyKeyCode,
                modifiers: settings.explanationHotkeyModifiers
            ) {
                AppController.shared.showExplanationBoard(for: item)
            }
        }
        Divider()
        if !store.pinboards.isEmpty {
            Menu(L10n.saveToPinboard) {
                ForEach(store.pinboards) { b in
                    Button(b.name) { store.saveToPinboard(item, boardID: b.id) }
                }
            }
        }
        Button(L10n.saveToNewPinboard) {
            if let name = TextPrompt.run(title: L10n.newPinboard, message: L10n.name) {
                let b = store.addPinboard(name: name)
                store.saveToPinboard(item, boardID: b.id)
            }
        }
        Button(L10n.editTitle) {
            if let t = TextPrompt.run(title: L10n.text("Edit Title", "编辑标题"), message: L10n.cardTitle,
                                      defaultValue: item.customTitle ?? "") {
                store.setTitle(t, for: item)
            }
        }
        Divider()
        Button(L10n.delete, role: .destructive) { store.delete(item) }
    }

    @ViewBuilder
    private func assistantMenuButton(
        _ title: String,
        keyCode: Int,
        modifiers: Int,
        action: @escaping () -> Void
    ) -> some View {
        if let shortcut = ContextMenuShortcut(
            keyCode: keyCode,
            carbonModifiers: modifiers
        ) {
            Button(title, action: action)
                .keyboardShortcut(shortcut.keyEquivalent, modifiers: shortcut.modifiers)
        } else {
            Button(title, action: action)
        }
    }
}

private struct AssistantProcessingOverlay: View {
    @Environment(\.colorScheme) private var colorScheme
    let label: String
    let itemID: UUID

    @State private var isPulsing = false

    var body: some View {
        ZStack {
            RoundedRectangle(
                cornerRadius: Theme.cardCorner,
                style: .continuous
            )
            .fill(Color.accentColor.opacity(isPulsing ? 0.10 : 0.04))
            .overlay {
                RoundedRectangle(
                    cornerRadius: Theme.cardCorner,
                    style: .continuous
                )
                .strokeBorder(
                    Color.accentColor.opacity(isPulsing ? 0.95 : 0.45),
                    lineWidth: isPulsing ? 3 : 2
                )
            }

            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                (colorScheme == .dark ? Color.black : Color.white)
                    .opacity(0.90),
                in: Capsule()
            )
            .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pesty-card-assistant-processing")
        .onAppear {
            AutomatedUITestProbe.recordAssistantProcessing(
                itemID: itemID,
                visible: true
            )
            withAnimation(
                .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
            ) {
                isPulsing = true
            }
        }
        .onDisappear {
            AutomatedUITestProbe.recordAssistantProcessing(
                itemID: itemID,
                visible: false
            )
        }
    }
}

enum ClipCardPreview {
    static let maximumCharacterCount = 4_096

    static func text(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "" }
        guard let end = value.index(
            value.startIndex,
            offsetBy: maximumCharacterCount,
            limitedBy: value.endIndex
        ), end != value.endIndex else {
            return value
        }
        return String(value[..<end]) + "…"
    }
}
