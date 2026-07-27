import SwiftUI

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
        .onTapGesture(count: 2) { AppController.shared.pasteItem(item) }
        .onTapGesture { store.selectedID = item.id }
        .contextMenu { menu }
        .id(settings.language)
        .onAppear { AutomatedUITestProbe.record(item) }
    }

    private var header: some View {
        ZStack {
            headerColor
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
        .background(palette.cardBody.swiftUIColor)
    }

    @ViewBuilder
    private var content: some View {
        switch item.type {
        case .image:
            if let img = store.loadImage(for: item) {
                Image(nsImage: img)
                    .resizable().interpolation(.medium).scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else { placeholder("photo") }
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
            VStack(spacing: 10) {
                Spacer(minLength: 0)
                Image(systemName: "safari").font(.system(size: 34, weight: .light))
                    .foregroundStyle(palette.textTertiary.swiftUIColor)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
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
            return (item.text ?? "").replacingOccurrences(of: "https://", with: "")
                                    .replacingOccurrences(of: "http://", with: "")
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
}
