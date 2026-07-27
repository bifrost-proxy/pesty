import SwiftUI

struct PinboardTabs: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable private var store = ClipboardStore.shared
    @Bindable private var settings = Settings.shared

    private var palette: ThemePalette { Theme.palette(for: colorScheme) }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                pill(title: L10n.clipboard,
                     dot: nil,
                     icon: "clock",
                     selected: store.source == .history) {
                    store.source = .history; store.selectFirst()
                }

                ForEach(store.pinboards) { board in
                    pill(title: board.name,
                         dot: board.color,
                         selected: store.source == .pinboard(board.id)) {
                        store.source = .pinboard(board.id); store.selectFirst()
                    }
                    .contextMenu {
                        Button(L10n.rename) { rename(board) }
                        Button(L10n.deletePinboard, role: .destructive) {
                            store.deletePinboard(board.id)
                        }
                    }
                }

                Button(action: addPinboard) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(palette.textSecondary.swiftUIColor)
                        .frame(width: 26, height: 26)
                        .background(palette.fieldBackground.swiftUIColor, in: Circle())
                }
                .buttonStyle(.plain)
                .help(L10n.newPinboard)
            }
        }
        .id(settings.language)
    }

    private func pill(title: String, dot: Color?, icon: String? = nil,
                      selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                }
                if let dot {
                    Circle().fill(dot).frame(width: 7, height: 7)
                }
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(selected
                ? palette.textPrimary.swiftUIColor
                : palette.textSecondary.swiftUIColor)
            .padding(.horizontal, 12)
            .frame(height: 29)
            .background(selected
                ? palette.pillSelected.swiftUIColor
                : palette.pillBackground.swiftUIColor,
                in: Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .animation(.easeOut(duration: 0.15), value: selected)
    }

    private func addPinboard() {
        let board = store.addPinboard(name: L10n.newPinboard)
        store.source = .pinboard(board.id)
    }

    private func rename(_ board: Pinboard) {
        if let name = TextPrompt.run(title: L10n.rename,
                                     message: L10n.enterNewName,
                                     defaultValue: board.name) {
            store.renamePinboard(board.id, to: name)
        }
    }
}

@MainActor
enum TextPrompt {
    static func run(title: String, message: String, defaultValue: String = "") -> String? {
        AppController.shared.suppressAutoHide = true
        defer { AppController.shared.suppressAutoHide = false }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: L10n.ok)
        alert.addButton(withTitle: L10n.cancel)
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = defaultValue
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }
        let v = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }
}
