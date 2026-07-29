import AppKit
import SwiftUI

enum SettingsWindowLayout {
    static let width: CGFloat = 680
    static let initialHeight: CGFloat = 780
    static let minimumHeight: CGFloat = 560
}

struct SettingsView: View {
    @Bindable var state: SettingsWindowState
    @Bindable private var settings = Settings.shared

    var body: some View {
        ZStack {
            VisualEffectView(
                material: .underWindowBackground,
                blending: .behindWindow
            )
            .ignoresSafeArea()

            Color.accentColor.opacity(0.025)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                SettingsTopBar(selection: $state.selectedPane)
                Divider().opacity(0.45)

                Group {
                    switch state.selectedPane {
                    case .general:
                        GeneralSettings(
                            onboardingReason:
                                state.accessibilityOnboardingReason
                        )
                    case .translation:
                        TranslationSettingsView()
                    case .about:
                        AboutView()
                    }
                }
                .transition(.opacity)
            }
        }
        .frame(width: SettingsWindowLayout.width)
        .frame(
            minHeight: SettingsWindowLayout.minimumHeight,
            maxHeight: .infinity
        )
        .id(settings.language)
    }
}

private struct SettingsTopBar: View {
    @Binding var selection: SettingsPane

    var body: some View {
        Picker(L10n.settingsWindowTitle, selection: $selection) {
            Text(L10n.general).tag(SettingsPane.general)
            Text(L10n.translationAndExplanation).tag(SettingsPane.translation)
            Text(L10n.about).tag(SettingsPane.about)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 340)
        .accessibilityLabel(L10n.settingsWindowTitle)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
    }
}

private struct GeneralSettings: View {
    @Bindable private var settings = Settings.shared
    @Bindable private var store = ClipboardStore.shared
    let onboardingReason: AccessibilityOnboardingReason?

    @State private var retentionSliderPosition =
        Settings.shared.historyRetentionSliderPosition

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                #if !MAS
                if let onboardingReason {
                    AccessibilityAccessCard(reason: onboardingReason)
                }
                #endif

                SettingsSection(
                    title: L10n.activation,
                    systemImage: "command"
                ) {
                    SettingsRow(title: L10n.showPesty) {
                        HotkeyRecorderView()
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        SettingsRow(
                            title: L10n.historyLimit,
                            value: retentionDisplayValue
                        )
                        Slider(
                            value: $retentionSliderPosition,
                            in: 0...HistoryRetentionPolicy
                                .unlimitedSliderPosition,
                            step: 1,
                            onEditingChanged: { editing in
                                guard !editing else { return }
                                settings.setHistoryRetentionSliderPosition(
                                    retentionSliderPosition
                                )
                            }
                        )
                        .labelsHidden()
                        HStack {
                            Text("100")
                            Spacer()
                            Text("1,000")
                            Spacer()
                            Text("10,000")
                            Text("∞")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        Text(L10n.historyLimitDelayDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    SettingsRow(
                        title: L10n.storageUsed,
                        value: storageDisplayValue
                    )
                }

                SettingsSection(
                    title: L10n.behavior,
                    systemImage: "slider.horizontal.3"
                ) {
                    #if !MAS
                    SettingsToggleRow(
                        title: L10n.pasteDirectly,
                        isOn: $settings.pasteDirectly
                    )
                    Divider()
                    #endif
                    SettingsToggleRow(
                        title: L10n.ignorePasswords,
                        isOn: $settings.ignoreConcealed
                    )
                    Divider()
                    SettingsToggleRow(
                        title: L10n.playSound,
                        isOn: $settings.playSound
                    )
                    Divider()
                    SettingsToggleRow(
                        title: L10n.launchAtLogin,
                        isOn: $settings.launchAtLogin
                    )
                    Divider()
                    SettingsToggleRow(
                        title: L10n.showMenuBarIcon,
                        subtitle: L10n.showMenuBarIconDescription,
                        isOn: $settings.showMenuBarIcon
                    )
                    Divider()
                    VStack(alignment: .leading, spacing: 10) {
                        SettingsRow(
                            title: L10n.barHeight,
                            value: "\(Int(settings.barHeight)) \(L10n.px)"
                        )
                        Slider(
                            value: $settings.barHeight,
                            in: 280...720,
                            step: 10
                        )
                    }
                    #if MAS
                    Text(L10n.selectClip)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    #endif
                }

                SettingsSection(
                    title: L10n.sync,
                    systemImage: "icloud"
                ) {
                    SettingsToggleRow(
                        title: L10n.syncClipboard,
                        subtitle: ClipboardStore.shared.iCloudAvailable
                            ? L10n.syncAvailable
                            : L10n.syncUnavailable,
                        isOn: Binding(
                            get: { settings.iCloudSync },
                            set: { _ in
                                AppController.shared.toggleICloudSync()
                            }
                        )
                    )
                }

                #if !MAS
                if onboardingReason == nil {
                    SettingsSection(
                        title: L10n.permissions,
                        systemImage: "hand.raised"
                    ) {
                        AccessibilityAccessCard(reason: nil)
                    }
                }
                #endif

                SettingsSection(
                    title: L10n.languageLabel,
                    systemImage: "globe"
                ) {
                    SettingsRow(
                        title: L10n.languageLabel,
                        subtitle: L10n.languageDescription
                    ) {
                        Picker(
                            L10n.languageLabel,
                            selection: $settings.language
                        ) {
                            ForEach(AppLanguage.allCases) { language in
                                Text(language.displayName).tag(language)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 140)
                    }
                }

                SettingsSection(
                    title: L10n.data,
                    systemImage: "externaldrive"
                ) {
                    HStack {
                        Text(L10n.clearClipboardHistory)
                        Spacer()
                        Button(
                            L10n.clearHistory,
                            role: .destructive
                        ) {
                            AppController.shared
                                .requestClearHistoryConfirmation()
                        }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 650)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            retentionSliderPosition =
                settings.historyRetentionSliderPosition
            store.refreshStorageUsage()
        }
    }

    private var retentionDisplayValue: String {
        guard let limit = HistoryRetentionPolicy.selection(
            at: retentionSliderPosition
        ) else {
            return L10n.unlimited
        }
        return L10n.items(limit)
    }

    private var storageDisplayValue: String {
        guard store.storageUsageBytes > 0 else { return "0 KB" }
        return ByteCountFormatter.string(
            fromByteCount: store.storageUsageBytes,
            countStyle: .file
        )
    }
}

#if !MAS
private struct AccessibilityAccessCard: View {
    let reason: AccessibilityOnboardingReason?

    @State private var accessibilityGranted = AXIsProcessTrusted()
    @State private var requestedGrant = false
    @State private var isRepairingAccessibility = false
    @State private var accessibilityRepairFailure: String?

    private let poll = Timer.publish(
        every: 1,
        on: .main,
        in: .common
    ).autoconnect()

    var body: some View {
        if let reason {
            onboardingContent(reason: reason)
                .padding(24)
                .settingsCardSurface(emphasized: true)
                .onAppear { refreshAuthorization() }
                .onReceive(poll) { _ in refreshAuthorization() }
        } else {
            compactContent
                .onAppear { refreshAuthorization() }
                .onReceive(poll) { _ in refreshAuthorization() }
        }
    }

    private func onboardingContent(
        reason: AccessibilityOnboardingReason
    ) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 16) {
                Image(
                    systemName: accessibilityGranted
                        ? "checkmark.shield.fill"
                        : "hand.raised.fill"
                )
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(
                    accessibilityGranted ? .green : Color.accentColor
                )
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.accessibilitySetupTitle)
                        .font(.title2.weight(.semibold))
                    Text(onboardingDescription(for: reason))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                OnboardingStep(
                    number: 1,
                    title: L10n.accessibilityStepOpen,
                    isComplete: requestedGrant || accessibilityGranted
                )
                OnboardingStep(
                    number: 2,
                    title: L10n.accessibilityStepEnable,
                    isComplete: accessibilityGranted
                )
                OnboardingStep(
                    number: 3,
                    title: L10n.accessibilityStepRestart,
                    isComplete: false
                )
            }

            HStack(spacing: 12) {
                statusLabel
                Spacer()
                if accessibilityGranted {
                    Button(L10n.restartPesty) {
                        restartAfterAuthorization()
                    }
                    .settingsPrimaryButton()
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button {
                        beginAuthorization()
                    } label: {
                        if isRepairingAccessibility {
                            ProgressView()
                                .controlSize(.small)
                                .frame(minWidth: 150)
                        } else {
                            Text(
                                requestedGrant
                                    ? L10n.openAccessibilitySettingsAgain
                                    : L10n.openAccessibilitySettings
                            )
                        }
                    }
                    .settingsPrimaryButton()
                    .disabled(isRepairingAccessibility)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private var compactContent: some View {
        HStack(spacing: 12) {
            Image(
                systemName: accessibilityGranted
                    ? "checkmark.circle.fill"
                    : "exclamationmark.triangle.fill"
            )
            .foregroundStyle(accessibilityGranted ? .green : .orange)
            .font(.title3)

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.accessibility)
                Text(accessibilityStatus)
                    .font(.caption)
                    .foregroundStyle(
                        accessibilityGranted
                            ? .green
                            : (
                                accessibilityRepairFailure == nil
                                    ? .secondary
                                    : .red
                            )
                    )
            }

            Spacer()

            if !accessibilityGranted {
                Button {
                    beginAuthorization()
                } label: {
                    if isRepairingAccessibility {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(L10n.repairAccessibility)
                    }
                }
                .disabled(isRepairingAccessibility)
            } else if requestedGrant {
                Button(L10n.restartPesty) {
                    restartAfterAuthorization()
                }
                .settingsPrimaryButton()
            }
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        Label(
            accessibilityStatus,
            systemImage: accessibilityGranted
                ? "checkmark.circle.fill"
                : "circle.dotted"
        )
        .font(.callout)
        .foregroundStyle(
            accessibilityGranted
                ? .green
                : (
                    accessibilityRepairFailure == nil
                        ? .secondary
                        : .red
                )
        )
    }

    private func onboardingDescription(
        for reason: AccessibilityOnboardingReason
    ) -> String {
        switch reason {
        case .firstInstall:
            return L10n.accessibilityFirstInstallDescription
        case .update:
            return L10n.accessibilityUpdateDescription
        }
    }

    private var accessibilityStatus: String {
        if accessibilityGranted {
            return reason == nil
                ? L10n.accessibilityGranted
                : L10n.accessibilityReadyToRestart
        }
        if let accessibilityRepairFailure {
            return L10n.accessibilityRepairFailed(
                accessibilityRepairFailure
            )
        }
        if isRepairingAccessibility {
            return L10n.accessibilityRepairing
        }
        if requestedGrant {
            return L10n.accessibilityWaiting
        }
        return L10n.accessibilityRequired
    }

    private func refreshAuthorization() {
        let current = AXIsProcessTrusted()
        if current != accessibilityGranted {
            accessibilityGranted = current
        }
        if current {
            AccessibilitySettingsGuideController.shared.dismiss()
        }
    }

    private func beginAuthorization() {
        guard !isRepairingAccessibility else { return }
        accessibilityRepairFailure = nil

        if requestedGrant {
            PasteService.ensureAccessibility(prompt: true)
            PasteService.openAccessibilitySettings()
            return
        }

        isRepairingAccessibility = true
        Task { @MainActor in
            let failure =
                await PasteService.resetAccessibilityAuthorization()
            isRepairingAccessibility = false
            if let failure {
                accessibilityRepairFailure = failure
                return
            }

            requestedGrant = true
            PasteService.ensureAccessibility(prompt: true)
            PasteService.openAccessibilitySettings()
        }
    }

    private func restartAfterAuthorization() {
        guard AXIsProcessTrusted() else {
            refreshAuthorization()
            return
        }
        Settings.shared.markAccessibilityOnboardingCompleted(
            for: Bundle.main.appVersion
        )
        AppController.restart()
    }
}

private struct OnboardingStep: View {
    let number: Int
    let title: String
    let isComplete: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        isComplete
                            ? Color.green
                            : Color.secondary.opacity(0.16)
                    )
                if isComplete {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                } else {
                    Text("\(number)")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 24, height: 24)

            Text(title)
                .font(.callout)
        }
    }
}
#endif

private struct SettingsSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.primary)

            content
        }
        .padding(18)
        .settingsCardSurface()
    }
}

private struct SettingsRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let trailing: Trailing

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: subtitle == nil ? .center : .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
    }
}

private extension SettingsRow where Trailing == Text {
    init(title: String, value: String) {
        self.init(title: title) {
            Text(value).foregroundStyle(.secondary)
        }
    }
}

private struct SettingsToggleRow: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title: title, subtitle: subtitle) {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
        }
    }
}

private struct SettingsCardSurfaceModifier: ViewModifier {
    var emphasized: Bool

    func body(content: Content) -> some View {
        content
            .background(
                .regularMaterial,
                in: RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
            )
            .background(
                emphasized ? Color.accentColor.opacity(0.06) : .clear,
                in: RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
    }
}

private struct SettingsPrimaryButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.buttonStyle(.borderedProminent)
    }
}

private extension View {
    func settingsCardSurface(
        emphasized: Bool = false
    ) -> some View {
        modifier(SettingsCardSurfaceModifier(emphasized: emphasized))
    }

    func settingsPrimaryButton() -> some View {
        modifier(SettingsPrimaryButtonModifier())
    }
}

private struct AboutView: View {
    @Bindable private var updater = UpdateManager.shared

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                .resizable()
                .frame(width: 104, height: 104)
                .shadow(color: .black.opacity(0.16), radius: 18, y: 8)

            Text("Pesty")
                .font(.system(size: 30, weight: .bold))
            Text(L10n.version(Bundle.main.appVersion))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(L10n.aboutDescription)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Button(updater.isBusy ? updater.statusText : L10n.checkForUpdates) {
                AppController.shared.checkForUpdatesManually()
            }
            .settingsPrimaryButton()
            .disabled(updater.isBusy)

            if updater.isBusy {
                VStack(spacing: 6) {
                    UpdateProgressIndicator()
                    Text(updater.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 280)
                .accessibilityIdentifier("pesty-settings-update-progress")
            }

            HStack(spacing: 18) {
                Link(
                    "GitHub",
                    destination: URL(
                        string: "https://github.com/\(Repository.current)"
                    )!
                )
                Link(
                    L10n.reportIssue,
                    destination: URL(
                        string: "https://github.com/\(Repository.current)/issues"
                    )!
                )
            }
            .padding(.top, 4)

            Spacer()

            Text(L10n.licenseDescription)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 24)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
