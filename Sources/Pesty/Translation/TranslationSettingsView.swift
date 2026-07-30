import AppKit
import Carbon.HIToolbox
import SwiftUI

struct TranslationSettingsView: View {
    private static let arkAPIKeyManagementURL = URL(
        string: "https://console.volcengine.com/ark/region:cn-beijing/apikey"
    )!

    @Bindable private var settings = Settings.shared
    @State private var doubaoAPIKey = ""
    @State private var doubaoModelID = ""
    @State private var isReplacingDoubaoAPIKey = false
    @State private var feedback: Feedback?
    @State private var showingAIProviderEditor = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                TranslationSettingsSection(
                    title: L10n.translationPreferences,
                    systemImage: "character.bubble"
                ) {
                    TranslationSettingsRow(title: L10n.sourceLanguage) {
                        Picker(L10n.sourceLanguage, selection: $settings.translationSourceLanguage) {
                            ForEach(TranslationLanguage.allCases) { language in
                                Text(language.displayName).tag(language)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }
                    Divider()
                    TranslationSettingsRow(title: L10n.targetLanguage) {
                        Picker(L10n.targetLanguage, selection: $settings.translationTargetLanguage) {
                            ForEach(TranslationLanguage.allCases.filter { $0 != .automatic }) { language in
                                Text(language.displayName).tag(language)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }
                    Divider()
                    TranslationSettingsRow(
                        title: L10n.translationService,
                        subtitle: L10n.translationServiceDescription
                    ) {
                        Picker(L10n.translationService, selection: $settings.translationService) {
                            ForEach(TranslationService.allCases) { service in
                                Text(service.displayName).tag(service)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }
                    if settings.translationService == .apple {
                        Divider()
                        AppleTranslationLanguagePacksView(
                            source: settings.translationSourceLanguage,
                            target: settings.translationTargetLanguage
                        )
                    }
                }

                TranslationSettingsSection(
                    title: L10n.translationShortcut,
                    systemImage: "command"
                ) {
                    TranslationSettingsRow(
                        title: L10n.showTranslationBoard,
                        subtitle: L10n.translationShortcutDescription
                    ) {
                        TranslationHotkeyRecorderView()
                    }
                }

                TranslationSettingsSection(
                    title: L10n.explanationShortcut,
                    systemImage: "text.magnifyingglass"
                ) {
                    TranslationSettingsRow(
                        title: L10n.showExplanationBoard,
                        subtitle: L10n.explanationShortcutDescription
                    ) {
                        ExplanationHotkeyRecorderView()
                    }
                }

                TranslationSettingsSection(
                    title: L10n.doubaoTranslation,
                    systemImage: "sparkles"
                ) {
                    Text(L10n.doubaoTranslationDisclosure)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Link(destination: Self.arkAPIKeyManagementURL) {
                            Label(
                                L10n.openDoubaoAPIKeyPage,
                                systemImage: "arrow.up.right.square"
                            )
                        }
                        .font(.callout)
                        Spacer()
                    }
                    if settings.doubaoTranslationConfigured, !isReplacingDoubaoAPIKey {
                        HStack(spacing: 10) {
                            Label(
                                L10n.credentialStoredInKeychain,
                                systemImage: "key.horizontal.fill"
                            )
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            Spacer()
                            Button(L10n.replaceAPIKey) {
                                isReplacingDoubaoAPIKey = true
                            }
                        }
                    } else {
                        HStack(spacing: 10) {
                            SecureField(L10n.doubaoTranslationAPIKey, text: $doubaoAPIKey)
                                .textFieldStyle(.roundedBorder)
                            Button(L10n.save) { saveDoubaoAPIKey() }
                                .disabled(doubaoAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            if settings.doubaoTranslationConfigured {
                                Button(L10n.cancel) {
                                    doubaoAPIKey = ""
                                    isReplacingDoubaoAPIKey = false
                                }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 10) {
                            TextField(L10n.doubaoTranslationModelID, text: $doubaoModelID)
                                .textFieldStyle(.roundedBorder)
                            Button(L10n.save) { saveDoubaoModelID() }
                                .disabled(doubaoModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        Text(L10n.doubaoModelIDExample)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Label(
                            settings.doubaoTranslationConfigured
                                ? L10n.doubaoTranslationConfigured
                                : L10n.doubaoTranslationNotConfigured,
                            systemImage: settings.doubaoTranslationConfigured
                                ? "checkmark.circle.fill"
                                : "circle.dotted"
                        )
                        .font(.caption)
                        .foregroundStyle(settings.doubaoTranslationConfigured ? .green : .secondary)
                        Spacer()
                        if !settings.doubaoTranslationModelID.isEmpty {
                            Text(settings.doubaoTranslationModelID)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    if let feedback {
                        Text(feedback.message)
                            .font(.caption)
                            .foregroundStyle(feedback.isFailure ? .red : .green)
                    }
                }

                TranslationSettingsSection(
                    title: L10n.aiProviders,
                    systemImage: "sparkles"
                ) {
                    Text(L10n.aiProvidersDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if settings.aiProviderProfiles.isEmpty {
                        Text(L10n.noAIProviders)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(settings.aiProviderProfiles) { profile in
                            HStack(spacing: 10) {
                                Image(systemName: "cpu")
                                    .foregroundStyle(Color.accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.name).font(.callout.weight(.medium))
                                    Text("\(profile.model) · \(profile.endpoint)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Button(L10n.remove, role: .destructive) {
                                    removeAIProvider(profile)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                    Button {
                        showingAIProviderEditor = true
                    } label: {
                        Label(L10n.addAIProvider, systemImage: "plus")
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 650)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showingAIProviderEditor) {
            AIProviderEditor { profile, apiKey in
                do {
                    try settings.addAIProviderProfile(profile, apiKey: apiKey)
                    showingAIProviderEditor = false
                } catch {
                    feedback = .failure(L10n.credentialSaveFailed)
                }
            }
        }
        .onAppear {
            doubaoModelID = settings.doubaoTranslationModelID
        }
    }

    private func saveDoubaoAPIKey() {
        do {
            try settings.saveDoubaoTranslationAPIKey(doubaoAPIKey)
            doubaoAPIKey = ""
            isReplacingDoubaoAPIKey = false
            feedback = .success(L10n.credentialSaved)
        } catch {
            feedback = .failure(L10n.credentialSaveFailed)
        }
    }

    private func saveDoubaoModelID() {
        settings.saveDoubaoTranslationModelID(doubaoModelID)
        doubaoModelID = settings.doubaoTranslationModelID
        feedback = .success(L10n.doubaoModelSaved)
    }

    private func removeAIProvider(_ profile: AIProviderProfile) {
        do {
            try settings.removeAIProviderProfile(profile)
        } catch {
            feedback = .failure(L10n.credentialRemoveFailed)
        }
    }

    private struct Feedback {
        let message: String
        let isFailure: Bool

        static func success(_ message: String) -> Self {
            Self(message: message, isFailure: false)
        }

        static func failure(_ message: String) -> Self {
            Self(message: message, isFailure: true)
        }
    }
}

private struct TranslationSettingsSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content
        }
        .padding(18)
        // Sections without a row containing a trailing control used to shrink to
        // their intrinsic width, leaving the AI provider section off the shared
        // settings grid. Keep every section on the same horizontal rhythm.
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        }
    }
}

private struct TranslationSettingsRow<Trailing: View>: View {
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

private struct TranslationHotkeyRecorderView: View {
    @Bindable private var settings = Settings.shared
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? L10n.pressKeys : settings.translationHotkeyDisplay)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .frame(minWidth: 90)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    recording ? Color.accentColor.opacity(0.2) : Color(NSColor.controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 7)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(recording ? Color.accentColor : Color.secondary.opacity(0.3))
                }
        }
        .buttonStyle(.plain)
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            guard event.type == .keyDown else { return event }
            let modifiers = carbonModifiers(from: event.modifierFlags)
            guard modifiers & (cmdKey | controlKey | optionKey) != 0 else {
                NSSound.beep()
                return nil
            }
            settings.translationHotkeyKeyCode = Int(event.keyCode)
            settings.translationHotkeyModifiers = modifiers
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> Int {
        var modifiers = 0
        if flags.contains(.command) { modifiers |= cmdKey }
        if flags.contains(.shift) { modifiers |= shiftKey }
        if flags.contains(.option) { modifiers |= optionKey }
        if flags.contains(.control) { modifiers |= controlKey }
        return modifiers
    }
}

private struct ExplanationHotkeyRecorderView: View {
    @Bindable private var settings = Settings.shared
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? L10n.pressKeys : settings.explanationHotkeyDisplay)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .frame(minWidth: 90)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    recording ? Color.accentColor.opacity(0.2) : Color(NSColor.controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 7)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(recording ? Color.accentColor : Color.secondary.opacity(0.3))
                }
        }
        .buttonStyle(.plain)
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            let modifiers = carbonModifiers(from: event.modifierFlags)
            guard modifiers & (cmdKey | controlKey | optionKey) != 0 else {
                NSSound.beep()
                return nil
            }
            settings.explanationHotkeyKeyCode = Int(event.keyCode)
            settings.explanationHotkeyModifiers = modifiers
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> Int {
        var modifiers = 0
        if flags.contains(.command) { modifiers |= cmdKey }
        if flags.contains(.shift) { modifiers |= shiftKey }
        if flags.contains(.option) { modifiers |= optionKey }
        if flags.contains(.control) { modifiers |= controlKey }
        return modifiers
    }
}

private struct AIProviderEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var endpoint = "https://api.example.com/v1"
    @State private var model = ""
    @State private var apiKey = ""

    let onSave: (AIProviderProfile, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.addAIProvider)
                .font(.title3.weight(.semibold))
            Text(L10n.aiProviderEditorDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
            TextField(L10n.aiProviderName, text: $name)
            TextField(L10n.apiEndpoint, text: $endpoint)
            TextField(L10n.modelName, text: $model)
            SecureField(L10n.apiKey, text: $apiKey)
            HStack {
                Spacer()
                Button(L10n.cancel) { dismiss() }
                Button(L10n.save) {
                    onSave(
                        AIProviderProfile(
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            endpoint: endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
                            model: model.trimmingCharacters(in: .whitespacesAndNewlines)
                        ),
                        apiKey
                    )
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && URL(string: endpoint)?.scheme != nil
            && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
