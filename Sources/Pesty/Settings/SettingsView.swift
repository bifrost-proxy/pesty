import SwiftUI
import AppKit

struct SettingsView: View {
    @Bindable private var settings = Settings.shared

    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label(L10n.general, systemImage: "gearshape") }
            AboutView()
                .tabItem { Label(L10n.about, systemImage: "info.circle") }
        }
        .frame(width: 520, height: 560)
        .id(settings.language)
    }
}

private struct GeneralSettings: View {
    @Bindable private var settings = Settings.shared
    @Bindable private var store = ClipboardStore.shared
    @State private var retentionSliderPosition =
        Settings.shared.historyRetentionSliderPosition
    #if !MAS
    @State private var accessibilityGranted = AXIsProcessTrusted()
    @State private var requestedGrant = false
    @State private var isRepairingAccessibility = false
    @State private var accessibilityRepairFailure: String?

    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    #endif

    var body: some View {
        Form {
            Section(L10n.activation) {
                LabeledContent(L10n.showPesty) { HotkeyRecorderView() }
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent(
                        L10n.historyLimit,
                        value: retentionDisplayValue
                    )
                    Slider(
                        value: $retentionSliderPosition,
                        in: 0...HistoryRetentionPolicy.unlimitedSliderPosition,
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
                LabeledContent(
                    L10n.storageUsed,
                    value: storageDisplayValue
                )
            }

            Section(L10n.behavior) {
                #if !MAS
                Toggle(L10n.pasteDirectly, isOn: $settings.pasteDirectly)
                #endif
                Toggle(L10n.ignorePasswords, isOn: $settings.ignoreConcealed)
                Toggle(L10n.playSound, isOn: $settings.playSound)
                Toggle(L10n.launchAtLogin, isOn: $settings.launchAtLogin)
                Toggle(L10n.showMenuBarIcon, isOn: $settings.showMenuBarIcon)
                Text(L10n.showMenuBarIconDescription)
                    .font(.caption).foregroundStyle(.secondary)
                VStack(alignment: .leading) {
                    LabeledContent(L10n.barHeight, value: "\(Int(settings.barHeight)) \(L10n.px)")
                    Slider(value: $settings.barHeight, in: 300...720, step: 10)
                }
                #if MAS
                Text(L10n.selectClip)
                    .font(.caption).foregroundStyle(.secondary)
                #endif
            }

            Section(L10n.sync) {
                Toggle(L10n.syncClipboard, isOn: Binding(
                    get: { settings.iCloudSync },
                    set: { _ in AppController.shared.toggleICloudSync() }))
                Text(ClipboardStore.shared.iCloudAvailable
                     ? L10n.syncAvailable
                     : L10n.syncUnavailable)
                    .font(.caption).foregroundStyle(.secondary)
            }

            #if !MAS
            Section(L10n.permissions) {
                HStack(spacing: 10) {
                    Image(systemName: accessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(accessibilityGranted ? .green : .orange)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.accessibility)
                        Text(accessibilityStatus)
                            .font(.caption)
                            .foregroundStyle(
                                accessibilityGranted
                                    ? .green
                                    : (accessibilityRepairFailure == nil ? .secondary : .red)
                            )
                    }
                    Spacer()
                    if !accessibilityGranted {
                        Button {
                            repairAccessibility()
                        } label: {
                            if isRepairingAccessibility {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text(L10n.repairAccessibility)
                            }
                        }
                        .disabled(isRepairingAccessibility)
                    } else if requestedGrant {
                        Button(L10n.restartPesty) { AppController.restart() }
                    }
                }
            }
            #endif

            Section(L10n.languageLabel) {
                Picker(L10n.languageLabel, selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                Text(L10n.languageDescription)
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(L10n.data) {
                Button(L10n.clearClipboardHistory, role: .destructive) {
                    AppController.shared.requestClearHistoryConfirmation()
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            retentionSliderPosition = settings.historyRetentionSliderPosition
            store.refreshStorageUsage()
        }
        #if !MAS
        .onAppear { accessibilityGranted = AXIsProcessTrusted() }
        .onReceive(poll) { _ in
            let now = AXIsProcessTrusted()
            if now != accessibilityGranted { accessibilityGranted = now }
        }
        #endif
        .id(settings.language)
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

    #if !MAS
    private var accessibilityStatus: String {
        if accessibilityGranted {
            return L10n.accessibilityGranted
        }
        if let accessibilityRepairFailure {
            return L10n.accessibilityRepairFailed(accessibilityRepairFailure)
        }
        if isRepairingAccessibility {
            return L10n.accessibilityRepairing
        }
        if requestedGrant {
            return L10n.accessibilityWaiting
        }
        return L10n.accessibilityRequired
    }

    private func repairAccessibility() {
        guard !isRepairingAccessibility else { return }
        requestedGrant = false
        accessibilityRepairFailure = nil
        isRepairingAccessibility = true

        Task { @MainActor in
            let failure = await PasteService.resetAccessibilityAuthorization()
            isRepairingAccessibility = false
            if let failure {
                accessibilityRepairFailure = failure
                return
            }

            requestedGrant = true
            PasteService.ensureAccessibility(prompt: true)
            openAccessibilityPane()
        }
    }

    private func openAccessibilityPane() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    #endif
}

private struct AboutView: View {
    @Bindable private var updater = UpdateManager.shared

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                .resizable().frame(width: 88, height: 88)
            Text("Pesty").font(.system(size: 26, weight: .bold))
            Text(L10n.version(Bundle.main.appVersion))
                .font(.subheadline).foregroundStyle(.secondary)
            Text(L10n.aboutDescription)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Button(L10n.checkForUpdates) {
                AppController.shared.checkForUpdatesManually()
            }
            .disabled(updater.activity == .checking || updater.isInstalling)
            HStack(spacing: 16) {
                Link("GitHub", destination: URL(string: "https://github.com/\(Repository.current)")!)
                Link(L10n.reportIssue,
                     destination: URL(string: "https://github.com/\(Repository.current)/issues")!)
            }
            .padding(.top, 4)
            Spacer()
            Text(L10n.licenseDescription)
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
