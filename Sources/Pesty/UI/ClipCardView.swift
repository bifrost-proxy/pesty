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

    @State private var hovering = false
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
        .shadow(color: .black.opacity(selected ? 0.35 : 0.18),
                radius: selected ? 12 : 5, y: selected ? 5 : 2)
        .scaleEffect(hovering && !selected ? 1.015 : 1.0)
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: selected)
        .animation(.easeOut(duration: 0.14), value: hovering)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu { menu }
        .id(settings.language)
        .onAppear { AutomatedUITestProbe.record(item) }
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
                Text(item.displayTitle).font(.system(size: 12))
                    .foregroundStyle(palette.textSecondary.swiftUIColor).lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .link:
            VStack(alignment: .leading, spacing: 10) {
                Label {
                    Text(item.displayTitle)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: "link")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(headerColor)

                Text(item.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(palette.textPrimary.swiftUIColor.opacity(0.9))
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
            }
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        default:
            Text(item.text ?? "")
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
                Text(item.displayTitle)
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
            return L10n.characterCount(item.charCount)
        case .link:
            return L10n.characterCount(item.charCount)
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
