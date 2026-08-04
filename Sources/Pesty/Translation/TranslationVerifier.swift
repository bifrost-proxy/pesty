import AppKit
import Carbon.HIToolbox
import Foundation
import Security

@MainActor
enum TranslationVerifier {
    private struct Result: Codable {
        let shortcutMatchesDefault: Bool
        let shortcutRejectsDifferentKey: Bool
        let shortcutMigratesPreviousDefault: Bool
        let shortcutPreservesUserChoice: Bool
        let selectedTextScreenGeometryIsCorrect: Bool
        let selectionGestureAnchorPolicyIsCorrect: Bool
        let pasteboardSnapshotRoundTripsAllTypes: Bool
        let languageSwapShortcutMatchesBareT: Bool
        let languageSwapShortcutRejectsModifiers: Bool
        let automaticFallsBackToDoubao: Bool
        let appleFailureFallsBackToDoubao: Bool
        let appleRequiresMacOS15: Bool
        let manualAppleRequiresInstalledLanguagePacks: Bool
        let automaticAppleMissingPacksFallsBackToDoubao: Bool
        let applePackPlanAlwaysIncludesEnglishAndChinese: Bool
        let applePackPlanIncludesSelectedLanguages: Bool
        let applePackPlanIncludesAutomaticTarget: Bool
        let automaticSourceDetectsInstalledPair: Bool
        let automaticSourceRecognizesSameTarget: Bool
        let automaticSourcePreservesAdditionalLanguage: Bool
        let doubaoRequestUsesChatCompletion: Bool
        let doubaoRequestUsesBearer: Bool
        let doubaoBodyContainsText: Bool
        let doubaoDisablesThinking: Bool
        let manualDoubaoRequiresConfiguration: Bool
        let aiProfileExcludesSecret: Bool
        let explanationShortcutMatchesDefault: Bool
        let explanationShortcutMigratesOldDefault: Bool
        let explanationShortcutPreservesUserChoice: Bool
        let contextualMenuShortcutsRender: Bool
        let explanationRequestUsesConfiguredModel: Bool
        let explanationDisablesDoubaoThinking: Bool
        let explanationRequestRequiresConciseOutput: Bool
        let explanationMarkdownRenderingSupported: Bool
        let translationPopoverGrowsAndCapsHeight: Bool
        let explanationPopoverGrowsAndCapsHeight: Bool
        let openAIEndpointNormalizesToChatCompletions: Bool
        let keychainPresenceLookupExcludesSecretData: Bool
        let keychainSecretLookupReturnsData: Bool
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    static func run() throws {
        let syntheticText = "pesty-translation-verifier"
        let syntheticAPIKey = "synthetic-api-key"

        let automaticWithDoubao = TranslationProviderResolver.resolve(
            selected: .automatic,
            hasDoubaoConfiguration: true,
            supportsAppleTranslation: false
        )
        guard automaticWithDoubao == .doubao else {
            throw Failure(description: "Automatic provider did not fall back to Doubao")
        }
        let appleFailureFallsBackToDoubao =
            TranslationProviderResolver.shouldFallbackFromApple(
                selected: .automatic,
                hasDoubaoConfiguration: true
            ) && !TranslationProviderResolver.shouldFallbackFromApple(
                selected: .apple,
                hasDoubaoConfiguration: true
            )
        guard appleFailureFallsBackToDoubao else {
            throw Failure(
                description: "Apple failure fallback policy is incorrect"
            )
        }
        let appleUnavailable = TranslationProviderResolver.resolve(
            selected: .apple,
            hasDoubaoConfiguration: true,
            supportsAppleTranslation: false
        )
        guard case .unavailable = appleUnavailable else {
            throw Failure(description: "Apple provider did not enforce its macOS availability")
        }
        let manualAppleMissingPacks =
            TranslationProviderResolver.resolveAppleReadiness(
                selected: .apple,
                hasDoubaoConfiguration: true,
                readiness: .downloadRequired
            )
        guard case .unavailable(let missingPackMessage) =
                manualAppleMissingPacks,
              missingPackMessage
                == L10n.appleTranslationLanguagePacksNotInstalled else {
            throw Failure(
                description:
                    "Manual Apple translation did not require installed language packs"
            )
        }
        let automaticAppleMissingPacks =
            TranslationProviderResolver.resolveAppleReadiness(
                selected: .automatic,
                hasDoubaoConfiguration: true,
                readiness: .downloadRequired
            )
        guard automaticAppleMissingPacks == .doubao else {
            throw Failure(
                description:
                    "Automatic translation did not fall back when Apple language packs were missing"
            )
        }
        let baselinePackPlan = AppleTranslationPackPlanner.requirements(
            source: .automatic,
            target: .simplifiedChinese
        )
        let selectedPackPlan = AppleTranslationPackPlanner.requirements(
            source: .japanese,
            target: .simplifiedChinese
        )
        let automaticTargetPackPlan =
            AppleTranslationPackPlanner.requirements(
                source: .automatic,
                target: .japanese
            )
        let baselinePackIsEnglishAndChinese =
            baselinePackPlan.count == 1
            && baselinePackPlan.first?.source == .english
            && baselinePackPlan.first?.target == .simplifiedChinese
            && baselinePackPlan.first?.kind == .baseline
        let selectedPackIsIncluded =
            selectedPackPlan.count == 2
            && selectedPackPlan.first?.kind == .baseline
            && selectedPackPlan.last?.source == .japanese
            && selectedPackPlan.last?.target == .simplifiedChinese
            && selectedPackPlan.last?.kind == .selected
        let automaticTargetPackIsIncluded =
            automaticTargetPackPlan.count == 2
            && automaticTargetPackPlan.first?.kind == .baseline
            && automaticTargetPackPlan.last?.source == .english
            && automaticTargetPackPlan.last?.target == .japanese
            && automaticTargetPackPlan.last?.kind == .selected
        guard baselinePackIsEnglishAndChinese,
              selectedPackIsIncluded,
              automaticTargetPackIsIncluded else {
            throw Failure(
                description:
                    "Apple language-pack planning did not include baseline and selected languages"
            )
        }
        let automaticSourceDetectsInstalledPair =
            AppleAutomaticSourceResolver.resolve(
                detectedIdentifier: "en",
                target: .simplifiedChinese
            ) == .source(identifier: "en")
        let automaticSourceRecognizesSameTarget =
            AppleAutomaticSourceResolver.resolve(
                detectedIdentifier: "zh-Hans",
                target: .simplifiedChinese
            ) == .alreadyInTarget(identifier: "zh-Hans")
        let automaticSourcePreservesAdditionalLanguage =
            AppleAutomaticSourceResolver.resolve(
                detectedIdentifier: "ru",
                target: .simplifiedChinese
            ) == .source(identifier: "ru")
        guard automaticSourceDetectsInstalledPair,
              automaticSourceRecognizesSameTarget,
              automaticSourcePreservesAdditionalLanguage else {
            throw Failure(
                description:
                    "Automatic Apple source-language resolution is incorrect"
            )
        }
        let doubaoUnavailable = TranslationProviderResolver.resolve(
            selected: .doubao,
            hasDoubaoConfiguration: false,
            supportsAppleTranslation: false
        )
        guard case .unavailable = doubaoUnavailable else {
            throw Failure(description: "Doubao provider did not require its configuration")
        }

        let doubaoRequest = try DoubaoTranslationRequestBuilder.make(
            text: syntheticText,
            source: .automatic,
            target: .simplifiedChinese,
            modelID: "doubao-seed-evolving",
            apiKey: syntheticAPIKey
        )
        let doubaoBody = String(data: doubaoRequest.httpBody ?? Data(), encoding: .utf8) ?? ""
        let usesDoubaoChatCompletion = doubaoRequest.url == DoubaoTranslationRequestBuilder.endpoint
            && doubaoRequest.httpMethod == "POST"
            && doubaoRequest.value(forHTTPHeaderField: "Content-Type") == "application/json"
        let usesDoubaoBearer = doubaoRequest.value(forHTTPHeaderField: "Authorization")
            == "Bearer \(syntheticAPIKey)"
        let disablesThinking = doubaoBody.contains("thinking") && doubaoBody.contains("disabled")
        guard usesDoubaoChatCompletion, usesDoubaoBearer,
              doubaoBody.contains(syntheticText),
              doubaoBody.contains("doubao-seed-evolving"), disablesThinking else {
            throw Failure(description: "Doubao request is malformed")
        }

        let defaultShortcutMatches = TranslationShortcut.matches(
            keyCode: TranslationShortcut.defaultKeyCode,
            flags: [.command, .shift],
            expectedKeyCode: TranslationShortcut.defaultKeyCode,
            expectedModifiers: TranslationShortcut.defaultModifiers
        )
        let shortcutRejectsDifferentKey = !TranslationShortcut.matches(
            keyCode: kVK_ANSI_R,
            flags: [.command, .shift],
            expectedKeyCode: TranslationShortcut.defaultKeyCode,
            expectedModifiers: TranslationShortcut.defaultModifiers
        )
        guard defaultShortcutMatches, shortcutRejectsDifferentKey else {
            throw Failure(description: "Translation shortcut matching is incorrect")
        }
        let shortcutMigratesPreviousDefault =
            TranslationShortcut.shouldMigratePreviousDefault(
                migrationVersion: 0,
                keyCode: TranslationShortcut.previousDefaultKeyCode,
                modifiers: TranslationShortcut.previousDefaultModifiers
            )
        let shortcutPreservesUserChoice =
            !TranslationShortcut.shouldMigratePreviousDefault(
                migrationVersion: 0,
                keyCode: kVK_ANSI_R,
                modifiers: cmdKey | optionKey
            )
            && !TranslationShortcut.shouldMigratePreviousDefault(
                migrationVersion: 1,
                keyCode: TranslationShortcut.previousDefaultKeyCode,
                modifiers: TranslationShortcut.previousDefaultModifiers
            )
        guard shortcutMigratesPreviousDefault,
              shortcutPreservesUserChoice else {
            throw Failure(
                description: "Translation shortcut migration is incorrect"
            )
        }
        let convertedSelectionRect =
            SelectedTextScreenGeometry.appKitRect(
                fromAccessibilityRect: CGRect(
                    x: 100,
                    y: 200,
                    width: 120,
                    height: 24
                ),
                primaryScreenMaxY: 1_000
            )
        let selectedTextScreenGeometryIsCorrect =
            convertedSelectionRect
                == NSRect(x: 100, y: 776, width: 120, height: 24)
            && SelectedTextScreenGeometry.usableAnchorRect(
                convertedSelectionRect,
                screens: [NSRect(x: 0, y: 0, width: 1_440, height: 1_000)]
            ) == convertedSelectionRect
            && SelectedTextScreenGeometry.usableAnchorRect(
                .zero,
                screens: [NSRect(x: 0, y: 0, width: 1_440, height: 1_000)]
            ) == nil
        guard selectedTextScreenGeometryIsCorrect else {
            throw Failure(
                description: "Selected-text screen geometry is incorrect"
            )
        }
        let testPasteboard = NSPasteboard(
            name: NSPasteboard.Name(
                "com.bifrostproxy.pesty.translation-verifier.\(UUID().uuidString)"
            )
        )
        testPasteboard.clearContents()
        let textItem = NSPasteboardItem()
        textItem.setString(syntheticText, forType: .string)
        textItem.setData(
            Data([0x01, 0x02, 0x03]),
            forType: NSPasteboard.PasteboardType(
                "com.bifrostproxy.pesty.synthetic"
            )
        )
        let secondItem = NSPasteboardItem()
        secondItem.setString("second-item", forType: .string)
        testPasteboard.writeObjects([textItem, secondItem])
        let pasteboardSnapshot = PasteboardSnapshot(
            pasteboard: testPasteboard
        )
        testPasteboard.clearContents()
        testPasteboard.setString("temporary-copy", forType: .string)
        pasteboardSnapshot.restore(to: testPasteboard)
        let pasteboardSnapshotRoundTripsAllTypes =
            PasteboardSnapshot(pasteboard: testPasteboard)
                == pasteboardSnapshot
        guard pasteboardSnapshotRoundTripsAllTypes else {
            throw Failure(
                description: "Pasteboard snapshot did not restore every item"
            )
        }
        let languageSwapShortcutMatchesBareT =
            TranslationLanguageSwapShortcut.matches(
                keyCode: kVK_ANSI_T,
                flags: []
            )
        let languageSwapShortcutRejectsModifiers =
            !TranslationLanguageSwapShortcut.matches(
                keyCode: kVK_ANSI_T,
                flags: [.command]
            )
        guard languageSwapShortcutMatchesBareT,
              languageSwapShortcutRejectsModifiers else {
            throw Failure(
                description: "Translation language-swap shortcut is incorrect"
            )
        }

        let explanationShortcutMatches = ExplanationShortcut.matches(
            keyCode: ExplanationShortcut.defaultKeyCode,
            flags: [.command, .shift],
            expectedKeyCode: ExplanationShortcut.defaultKeyCode,
            expectedModifiers: ExplanationShortcut.defaultModifiers
        )
        guard explanationShortcutMatches,
              !ExplanationShortcut.matches(
                keyCode: TranslationShortcut.defaultKeyCode,
                flags: [.command, .shift],
                expectedKeyCode: ExplanationShortcut.defaultKeyCode,
                expectedModifiers: ExplanationShortcut.defaultModifiers
              ) else {
            throw Failure(description: "Explanation shortcut matching is incorrect")
        }
        let explanationShortcutMigratesOldDefault =
            Settings.shouldMigrateExplanationShortcutDefault(
                migrationVersion: 0,
                keyCode: ExplanationShortcut.previousDefaultKeyCode,
                modifiers: ExplanationShortcut.previousDefaultModifiers
            )
            && Settings.shouldMigrateExplanationShortcutDefault(
                migrationVersion: 1,
                keyCode: kVK_ANSI_D,
                modifiers: cmdKey
            )
        let explanationShortcutPreservesUserChoice =
            !Settings.shouldMigrateExplanationShortcutDefault(
                migrationVersion: 0,
                keyCode: kVK_ANSI_R,
                modifiers: cmdKey
            )
            && !Settings.shouldMigrateExplanationShortcutDefault(
                migrationVersion: ExplanationShortcut.migrationVersion,
                keyCode: kVK_ANSI_D,
                modifiers: cmdKey
            )
        guard explanationShortcutMigratesOldDefault,
              explanationShortcutPreservesUserChoice else {
            throw Failure(description: "Explanation shortcut migration is incorrect")
        }
        let contextualMenuShortcutsRender = ContextMenuShortcut(
            keyCode: TranslationShortcut.defaultKeyCode,
            carbonModifiers: TranslationShortcut.defaultModifiers
        )?.display == "⇧⌘T" && ContextMenuShortcut(
            keyCode: ExplanationShortcut.defaultKeyCode,
            carbonModifiers: ExplanationShortcut.defaultModifiers
        )?.display == "⇧⌘D"
        guard contextualMenuShortcutsRender else {
            throw Failure(description: "Context-menu shortcut rendering is incorrect")
        }

        let gestureTracker = SelectionGestureTracker.shared
        let gestureTime = Date()
        gestureTracker.recordMouseDown(
            at: NSPoint(x: 40, y: 50),
            sourceBundleIdentifier: "com.pesty.synthetic.source"
        )
        gestureTracker.recordMouseDragged(
            to: NSPoint(x: 120, y: 70)
        )
        gestureTracker.recordMouseUp(
            at: NSPoint(x: 180, y: 80),
            sourceBundleIdentifier: "com.pesty.synthetic.source",
            occurredAt: gestureTime
        )
        let selectionGestureAnchorIsRecentAndSourceScoped =
            gestureTracker.bestAnchorPoint(
                for: "com.pesty.synthetic.source",
                now: gestureTime.addingTimeInterval(1)
            ) == NSPoint(x: 180, y: 80)
            && gestureTracker.bestAnchorPoint(
                for: "com.pesty.synthetic.other",
                now: gestureTime.addingTimeInterval(1)
            ) == nil
            && gestureTracker.bestAnchorPoint(
                for: "com.pesty.synthetic.source",
                now: gestureTime.addingTimeInterval(
                    SelectionGestureTracker.maximumAnchorAge + 1
                )
            ) == nil
        gestureTracker.recordMouseDown(
            at: NSPoint(x: 200, y: 200),
            sourceBundleIdentifier: "com.pesty.synthetic.source"
        )
        gestureTracker.recordMouseUp(
            at: NSPoint(x: 201, y: 200),
            sourceBundleIdentifier: "com.pesty.synthetic.source",
            occurredAt: gestureTime
        )
        let ordinaryClickIsNotASelectionAnchor =
            gestureTracker.bestAnchorPoint(
                for: "com.pesty.synthetic.source",
                now: gestureTime.addingTimeInterval(1)
            ) == nil
        guard selectionGestureAnchorIsRecentAndSourceScoped,
              ordinaryClickIsNotASelectionAnchor else {
            throw Failure(
                description: "Selection gesture anchoring is incorrect"
            )
        }

        let explanationRequest = try ExplanationClient.makeRequest(
            text: syntheticText,
            provider: .doubao(
                modelID: "doubao-seed-evolving",
                apiKey: syntheticAPIKey
            )
        )
        let explanationBody = String(
            data: explanationRequest.httpBody ?? Data(),
            encoding: .utf8
        ) ?? ""
        guard explanationRequest.url == DoubaoTranslationRequestBuilder.endpoint,
              explanationRequest.value(forHTTPHeaderField: "Authorization")
                == "Bearer \(syntheticAPIKey)",
              explanationBody.contains(syntheticText),
              explanationBody.contains("doubao-seed-evolving"),
              explanationBody.contains("thinking"),
              explanationBody.contains("disabled") else {
            throw Failure(description: "Doubao explanation request is malformed")
        }
        let explanationRequestRequiresConciseOutput = explanationBody.contains("160")
            && explanationBody.contains("3 个短要点")
            && explanationBody.contains("Markdown")
        guard explanationRequestRequiresConciseOutput else {
            throw Failure(description: "Explanation request does not require concise output")
        }
        let markdownBlocks = ExplanationMarkdownParser.blocks(
            from: "**核心含义**\n- `uid` 是常用字段\n1. 先确认上下文"
        )
        let explanationMarkdownRenderingSupported = markdownBlocks == [
            .paragraph("**核心含义**"),
            .unordered("`uid` 是常用字段"),
            .ordered(number: 1, text: "先确认上下文"),
        ]
        guard explanationMarkdownRenderingSupported else {
            throw Failure(description: "Explanation Markdown parsing is incorrect")
        }
        let defaultTranslationHeight =
            AssistantPopoverLayout.preferredTranslationHeight(
                translation: "Short translation"
            )
        let expandedTranslationHeight =
            AssistantPopoverLayout.preferredTranslationHeight(
                translation: String(
                    repeating: "This translated paragraph should grow the popover height. ",
                    count: 18
                )
            )
        let cappedTranslationHeight =
            AssistantPopoverLayout.preferredTranslationHeight(
                translation: String(repeating: "Long translation ", count: 800)
            )
        let translationPopoverGrowsAndCapsHeight =
            defaultTranslationHeight
                == AssistantPopoverLayout.translationDefaultHeight
            && expandedTranslationHeight > defaultTranslationHeight
            && expandedTranslationHeight
                <= AssistantPopoverLayout.translationMaximumHeight
            && cappedTranslationHeight
                == AssistantPopoverLayout.translationMaximumHeight
        guard translationPopoverGrowsAndCapsHeight else {
            throw Failure(description: "Translation popover height policy is incorrect")
        }
        let defaultExplanationHeight = AssistantPopoverLayout.preferredExplanationHeight(
            sourceText: syntheticText,
            explanation: "简短说明"
        )
        let expandedExplanationHeight = AssistantPopoverLayout.preferredExplanationHeight(
            sourceText: syntheticText,
            explanation: String(
                repeating: "这是一段用于验证解释浮层高度会随内容增长的测试文本。",
                count: 24
            )
        )
        let cappedExplanationHeight = AssistantPopoverLayout.preferredExplanationHeight(
            sourceText: syntheticText,
            explanation: String(repeating: "解释内容", count: 800)
        )
        let explanationPopoverGrowsAndCapsHeight = defaultExplanationHeight
            == AssistantPopoverLayout.explanationDefaultHeight
            && expandedExplanationHeight > defaultExplanationHeight
            && expandedExplanationHeight <= AssistantPopoverLayout.explanationMaximumHeight
            && cappedExplanationHeight == AssistantPopoverLayout.explanationMaximumHeight
        guard explanationPopoverGrowsAndCapsHeight else {
            throw Failure(description: "Explanation popover height policy is incorrect")
        }
        let normalizedEndpoint = ExplanationClient.chatCompletionEndpoint(
            from: "https://example.invalid/v1/"
        )
        guard normalizedEndpoint?.absoluteString
            == "https://example.invalid/v1/chat/completions" else {
            throw Failure(description: "OpenAI-compatible explanation endpoint is malformed")
        }

        let profile = AIProviderProfile(
            name: "Verifier",
            endpoint: "https://example.invalid/v1",
            model: "translation-test"
        )
        let encodedProfile = try JSONEncoder().encode(profile)
        guard let encodedText = String(data: encodedProfile, encoding: .utf8),
              !encodedText.contains("apiKey"),
              !encodedText.contains(syntheticAPIKey) else {
            throw Failure(description: "AI provider metadata contains credential material")
        }

        let presenceQuery = SecureCredentialStore.presenceQuery(
            account: "translation-verifier"
        )
        let secretReadQuery = SecureCredentialStore.secretReadQuery(
            account: "translation-verifier"
        )
        let keychainPresenceLookupExcludesSecretData =
            presenceQuery[kSecReturnAttributes as String] as? Bool == true
            && presenceQuery[kSecReturnData as String] == nil
        let keychainSecretLookupReturnsData =
            secretReadQuery[kSecReturnData as String] as? Bool == true
            && secretReadQuery[kSecReturnAttributes as String] == nil
        guard keychainPresenceLookupExcludesSecretData,
              keychainSecretLookupReturnsData else {
            throw Failure(description: "Keychain lookup modes are not separated")
        }

        let result = Result(
            shortcutMatchesDefault: defaultShortcutMatches,
            shortcutRejectsDifferentKey: shortcutRejectsDifferentKey,
            shortcutMigratesPreviousDefault: shortcutMigratesPreviousDefault,
            shortcutPreservesUserChoice: shortcutPreservesUserChoice,
            selectedTextScreenGeometryIsCorrect:
                selectedTextScreenGeometryIsCorrect,
            selectionGestureAnchorPolicyIsCorrect:
                selectionGestureAnchorIsRecentAndSourceScoped
                    && ordinaryClickIsNotASelectionAnchor,
            pasteboardSnapshotRoundTripsAllTypes:
                pasteboardSnapshotRoundTripsAllTypes,
            languageSwapShortcutMatchesBareT:
                languageSwapShortcutMatchesBareT,
            languageSwapShortcutRejectsModifiers:
                languageSwapShortcutRejectsModifiers,
            automaticFallsBackToDoubao: automaticWithDoubao == .doubao,
            appleFailureFallsBackToDoubao: appleFailureFallsBackToDoubao,
            appleRequiresMacOS15: {
                if case .unavailable = appleUnavailable { return true }
                return false
            }(),
            manualAppleRequiresInstalledLanguagePacks: {
                if case .unavailable = manualAppleMissingPacks {
                    return true
                }
                return false
            }(),
            automaticAppleMissingPacksFallsBackToDoubao:
                automaticAppleMissingPacks == .doubao,
            applePackPlanAlwaysIncludesEnglishAndChinese:
                baselinePackIsEnglishAndChinese,
            applePackPlanIncludesSelectedLanguages:
                selectedPackIsIncluded,
            applePackPlanIncludesAutomaticTarget:
                automaticTargetPackIsIncluded,
            automaticSourceDetectsInstalledPair:
                automaticSourceDetectsInstalledPair,
            automaticSourceRecognizesSameTarget:
                automaticSourceRecognizesSameTarget,
            automaticSourcePreservesAdditionalLanguage:
                automaticSourcePreservesAdditionalLanguage,
            doubaoRequestUsesChatCompletion: usesDoubaoChatCompletion,
            doubaoRequestUsesBearer: usesDoubaoBearer,
            doubaoBodyContainsText: doubaoBody.contains(syntheticText),
            doubaoDisablesThinking: disablesThinking,
            manualDoubaoRequiresConfiguration: {
                if case .unavailable = doubaoUnavailable { return true }
                return false
            }(),
            aiProfileExcludesSecret: !encodedText.contains("apiKey"),
            explanationShortcutMatchesDefault: explanationShortcutMatches,
            explanationShortcutMigratesOldDefault: explanationShortcutMigratesOldDefault,
            explanationShortcutPreservesUserChoice: explanationShortcutPreservesUserChoice,
            contextualMenuShortcutsRender: contextualMenuShortcutsRender,
            explanationRequestUsesConfiguredModel: explanationBody.contains("doubao-seed-evolving"),
            explanationDisablesDoubaoThinking: explanationBody.contains("disabled"),
            explanationRequestRequiresConciseOutput: explanationRequestRequiresConciseOutput,
            explanationMarkdownRenderingSupported: explanationMarkdownRenderingSupported,
            translationPopoverGrowsAndCapsHeight:
                translationPopoverGrowsAndCapsHeight,
            explanationPopoverGrowsAndCapsHeight: explanationPopoverGrowsAndCapsHeight,
            openAIEndpointNormalizesToChatCompletions: normalizedEndpoint?.absoluteString
                == "https://example.invalid/v1/chat/completions",
            keychainPresenceLookupExcludesSecretData:
                keychainPresenceLookupExcludesSecretData,
            keychainSecretLookupReturnsData: keychainSecretLookupReturnsData
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(result)
        guard let json = String(data: data, encoding: .utf8) else {
            throw Failure(description: "Could not encode translation verification result")
        }
        print("TRANSLATION_VERIFICATION_RESULT \(json)")
    }
}
