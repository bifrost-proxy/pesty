import AppKit
import SwiftUI

struct UpdateProgressIndicator: View {
    @Bindable private var updater = UpdateManager.shared

    var body: some View {
        Group {
            if let fraction = updater.progressFraction {
                ProgressView(value: fraction)
            } else {
                ProgressView()
            }
        }
        .progressViewStyle(.linear)
        .accessibilityLabel(updater.statusText)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        guard let percentage = updater.progressPercentage else { return "" }
        return "\(percentage)%"
    }
}

@MainActor
final class UpdateProgressWindowController: NSWindowController {
    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 150),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = L10n.updateProgressTitle
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: UpdateProgressPanelView())
        super.init(window: panel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        window?.title = L10n.updateProgressTitle
        NSApp.activate(ignoringOtherApps: true)
        if window?.isVisible != true {
            window?.center()
        }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct UpdateProgressPanelView: View {
    @Bindable private var updater = UpdateManager.shared
    @Bindable private var settings = Settings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 10) {
                Image(systemName: statusSymbol)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.tint)
                    .symbolEffect(.pulse, isActive: updater.isBusy)
                Text(updater.statusText)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(2)
            }
            UpdateProgressIndicator()
            Text(L10n.updateProgressDescription)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(width: 420, height: 150)
        .accessibilityIdentifier("pesty-update-progress-panel")
        .id(settings.language)
    }

    private var statusSymbol: String {
        switch updater.activity {
        case .checking:
            return "magnifyingglass"
        case .downloading:
            return "arrow.down.circle.fill"
        case .verifying:
            return "checkmark.shield.fill"
        case .preparing:
            return "shippingbox.fill"
        case .installing:
            return "arrow.triangle.2.circlepath"
        case .idle:
            return "arrow.down.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }
}

@MainActor
final class UpdateProgressMenuItemView: NSView {
    init(updater: UpdateManager) {
        super.init(frame: NSRect(x: 0, y: 0, width: 270, height: 48))
        setAccessibilityIdentifier("pesty-update-progress-menu-item")

        let label = NSTextField(labelWithString: updater.statusText)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false

        let progress = NSProgressIndicator()
        progress.style = .bar
        progress.controlSize = .small
        progress.minValue = 0
        progress.maxValue = 1
        progress.translatesAutoresizingMaskIntoConstraints = false
        if let fraction = updater.progressFraction {
            progress.isIndeterminate = false
            progress.doubleValue = fraction
        } else {
            progress.isIndeterminate = true
            progress.startAnimation(nil)
        }

        addSubview(label)
        addSubview(progress)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            progress.leadingAnchor.constraint(equalTo: label.leadingAnchor),
            progress.trailingAnchor.constraint(equalTo: label.trailingAnchor),
            progress.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 5),
            progress.heightAnchor.constraint(equalToConstant: 4),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
