import AppKit
import Carbon.HIToolbox
import Foundation

@MainActor
enum TranslationVerifier {
    private struct Result: Codable {
        let shortcutMatchesDefault: Bool
        let shortcutRejectsDifferentKey: Bool
        let automaticFallsBackToDoubao: Bool
        let appleFailureFallsBackToDoubao: Bool
        let appleRequiresMacOS15: Bool
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
            flags: [.command],
            expectedKeyCode: TranslationShortcut.defaultKeyCode,
            expectedModifiers: TranslationShortcut.defaultModifiers
        )
        let shortcutRejectsDifferentKey = !TranslationShortcut.matches(
            keyCode: kVK_ANSI_R,
            flags: [.command],
            expectedKeyCode: TranslationShortcut.defaultKeyCode,
            expectedModifiers: TranslationShortcut.defaultModifiers
        )
        guard defaultShortcutMatches, shortcutRejectsDifferentKey else {
            throw Failure(description: "Translation shortcut matching is incorrect")
        }

        let explanationShortcutMatches = ExplanationShortcut.matches(
            keyCode: ExplanationShortcut.defaultKeyCode,
            flags: [.command],
            expectedKeyCode: ExplanationShortcut.defaultKeyCode,
            expectedModifiers: ExplanationShortcut.defaultModifiers
        )
        guard explanationShortcutMatches,
              !ExplanationShortcut.matches(
                keyCode: TranslationShortcut.defaultKeyCode,
                flags: [.command],
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
        let explanationShortcutPreservesUserChoice =
            !Settings.shouldMigrateExplanationShortcutDefault(
                migrationVersion: 0,
                keyCode: kVK_ANSI_R,
                modifiers: cmdKey
            )
        guard explanationShortcutMigratesOldDefault,
              explanationShortcutPreservesUserChoice else {
            throw Failure(description: "Explanation shortcut migration is incorrect")
        }
        let contextualMenuShortcutsRender = ContextMenuShortcut(
            keyCode: TranslationShortcut.defaultKeyCode,
            carbonModifiers: TranslationShortcut.defaultModifiers
        )?.display == "⌘T" && ContextMenuShortcut(
            keyCode: ExplanationShortcut.defaultKeyCode,
            carbonModifiers: ExplanationShortcut.defaultModifiers
        )?.display == "⌘D"
        guard contextualMenuShortcutsRender else {
            throw Failure(description: "Context-menu shortcut rendering is incorrect")
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
                sourceText: syntheticText,
                translation: "Short translation"
            )
        let expandedTranslationHeight =
            AssistantPopoverLayout.preferredTranslationHeight(
                sourceText: syntheticText,
                translation: String(
                    repeating: "This translated paragraph should grow the popover height. ",
                    count: 18
                )
            )
        let cappedTranslationHeight =
            AssistantPopoverLayout.preferredTranslationHeight(
                sourceText: syntheticText,
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
            explanation: String(repeating: "这是一段用于验证解释浮层高度会随内容增长的测试文本。", count: 12)
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

        let result = Result(
            shortcutMatchesDefault: defaultShortcutMatches,
            shortcutRejectsDifferentKey: shortcutRejectsDifferentKey,
            automaticFallsBackToDoubao: automaticWithDoubao == .doubao,
            appleFailureFallsBackToDoubao: appleFailureFallsBackToDoubao,
            appleRequiresMacOS15: {
                if case .unavailable = appleUnavailable { return true }
                return false
            }(),
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
                == "https://example.invalid/v1/chat/completions"
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
