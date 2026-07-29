import AppKit
import SwiftUI

enum SearchFieldLayout {
    static let minimumWidth: CGFloat = 72
    static let maximumWidth: CGFloat = 420
    static let horizontalContentPadding: CGFloat = 18

    static func requiredWidth(for text: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        let measuredWidth = (text as NSString).size(
            withAttributes: [.font: font]
        ).width
        return ceil(measuredWidth) + horizontalContentPadding
    }

    static func width(for text: String) -> CGFloat {
        min(maximumWidth, max(minimumWidth, requiredWidth(for: text)))
    }
}

@MainActor
final class SearchInputBridge {
    static let shared = SearchInputBridge()

    private weak var field: NSTextField?
    private var pendingEvents: [NSEvent] = []
    private var focusRequested = false

    func requestActivation(replaying event: NSEvent? = nil) {
        if let event {
            pendingEvents.append(event)
        }
        focusRequested = true
        ClipboardStore.shared.isSearchFieldActive = true
        focusIfPossible()
    }

    func connect(_ field: NSTextField) {
        self.field = field
        focusIfPossible()
    }

    func disconnect(_ field: NSTextField) {
        if self.field === field {
            self.field = nil
        }
    }

    private func focusIfPossible(attempt: Int = 0) {
        guard focusRequested else { return }
        guard let field, let window = field.window else {
            guard attempt < 50 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
                self?.focusIfPossible(attempt: attempt + 1)
            }
            return
        }

        focusRequested = false
        window.makeFirstResponder(field)
        let events = pendingEvents
        pendingEvents.removeAll(keepingCapacity: true)
        guard !events.isEmpty else { return }
        DispatchQueue.main.async {
            for event in events {
                NSApp.sendEvent(event)
            }
        }
    }
}

struct AdaptiveSearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let textColor: NSColor

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13, weight: .medium)
        field.placeholderString = placeholder
        field.textColor = textColor
        field.usesSingleLineMode = true
        field.lineBreakMode = .byClipping
        field.cell?.isScrollable = true
        field.setAccessibilityIdentifier("pesty-search-field")
        SearchInputBridge.shared.connect(field)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        field.placeholderString = placeholder
        field.textColor = textColor
        if (field.currentEditor() as? NSTextView)?.hasMarkedText() != true,
           field.stringValue != text {
            field.stringValue = text
        }
    }

    static func dismantleNSView(_ field: NSTextField, coordinator: Coordinator) {
        SearchInputBridge.shared.disconnect(field)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: AdaptiveSearchField

        init(parent: AdaptiveSearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:))
                    || commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:))
            else {
                return false
            }
            AppController.shared.pasteSelected()
            return true
        }
    }
}

struct BarView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable private var store = ClipboardStore.shared
    @Bindable private var settings = Settings.shared
    @Bindable private var updater = UpdateManager.shared
    @Bindable private var translator = TranslationCenter.shared
    @State private var usageTipsVisible = false
    @State private var usageTipsPinned = false
    @State private var usageTipsHovering = false

    private var palette: ThemePalette { Theme.palette(for: colorScheme) }

    var body: some View {
        ZStack {
            VisualEffectView(
                material: .sidebar,
                blending: .behindWindow,
                isEmphasized: true
            )
            palette.panelTint.swiftUIColor
            LinearGradient(
                colors: [
                    Color.white.opacity(colorScheme == .dark ? 0.06 : 0.13),
                    Color.white.opacity(colorScheme == .dark ? 0.018 : 0.035),
                    Color.clear,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .overlay(alignment: .top) {
            VStack(spacing: 0) {
                topBar
                strip
            }
        }
        .clipShape(RoundedCorners(radius: Theme.cornerRadius, corners: [.topLeft, .topRight]))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(colorScheme == .dark ? 0.18 : 0.55))
                .frame(height: 1)
        }
        .attachAppleTranslationTask(translator)
        .ignoresSafeArea()
        .id(settings.language)
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            syncButton
            searchIndicator
            PinboardTabs()
                .layoutPriority(1)
            Spacer(minLength: 8)
            if updater.showInClipboardBar, let release = updater.availableRelease {
                updateButton(release)
            }
            HStack(spacing: 0) {
                usageTipsButton
                moreMenu
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 56)
    }

    private var usageTipsButton: some View {
        Button {
            usageTipsPinned.toggle()
            usageTipsVisible = usageTipsPinned
        } label: {
            Image(systemName: "lightbulb")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.textSecondary.swiftUIColor)
                .frame(width: 26, height: 26)
                .background(
                    palette.textPrimary.swiftUIColor.opacity(usageTipsVisible ? 0.08 : 0.025),
                    in: Circle()
                )
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .accessibilityLabel(L10n.usageTips)
        .accessibilityIdentifier("pesty-usage-tips")
        .help(L10n.usageTips)
        .onHover { hovering in
            usageTipsHovering = hovering
            if hovering {
                usageTipsVisible = true
            } else if !usageTipsPinned {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    guard !usageTipsPinned, !usageTipsHovering else { return }
                    usageTipsVisible = false
                }
            }
        }
        .onChange(of: usageTipsVisible) { _, visible in
            if !visible {
                usageTipsPinned = false
            }
        }
        .popover(isPresented: $usageTipsVisible, arrowEdge: .bottom) {
            UsageTipsPopover(
                translationShortcut: settings.translationHotkeyDisplay,
                explanationShortcut: settings.explanationHotkeyDisplay
            )
        }
    }

    private var syncButton: some View {
        Button {
            AppController.shared.toggleICloudSync()
        } label: {
            Image(systemName: settings.iCloudSync ? "checkmark.icloud.fill" : "arrow.triangle.2.circlepath")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(settings.iCloudSync
                    ? palette.selection.swiftUIColor
                    : palette.textSecondary.swiftUIColor)
        }
        .buttonStyle(.plain)
        .help(settings.iCloudSync ? L10n.iCloudSyncOn : L10n.turnOnICloudSync)
    }

    private var searchIndicator: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.textSecondary.swiftUIColor)
            if store.isSearchFieldActive || !store.searchText.isEmpty {
                AdaptiveSearchField(
                    text: $store.searchText,
                    placeholder: L10n.searchClipboard,
                    textColor: palette.textPrimary.nsColor
                )
                    .frame(width: searchFieldWidth)
            } else {
                Button {
                    SearchInputBridge.shared.requestActivation()
                } label: {
                    Text(L10n.searchClipboard)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(palette.textTertiary.swiftUIColor)
                        .frame(width: searchFieldWidth, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pesty-search-field-placeholder")
            }
            if !store.searchText.isEmpty {
                Button {
                    store.searchText = ""
                    store.selectFirst()
                    SearchInputBridge.shared.requestActivation()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.textTertiary.swiftUIColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(palette.fieldBackground.swiftUIColor, in: Capsule())
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(2)
        .onChange(of: store.searchText) {
            store.selectFirst()
        }
    }

    private var searchFieldWidth: CGFloat {
        let displayText = store.searchText.isEmpty
            ? L10n.searchClipboard
            : store.searchText
        return SearchFieldLayout.width(for: displayText)
    }

    private var moreMenu: some View {
        Menu {
            Button(L10n.checkForUpdates) {
                AppController.shared.checkForUpdatesManually()
            }
            .disabled(updater.activity == .checking || updater.isInstalling)
            Divider()
            Button(L10n.settings) { AppController.shared.showSettings() }
            Button(L10n.clearHistory) {
                AppController.shared.requestClearHistoryConfirmation()
            }
            Divider()
            Button(L10n.aboutPesty) { AppController.shared.showAbout() }
            Button(L10n.quitPesty) { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.textSecondary.swiftUIColor)
                .frame(width: 30, height: 30)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 34)
        .fixedSize()
    }

    private func updateButton(_ release: AppRelease) -> some View {
        Button {
            updater.installAvailableUpdate()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: updater.isInstalling
                      ? "arrow.triangle.2.circlepath"
                      : "arrow.down.circle.fill")
                Text(updateButtonTitle(release))
                    .lineLimit(1)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(palette.selection.swiftUIColor, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(updater.isInstalling)
        .help(L10n.updateAvailableMessage(release.version))
        .accessibilityIdentifier("pesty-update-button")
    }

    private func updateButtonTitle(_ release: AppRelease) -> String {
        switch updater.activity {
        case .downloading:
            return L10n.downloadingUpdate(release.version)
        case .installing:
            return L10n.installingUpdate(release.version)
        default:
            return L10n.updateToVersion(release.version)
        }
    }

    private var strip: some View {
        let visibleItems = store.visibleItems
        return VirtualizedClipStrip(
            items: visibleItems,
            contentRevision: store.stripContentRevision,
            selectedID: store.selectedID,
            cardHeight: cardHeight,
            language: settings.language
        )
        .overlay { if visibleItems.isEmpty { emptyState } }
        .frame(maxHeight: .infinity)
    }

    private var cardHeight: CGFloat {
        max(160, CGFloat(settings.barHeight) - 82)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: store.searchText.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(palette.textTertiary.swiftUIColor)
            Text(store.searchText.isEmpty
                 ? L10n.nothingCopied
                 : L10n.noMatches(store.searchText))
                .font(.system(size: 13))
                .foregroundStyle(palette.textSecondary.swiftUIColor)
        }
    }
}

private struct UsageTipsPopover: View {
    let translationShortcut: String
    let explanationShortcut: String

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label(L10n.usageTips, systemImage: "lightbulb.fill")
                .font(.system(size: 15, weight: .semibold))

            UsageTipRow(
                icon: "command",
                text: L10n.usageTipTranslation(translationShortcut, explanationShortcut)
            )
            UsageTipRow(
                icon: "pin",
                text: L10n.usageTipPinboard
            )
            UsageTipRow(
                icon: "cursorarrow.click.2",
                text: L10n.usageTipQuickPaste
            )
            UsageTipRow(
                icon: "magnifyingglass",
                text: L10n.usageTipSearch
            )
        }
        .padding(16)
        .frame(width: 350, alignment: .leading)
        .accessibilityIdentifier("pesty-usage-tips-popover")
    }
}

private struct UsageTipRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 16, height: 17)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 12.5))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct RoundedCorners: Shape {
    var radius: CGFloat
    var corners: RectCorner

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let tl = corners.contains(.topLeft) ? radius : 0
        let tr = corners.contains(.topRight) ? radius : 0
        let bl = corners.contains(.bottomLeft) ? radius : 0
        let br = corners.contains(.bottomRight) ? radius : 0
        p.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        p.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr), radius: tr,
                 startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        p.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br), radius: br,
                 startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl), radius: bl,
                 startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        p.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl), radius: tl,
                 startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}

struct RectCorner: OptionSet {
    let rawValue: Int
    static let topLeft = RectCorner(rawValue: 1 << 0)
    static let topRight = RectCorner(rawValue: 1 << 1)
    static let bottomLeft = RectCorner(rawValue: 1 << 2)
    static let bottomRight = RectCorner(rawValue: 1 << 3)
}
