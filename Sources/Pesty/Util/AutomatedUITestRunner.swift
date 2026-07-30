import AppKit
import Carbon.HIToolbox
import Darwin
import Foundation

@MainActor
enum AutomatedUITestProbe {
    private(set) static var renderedTexts = Set<String>()
    private(set) static var translationBoardRendered = false
    private(set) static var translationPreviewRendered = false
    private(set) static var explanationBoardRendered = false
    private(set) static var explanationPreviewRendered = false
    private(set) static var appleLanguagePackSettingsRendered = false
    private(set) static var assistantProcessingItemIDs = Set<UUID>()
    private(set) static var renderedItemIDs = Set<UUID>()

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["PESTY_AUTOMATED_UI_TEST"] != nil
    }

    static func reset() {
        renderedTexts.removeAll()
        translationBoardRendered = false
        translationPreviewRendered = false
        explanationBoardRendered = false
        explanationPreviewRendered = false
        appleLanguagePackSettingsRendered = false
        assistantProcessingItemIDs.removeAll()
        renderedItemIDs.removeAll()
    }

    static func record(_ item: ClipItem) {
        guard isEnabled else { return }
        renderedItemIDs.insert(item.id)
        guard ProcessInfo.processInfo.environment["PESTY_AUTOMATED_UI_TEST"]
                != "performance",
              let text = item.text else { return }
        renderedTexts.insert(text)
    }

    static func recordTranslationBoard() {
        guard isEnabled else { return }
        translationBoardRendered = true
    }

    static func recordTranslationPreview() {
        guard isEnabled else { return }
        translationPreviewRendered = true
    }

    static func recordExplanationBoard() {
        guard isEnabled else { return }
        explanationBoardRendered = true
    }

    static func recordExplanationPreview() {
        guard isEnabled else { return }
        explanationPreviewRendered = true
    }

    static func recordAppleLanguagePackSettings() {
        guard isEnabled else { return }
        appleLanguagePackSettingsRendered = true
    }

    static func recordAssistantProcessing(itemID: UUID, visible: Bool) {
        guard isEnabled else { return }
        if visible {
            assistantProcessingItemIDs.insert(itemID)
        } else {
            assistantProcessingItemIDs.remove(itemID)
        }
    }
}

@MainActor
enum AutomatedUITestRunner {
    private struct Result: Codable {
        let phase: String
        let success: Bool
        let historyCount: Int
        let visibleCount: Int
        let expectedCount: Int
        let persistedMatches: Int
        let visibleMatches: Int
        let renderedMatches: Int
        let source: String
        let searchLength: Int
    }

    private struct CleanupResult: Codable {
        let phase: String
        let success: Bool
        let historyCount: Int
        let removedCount: Int
    }

    private struct PerformanceResult: Codable {
        let phase: String
        let success: Bool
        let historyCount: Int
        let visibleCount: Int
        let expectedCount: Int
        let persistedInOrder: Bool
        let visibleInOrder: Bool
        let checkpointCount: Int
        let renderedCheckpoints: Int
        let configuredCheckpoints: Int
        let createdCellCount: Int
        let maximumVisibleCellCount: Int
        let maximumAllowedCells: Int
        let hostingRootCreationCount: Int
        let maximumHostingRootCreationCount: Int
        let cellConfigurationCount: Int
        let configuredItemCount: Int
        let rapidScrollStepCount: Int
        let previewBounded: Bool
        let imageItemCount: Int
        let finalSelectedIndex: Int?
        let source: String
        let searchLength: Int
        let durationMilliseconds: Int
        let maximumDurationMilliseconds: Int
    }

    private struct MouseSelectionResult: Codable {
        let phase: String
        let success: Bool
        let itemCount: Int
        let selectionChangedSynchronously: Bool
        let selectionLatencyMilliseconds: Double
        let maximumSelectionLatencyMilliseconds: Double
        let selectionRendered: Bool
        let renderLatencyMilliseconds: Double
        let maximumRenderLatencyMilliseconds: Double
        let textEditorFocusedBeforeClick: Bool
        let textEditorReleasedByClick: Bool
        let selectionPreservedEventSurface: Bool
        let doubleClickSelectedItem: Bool
        let doubleClickRequestedQuickPaste: Bool
        let doubleClickQuickPasteRequestCount: Int
        let rightArrowConsumedAfterClick: Bool
        let rightArrowMovedSelectionAfterClick: Bool
        let contentIndexRebuildCount: Int
        let maximumContentIndexRebuildCount: Int
        let visibleClickPreservedScrollPosition: Bool
        let offscreenSelectionBecameVisible: Bool
        let offscreenSelectionWasNotCentered: Bool
    }

    private struct KeyboardDeleteResult: Codable {
        let phase: String
        let success: Bool
        let initialCount: Int
        let finalCount: Int
        let searchBackspaceConsumed: Bool
        let searchBackspacePreservedHistory: Bool
        let rightArrowConsumed: Bool
        let plainBackspaceConsumed: Bool
        let plainBackspacePreservedHistory: Bool
        let forwardDeleteConsumed: Bool
        let forwardDeletePreservedHistory: Bool
        let commandBackspaceConsumed: Bool
        let selectedFollowingItemAfterMiddleDelete: Bool
        let selectedFollowingItemAfterSecondDelete: Bool
        let selectedPreviousItemAfterTailDelete: Bool
        let remainingItemMatches: Bool
    }

    private struct RetentionDelayResult: Codable {
        let phase: String
        let success: Bool
        let initialCount: Int
        let countDuringGracePeriod: Int
        let countAfterCancellation: Int
        let countDuringSecondGracePeriod: Int
        let finalCount: Int
        let expectedFinalCount: Int
    }

    private struct RetentionRestartResult: Codable {
        let phase: String
        let success: Bool
        let countAfterRestart: Int
        let finalCount: Int
        let expectedFinalCount: Int
    }

    private struct RetentionSyncResult: Codable {
        let phase: String
        let success: Bool
        let countBeforeDeadline: Int
        let finalCount: Int
        let expectedFinalCount: Int
        let configuredLimit: Int
        let unlimited: Bool
        let hasSyncedConfiguration: Bool
        let hasSharedEffectiveDate: Bool
    }

    private struct ClearConfirmationResult: Codable {
        let phase: String
        let success: Bool
        let initialCount: Int
        let countAfterCancellation: Int
        let countAfterConfirmation: Int
        let pinboardCountAfterConfirmation: Int
    }

    private struct DeletionSyncResult: Codable {
        let phase: String
        let success: Bool
        let historyCount: Int
        let deletedItemAbsent: Bool
        let deletedPinboardItemAbsent: Bool
        let tombstoneCount: Int
        let staleSnapshotRejected: Bool
        let recopyAllowed: Bool
    }

    private struct SearchInputResult: Codable {
        let phase: String
        let success: Bool
        let searchFieldActivated: Bool
        let nativeTextFieldCount: Int
        let nativeTextEditorFocused: Bool
        let firstKeyboardEventReplayed: Bool
        let markedTextActive: Bool
        let compositionEventPassedThrough: Bool
        let adaptiveWidthExpanded: Bool
        let longChineseQueryFits: Bool
    }

    private struct TranslationBoardResult: Codable {
        let phase: String
        let success: Bool
        let shortcutOpenedBoard: Bool
        let shortcutClosedBoard: Bool
        let boardRendered: Bool
        let previewContentRendered: Bool
        let popoverPresented: Bool
        let popoverAnchoredAboveCard: Bool
        let selectedSecondCard: Bool
        let processingIndicatorRenderedOnSelectedCard: Bool
        let processingIndicatorClearedAfterResult: Bool
        let popoverExpandedForLongResult: Bool
        let resultCopied: Bool
        let translationShortcut: String
    }

    private struct TranslationSettingsResult: Codable {
        let phase: String
        let success: Bool
        let settingsWindowPresented: Bool
        let selectAllShortcutWorked: Bool
        let copyShortcutWorked: Bool
        let pasteShortcutWorked: Bool
        let cutShortcutWorked: Bool
        let commandWClosedWindow: Bool
        let apiKeyCopyMarkedConcealed: Bool
        let apiKeyExcludedFromHistory: Bool
        let apiKeyPasteMarkedConcealed: Bool
        let apiKeyPasteExcludedFromHistory: Bool
        let modelIDCopyWorked: Bool
        let modelIDPasteWorked: Bool
        let pasteboardRestored: Bool
        let appleLanguagePackSettingsRendered: Bool
    }

    private struct ExplanationBoardResult: Codable {
        let phase: String
        let success: Bool
        let shortcutOpenedBoard: Bool
        let shortcutClosedBoard: Bool
        let boardRendered: Bool
        let previewContentRendered: Bool
        let popoverPresented: Bool
        let popoverAnchoredAboveCard: Bool
        let selectedSecondCard: Bool
        let processingIndicatorRenderedOnSelectedCard: Bool
        let processingIndicatorClearedAfterResult: Bool
        let resultCopied: Bool
        let explanationShortcut: String
    }

    private struct ExplanationLiveResult: Codable {
        let phase: String
        let success: Bool
        let configurationPresent: Bool
        let state: String
        let provider: String
        let explanationLength: Int
        /// Provider/UI error metadata only. Never contains a clipboard value or model answer.
        let failureReason: String?
    }

    private struct DoubaoLiveTranslationResult: Codable {
        let phase: String
        let success: Bool
        let serviceSelected: Bool
        let configurationPresent: Bool
        let state: String
        let provider: String
        let translationLength: Int
        /// A provider/UI error only; the synthetic source text and translated text are never logged.
        let failureReason: String?
    }

    private struct DoubaoPromptDiagnosticResult: Codable {
        let phase: String
        let success: Bool
        let configurationPresent: Bool
        let httpStatus: Int?
        let requestBody: String?
        let responseBody: String?
        let failureReason: String?
    }

    private struct PreviewResult: Codable {
        let phase: String
        let success: Bool
        let textObservedIndex: Int?
        let textObservedKind: String?
        let textObservedCharacterCount: Int
        let richTextRendered: Bool
        let fileObservedIndex: Int?
        let fileObservedKind: String?
        let textPreviewWithinScreen: Bool
        let richTextPreviewWithinScreen: Bool
        let imagePreviewWithinScreen: Bool
        let filePreviewWithinScreen: Bool
        let previewAvoidedSelectedCards: Bool
        let arrowTrackedSelection: Bool
        let titleHeaderRemoved: Bool
        let translucentBackground: Bool
        let spaceOpenedPreview: Bool
        let textWasComplete: Bool
        let longTextNeededVerticalScrolling: Bool
        let previewStayedWithinScreen: Bool
        let rightArrowConsumed: Bool
        let imageSelectionUpdatedPreview: Bool
        let imageDecoded: Bool
        let imageDecodeStayedBounded: Bool
        let fileSelectionUpdatedPreview: Bool
        let quickLookURLMatched: Bool
        let escapeClosedPreview: Bool
        let spaceReopenedPreview: Bool
        let secondSpaceClosedPreview: Bool
        let printableKeyClosedPreview: Bool
        let printableKeyActivatedSearch: Bool
        let contentIndexRebuildCount: Int
        let maximumContentIndexRebuildCount: Int
    }

    private struct QuickPasteResult: Codable {
        let phase: String
        let success: Bool
        let accessibilityTrusted: Bool
        let expectedLength: Int
        let promotedToFront: Bool
        let returnedToTarget: Bool
        let targetBundleID: String
    }

    static func start(controller: AppController) {
        let environment = ProcessInfo.processInfo.environment
        let phase = environment["PESTY_AUTOMATED_UI_TEST"] ?? "verify"
        let runID = environment["PESTY_AUTOMATED_TEST_ID"] ?? "default"
        if phase == "quick-paste" {
            verifyQuickPaste(controller: controller, phase: phase)
            return
        }
        if phase == "performance" {
            runPerformanceTest(controller: controller, runID: runID)
            return
        }
        if phase == "mouse-selection" {
            runMouseSelectionTest(controller: controller, runID: runID)
            return
        }
        if phase == "keyboard-delete" {
            runKeyboardDeleteTest(controller: controller, runID: runID)
            return
        }
        if phase == "retention-delay" {
            runRetentionDelayTest(controller: controller, runID: runID)
            return
        }
        if phase == "retention-restart-seed" {
            seedRetentionRestartTest(controller: controller, runID: runID)
            return
        }
        if phase == "retention-restart-verify" {
            verifyRetentionRestartTest(controller: controller)
            return
        }
        if phase == "retention-sync-seed" {
            seedRetentionSyncTest(controller: controller, runID: runID)
            return
        }
        if phase == "retention-sync-verify" {
            verifyRetentionSyncTest(controller: controller)
            return
        }
        if phase == "clear-confirmation" {
            runClearConfirmationTest(controller: controller, runID: runID)
            return
        }
        if phase == "deletion-sync-seed" {
            seedDeletionSyncTest(controller: controller, runID: runID)
            return
        }
        if phase == "deletion-sync-restart-1" {
            verifyDeletionSyncRestart(
                controller: controller,
                runID: runID,
                phase: phase,
                allowRecopy: false
            )
            return
        }
        if phase == "deletion-sync-restart-2" {
            verifyDeletionSyncRestart(
                controller: controller,
                runID: runID,
                phase: phase,
                allowRecopy: true
            )
            return
        }
        if phase == "search-input" {
            runSearchInputTest(controller: controller)
            return
        }
        if phase == "translation-board" {
            runTranslationBoardTest(controller: controller)
            return
        }
        if phase == "explanation-board" {
            runExplanationBoardTest(controller: controller)
            return
        }
        if phase == "translation-settings" {
            runTranslationSettingsTest(controller: controller)
            return
        }
        if phase == "doubao-live" {
            runDoubaoLiveTranslationTest(controller: controller)
            return
        }
        if phase == "explanation-live" {
            runLiveExplanationTest(controller: controller)
            return
        }
        if phase == "doubao-prompt-diagnosis" {
            runDoubaoPromptDiagnostic(controller: controller)
            return
        }
        if phase == "preview" {
            runPreviewTest(controller: controller, runID: runID)
            return
        }
        let expected = (1...4).map { "pesty-auto-\(runID)-\($0)" }

        AutomatedUITestProbe.reset()
        if phase == "seed" {
            seed(expected, controller: controller, phase: phase)
        } else {
            showAndVerify(expected, controller: controller, phase: phase, originalItems: nil)
        }
    }

    private static func verifyQuickPaste(
        controller: AppController,
        phase: String
    ) {
        let pasteboardText = NSPasteboard.general.string(forType: .string) ?? ""
        let requestedTargetBundleID = ProcessInfo.processInfo.environment[
            "PESTY_AUTOMATED_TARGET_BUNDLE_ID"
        ]
        let target = requestedTargetBundleID.flatMap {
            NSRunningApplication.runningApplications(withBundleIdentifier: $0).first
        } ?? NSWorkspace.shared.frontmostApplication
        let targetBundleID = target?.bundleIdentifier ?? ""
        guard !pasteboardText.isEmpty,
              targetBundleID != Bundle.main.bundleIdentifier,
              let item = controller.store.history.first(where: { $0.text == pasteboardText })
        else {
            writeQuickPaste(QuickPasteResult(
                phase: phase,
                success: false,
                accessibilityTrusted: accessibilityIsTrusted,
                expectedLength: pasteboardText.count,
                promotedToFront: false,
                returnedToTarget: false,
                targetBundleID: targetBundleID
            ))
            exit(EXIT_FAILURE)
        }

        controller.showBar()
        if let target {
            controller.setPasteTargetForAutomatedTest(target)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            controller.quickPasteItem(item)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            let promoted = controller.store.history.first?.id == item.id
            let returned = NSWorkspace.shared.frontmostApplication?.processIdentifier
                == target?.processIdentifier
            let success = promoted && returned && accessibilityIsTrusted
            controller.store.saveNow()
            writeQuickPaste(QuickPasteResult(
                phase: phase,
                success: success,
                accessibilityTrusted: accessibilityIsTrusted,
                expectedLength: pasteboardText.count,
                promotedToFront: promoted,
                returnedToTarget: returned,
                targetBundleID: targetBundleID
            ))
            exit(success ? EXIT_SUCCESS : EXIT_FAILURE)
        }
    }

    private static var accessibilityIsTrusted: Bool {
        #if MAS
        false
        #else
        PasteService.ensureAccessibility(prompt: false)
        #endif
    }

    private static func runSearchInputTest(controller: AppController) {
        controller.monitor.stop()
        controller.showBar()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let barWindow = NSApp.windows.first(where: { $0 is BarPanel })
            if let barWindow {
                NSApp.activate(ignoringOtherApps: true)
                barWindow.makeKeyAndOrderFront(nil)
            }
            let focusEvent = makeKeyEvent(
                keyCode: UInt16(kVK_ANSI_A),
                characters: "a",
                windowNumber: barWindow?.windowNumber ?? 0
            )
            let firstEventConsumedForReplay = focusEvent.map {
                controller.handleKey($0) == nil
            } ?? false

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let textFieldCount = descendantViews(
                    of: barWindow?.contentView
                ).compactMap { $0 as? NSTextField }.count
                let editor = barWindow?.firstResponder as? NSTextView
                let firstKeyboardEventReplayed =
                    firstEventConsumedForReplay && controller.store.searchText == "a"
                controller.store.searchText = ""
                editor?.setMarkedText(
                    "中文",
                    selectedRange: NSRange(location: 2, length: 0),
                    replacementRange: NSRange(location: NSNotFound, length: 0)
                )
                let markedTextActive = editor?.hasMarkedText() == true
                let event = makeKeyEvent(
                    keyCode: UInt16(kVK_LeftArrow),
                    characters: "\u{F702}",
                    windowNumber: barWindow?.windowNumber ?? 0
                )
                let returnedEvent = event.flatMap { controller.handleKey($0) }
                let compositionEventPassedThrough =
                    event != nil && returnedEvent === event
                editor?.unmarkText()
                let longChineseQuery = "这是一个用于验证中文输入法组合输入的完整搜索字符串"
                let shortWidth = SearchFieldLayout.width(for: "中")
                let longWidth = SearchFieldLayout.width(for: longChineseQuery)
                let adaptiveWidthExpanded = longWidth > shortWidth
                let longChineseQueryFits =
                    longWidth >= SearchFieldLayout.requiredWidth(for: longChineseQuery)

                let result = SearchInputResult(
                    phase: "search-input",
                    success: editor != nil
                        && firstKeyboardEventReplayed
                        && markedTextActive
                        && compositionEventPassedThrough
                        && adaptiveWidthExpanded
                        && longChineseQueryFits,
                    searchFieldActivated: controller.store.isSearchFieldActive,
                    nativeTextFieldCount: textFieldCount,
                    nativeTextEditorFocused: editor != nil,
                    firstKeyboardEventReplayed: firstKeyboardEventReplayed,
                    markedTextActive: markedTextActive,
                    compositionEventPassedThrough: compositionEventPassedThrough,
                    adaptiveWidthExpanded: adaptiveWidthExpanded,
                    longChineseQueryFits: longChineseQueryFits
                )
                writeSearchInput(result)
                exit(result.success ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }
    }

    private static func runTranslationBoardTest(controller: AppController) {
        let items = [
            ClipItem(
                type: .text,
                text: "Pesty translation board first card",
                createdAt: Date()
            ),
            ClipItem(
                type: .text,
                text: "Pesty translation board selected card",
                createdAt: Date().addingTimeInterval(-1)
            ),
        ]
        let item = items[1]
        let translationPreview = String(
            repeating: "自适应高度会优先完整展示翻译结果，达到阅读上限后才滚动。",
            count: 24
        )
        controller.monitor.stop()
        controller.store.replaceHistoryForAutomatedKeyboardTest(items)
        Settings.shared.translationService = .doubao
        AutomatedUITestProbe.reset()
        controller.showBar()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let translationEvent = makeKeyEvent(
                keyCode: UInt16(TranslationShortcut.defaultKeyCode),
                characters: "t",
                modifierFlags: [.command]
            )
            let shortcutWasConsumed = translationEvent.map {
                controller.handleKey($0) == nil
            } ?? false
            let shortcutOpenedBoard = shortcutWasConsumed
                && TranslationCenter.shared.isPresented

            let secondTranslationEvent = makeKeyEvent(
                keyCode: UInt16(TranslationShortcut.defaultKeyCode),
                characters: "t",
                modifierFlags: [.command]
            )
            let shortcutClosedBoard = (secondTranslationEvent.map {
                controller.handleKey($0) == nil
            } ?? false) && !TranslationCenter.shared.isPresented

            controller.store.selectedID = item.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                let selectedSecondCard = controller.store.selectedID == item.id
                TranslationCenter.shared.showAutomatedProcessing(for: item)
                controller.presentAssistantPopoverForAutomatedTest(
                    kind: .translation,
                    item: item
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    let processingIndicatorRendered =
                        AutomatedUITestProbe.assistantProcessingItemIDs.contains(
                            item.id
                        )
                    TranslationCenter.shared.showAutomatedPreview(
                        source: item.text ?? "",
                        translation: translationPreview,
                        itemID: item.id
                    )
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        let resultPasteboard = NSPasteboard(
                            name: NSPasteboard.Name(
                                "com.bifrostproxy.pesty.translation-board-test"
                            )
                        )
                        let resultCopied = TranslationCenter.shared.copyResult(
                            to: resultPasteboard
                        ) && resultPasteboard.string(forType: .string)
                            == translationPreview
                        let boardRendered =
                            AutomatedUITestProbe.translationBoardRendered
                        let previewContentRendered =
                            TranslationCenter.shared.status == .translated
                            && TranslationCenter.shared.translatedText
                                == translationPreview
                            && AutomatedUITestProbe.translationPreviewRendered
                        let popoverPresented =
                            AssistantPopoverController.shared.isPresented
                        let popoverAnchoredAboveCard =
                            isAssistantPopoverAnchoredAboveCard(item.id)
                        let processingIndicatorCleared =
                            !AutomatedUITestProbe.assistantProcessingItemIDs
                                .contains(item.id)
                        let popoverExpandedForLongResult =
                            (AssistantPopoverController.shared.screenFrame?.height
                                ?? 0)
                            > AssistantPopoverLayout.translationDefaultHeight
                        let result = TranslationBoardResult(
                            phase: "translation-board",
                            success: shortcutOpenedBoard
                                && shortcutClosedBoard
                                && selectedSecondCard
                                && processingIndicatorRendered
                                && processingIndicatorCleared
                                && boardRendered
                                && previewContentRendered
                                && popoverPresented
                                && popoverAnchoredAboveCard
                                && popoverExpandedForLongResult
                                && resultCopied,
                            shortcutOpenedBoard: shortcutOpenedBoard,
                            shortcutClosedBoard: shortcutClosedBoard,
                            boardRendered: boardRendered,
                            previewContentRendered: previewContentRendered,
                            popoverPresented: popoverPresented,
                            popoverAnchoredAboveCard: popoverAnchoredAboveCard,
                            selectedSecondCard: selectedSecondCard,
                            processingIndicatorRenderedOnSelectedCard:
                                processingIndicatorRendered,
                            processingIndicatorClearedAfterResult:
                                processingIndicatorCleared,
                            popoverExpandedForLongResult:
                                popoverExpandedForLongResult,
                            resultCopied: resultCopied,
                            translationShortcut:
                                Settings.shared.translationHotkeyDisplay
                        )
                        captureKeyWindowScreenshotIfRequested()
                        writeTranslationBoard(result)
                        let exitCode = result.success
                            ? EXIT_SUCCESS
                            : EXIT_FAILURE
                        let holdSeconds = TimeInterval(
                            ProcessInfo.processInfo.environment[
                                "PESTY_AUTOMATED_TEST_HOLD_SECONDS"
                            ] ?? ""
                        ) ?? 0
                        guard holdSeconds > 0 else {
                            controller.hideBar()
                            exit(exitCode)
                        }
                        DispatchQueue.main.asyncAfter(
                            deadline: .now() + holdSeconds
                        ) {
                            controller.hideBar()
                            exit(exitCode)
                        }
                    }
                }
            }
        }
    }

    private static func runTranslationSettingsTest(controller: AppController) {
        controller.monitor.stop()
        AutomatedUITestProbe.reset()
        let pasteboardItems = snapshot(.general)
        controller.showSettings(pane: .translation)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            let settingsWindow = visibleContentWindow()
            let settingsWindowPresented = settingsWindow != nil
            let fields = descendantViews(of: settingsWindow?.contentView)
                .compactMap { $0 as? NSTextField }
                .filter(\.isEditable)
            let apiKeyField = fields.first(where: {
                $0 is NSSecureTextField
            })
            let modelIDField = fields.first(where: {
                !($0 is NSSecureTextField)
            })
            let apiKeySource = "pesty-settings-api-key"
            let apiKeyPaste = "pesty-settings-api-key-paste"
            let modelIDSource = "pesty-settings-model-id"
            let modelIDPaste = "pesty-settings-model-id-paste"
            settingsWindow?.makeKeyAndOrderFront(nil)

            let apiKeyEditing = verifySettingsFieldEditing(
                field: apiKeyField,
                sourceText: apiKeySource,
                pasteText: apiKeyPaste,
                window: settingsWindow,
                controller: controller,
                shouldPollClipboardMonitor: true
            )
            let modelIDEditing = verifySettingsFieldEditing(
                field: modelIDField,
                sourceText: modelIDSource,
                pasteText: modelIDPaste,
                window: settingsWindow,
                controller: controller,
                shouldPollClipboardMonitor: false
            )
            restore(pasteboardItems, to: .general)
            let pasteboardRestored = snapshot(.general) == pasteboardItems
            let languagePackSettingsExpected =
                Settings.shared.translationService == .apple
            let languagePackSettingsRendered =
                AutomatedUITestProbe.appleLanguagePackSettingsRendered

            @MainActor
            func finish() {
                captureKeyWindowScreenshotIfRequested()
                let closeHandled = makeKeyEvent(
                    keyCode: UInt16(kVK_ANSI_W),
                    characters: "w",
                    modifierFlags: [.command],
                    windowNumber: settingsWindow?.windowNumber ?? 0
                ).map {
                    controller.handleKey($0) == nil
                } ?? false
                let commandWClosedWindow = closeHandled
                    && settingsWindow?.isVisible == false
                let result = TranslationSettingsResult(
                    phase: "translation-settings",
                    success: settingsWindowPresented
                        && apiKeyEditing.selectAll
                        && apiKeyEditing.copy
                        && apiKeyEditing.paste
                        && apiKeyEditing.copyMarkedConcealed
                        && apiKeyEditing.excludedFromHistory
                        && apiKeyEditing.pasteMarkedConcealed
                        && apiKeyEditing.pasteExcludedFromHistory
                        && modelIDEditing.copy
                        && modelIDEditing.paste
                        && modelIDEditing.cut
                        && commandWClosedWindow
                        && pasteboardRestored
                        && (
                            !languagePackSettingsExpected
                            || languagePackSettingsRendered
                        ),
                    settingsWindowPresented: settingsWindowPresented,
                    selectAllShortcutWorked: apiKeyEditing.selectAll,
                    copyShortcutWorked: apiKeyEditing.copy,
                    pasteShortcutWorked: apiKeyEditing.paste,
                    cutShortcutWorked: modelIDEditing.cut,
                    commandWClosedWindow: commandWClosedWindow,
                    apiKeyCopyMarkedConcealed:
                        apiKeyEditing.copyMarkedConcealed,
                    apiKeyExcludedFromHistory:
                        apiKeyEditing.excludedFromHistory,
                    apiKeyPasteMarkedConcealed:
                        apiKeyEditing.pasteMarkedConcealed,
                    apiKeyPasteExcludedFromHistory:
                        apiKeyEditing.pasteExcludedFromHistory,
                    modelIDCopyWorked: modelIDEditing.copy,
                    modelIDPasteWorked: modelIDEditing.paste,
                    pasteboardRestored: pasteboardRestored,
                    appleLanguagePackSettingsRendered:
                        languagePackSettingsRendered
                )
                writeTranslationSettings(result)
                settingsWindow?.orderOut(nil)
                exit(result.success ? EXIT_SUCCESS : EXIT_FAILURE)
            }

            let holdSeconds = TimeInterval(
                ProcessInfo.processInfo.environment[
                    "PESTY_AUTOMATED_TEST_HOLD_SECONDS"
                ] ?? ""
            ) ?? 0
            guard holdSeconds > 0 else {
                finish()
                return
            }
            DispatchQueue.main.asyncAfter(
                deadline: .now() + holdSeconds
            ) {
                finish()
            }
        }
    }

    private static func verifySettingsFieldEditing(
        field: NSTextField?,
        sourceText: String,
        pasteText: String,
        window: NSWindow?,
        controller: AppController,
        shouldPollClipboardMonitor: Bool
    ) -> (
        selectAll: Bool,
        copy: Bool,
        paste: Bool,
        cut: Bool,
        copyMarkedConcealed: Bool,
        excludedFromHistory: Bool,
        pasteMarkedConcealed: Bool,
        pasteExcludedFromHistory: Bool
    ) {
        guard let field, let window else {
            return (
                false, false, false, false,
                false, false, false, false
            )
        }
        field.stringValue = sourceText
        guard window.makeFirstResponder(field),
              let editor = field.currentEditor() as? NSTextView else {
            return (
                false, false, false, false,
                false, false, false, false
            )
        }
        editor.setSelectedRange(
            NSRange(location: sourceText.utf16.count, length: 0)
        )

        let selectAllHandled = performSettingsShortcut(
            keyCode: UInt16(kVK_ANSI_A),
            characters: "a",
            window: window,
            controller: controller
        )
        let selectAllWorked = selectAllHandled
            && editor.selectedRange()
                == NSRange(location: 0, length: sourceText.utf16.count)
        let historyCountBeforeCopy = controller.store.history.count
        let copyHandled = performSettingsShortcut(
            keyCode: UInt16(kVK_ANSI_C),
            characters: "c",
            window: window,
            controller: controller
        )
        let copyWorked = copyHandled
            && NSPasteboard.general.string(forType: .string) == sourceText
        let copyMarkedConcealed = !shouldPollClipboardMonitor
            || NSPasteboard.general.types?.contains(
                ClipboardMonitor.concealedPasteboardType
            ) == true
        if shouldPollClipboardMonitor {
            controller.monitor.pollNowForAutomatedTest()
        }
        let excludedFromHistory = !shouldPollClipboardMonitor
            || (
                controller.store.history.count == historyCountBeforeCopy
                && !controller.store.history.contains {
                    $0.text == sourceText
                }
            )

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pasteText, forType: .string)
        editor.setSelectedRange(
            NSRange(location: 0, length: editor.string.utf16.count)
        )
        let pasteHandled = performSettingsShortcut(
            keyCode: UInt16(kVK_ANSI_V),
            characters: "v",
            window: window,
            controller: controller
        )
        let editedText = field.currentEditor()?.string ?? field.stringValue
        let pasteWorked = pasteHandled
            && editedText == pasteText
            && NSPasteboard.general.string(forType: .string) == pasteText
        let pasteMarkedConcealed = !shouldPollClipboardMonitor
            || NSPasteboard.general.types?.contains(
                ClipboardMonitor.concealedPasteboardType
            ) == true
        if shouldPollClipboardMonitor {
            controller.monitor.pollNowForAutomatedTest()
        }
        let pasteExcludedFromHistory = !shouldPollClipboardMonitor
            || (
                controller.store.history.count == historyCountBeforeCopy
                && !controller.store.history.contains {
                    $0.text == pasteText
                }
            )

        editor.setSelectedRange(
            NSRange(location: 0, length: pasteText.utf16.count)
        )
        let cutHandled = performSettingsShortcut(
            keyCode: UInt16(kVK_ANSI_X),
            characters: "x",
            window: window,
            controller: controller
        )
        let cutWorked = shouldPollClipboardMonitor
            ? cutHandled && (field.currentEditor()?.string ?? field.stringValue)
                == pasteText
            : cutHandled
                && (field.currentEditor()?.string ?? field.stringValue).isEmpty
                && NSPasteboard.general.string(forType: .string) == pasteText
        return (
            selectAllWorked,
            copyWorked,
            pasteWorked,
            cutWorked,
            copyMarkedConcealed,
            excludedFromHistory,
            pasteMarkedConcealed,
            pasteExcludedFromHistory
        )
    }

    private static func performSettingsShortcut(
        keyCode: UInt16,
        characters: String,
        window: NSWindow,
        controller: AppController
    ) -> Bool {
        makeKeyEvent(
            keyCode: keyCode,
            characters: characters,
            modifierFlags: [.command],
            windowNumber: window.windowNumber
        ).map {
            controller.handleKey($0) == nil
        } ?? false
    }

    private static func runPreviewTest(
        controller: AppController,
        runID: String
    ) {
        guard let testBase = ClipboardStore.automatedTestBase,
              let imageData = makePreviewImageData(),
              let imageFileName = controller.store.storeImageData(imageData)
        else {
            writePreview(failedPreviewResult())
            exit(EXIT_FAILURE)
        }

        let longText = (0..<2_000)
            .map { "pesty-preview-\(runID)-line-\($0)" }
            .joined(separator: "\n")
        let richText = "Pesty rich text preview \(runID)"
        let richAttributed = NSAttributedString(
            string: richText,
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: 18),
                .foregroundColor: NSColor.systemBlue,
            ]
        )
        guard let richData = try? richAttributed.data(
            from: NSRange(location: 0, length: richAttributed.length),
            documentAttributes: [
                .documentType: NSAttributedString.DocumentType.rtf,
            ]
        ) else {
            writePreview(failedPreviewResult())
            exit(EXIT_FAILURE)
        }
        let fileURL = testBase.appendingPathComponent(
            "pesty-preview-\(runID).txt"
        )
        do {
            try Data("Pesty Quick Look preview fixture".utf8).write(
                to: fileURL,
                options: .atomic
            )
        } catch {
            writePreview(failedPreviewResult())
            exit(EXIT_FAILURE)
        }

        let items = [
            ClipItem(
                type: .text,
                text: longText,
                sourceBundleID: "com.bifrostproxy.pesty.preview-test",
                sourceAppName: "Pesty Preview Test",
                createdAt: Date()
            ),
            ClipItem(
                type: .richText,
                text: richText,
                rtfData: richData,
                sourceBundleID: "com.bifrostproxy.pesty.preview-test",
                sourceAppName: "Pesty Preview Test",
                createdAt: Date(timeIntervalSinceNow: -1)
            ),
            ClipItem(
                type: .image,
                imageFileName: imageFileName,
                imageHash: "pesty-preview-image-\(runID)",
                sourceBundleID: "com.bifrostproxy.pesty.preview-test",
                sourceAppName: "Pesty Preview Test",
                createdAt: Date(timeIntervalSinceNow: -2)
            ),
            ClipItem(
                type: .file,
                text: fileURL.lastPathComponent,
                fileURLs: [fileURL.absoluteString],
                sourceBundleID: "com.bifrostproxy.pesty.preview-test",
                sourceAppName: "Pesty Preview Test",
                createdAt: Date(timeIntervalSinceNow: -3)
            ),
        ]

        controller.monitor.stop()
        AutomatedUITestProbe.reset()
        VirtualizedClipStripMetrics.reset()
        controller.store.replaceHistoryForAutomatedStripTest(items)
        controller.showBar()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)

            let space = makeKeyEvent(
                keyCode: UInt16(kVK_Space),
                characters: " "
            )
            let spaceConsumed = space.map {
                controller.handleKey($0) == nil
            } ?? false
            try? await Task.sleep(nanoseconds: 250_000_000)

            let textSnapshot =
                ClipPreviewWindowController.shared.automationSnapshot()
            let spaceOpenedPreview =
                spaceConsumed
                && textSnapshot.isVisible
                && textSnapshot.itemID == items[0].id
                && textSnapshot.contentKind == .text
            let textWasComplete =
                textSnapshot.textCharacterCount == longText.count
            let longTextNeededVerticalScrolling =
                textSnapshot.textNeedsVerticalScrolling
            let textPreviewWithinScreen =
                previewSnapshotIsWithinScreen(textSnapshot)

            let right = makeKeyEvent(
                keyCode: UInt16(kVK_RightArrow),
                characters: "\u{F703}"
            )
            let firstRightConsumed = right.map {
                controller.handleKey($0) == nil
            } ?? false
            try? await Task.sleep(nanoseconds: 300_000_000)

            let richTextSnapshot =
                ClipPreviewWindowController.shared.automationSnapshot()
            let richTextRendered =
                richTextSnapshot.isVisible
                && richTextSnapshot.itemID == items[1].id
                && richTextSnapshot.contentKind == .text
                && richTextSnapshot.textCharacterCount == richText.count
            let richTextPreviewWithinScreen =
                previewSnapshotIsWithinScreen(richTextSnapshot)

            let secondRightConsumed = right.map {
                controller.handleKey($0) == nil
            } ?? false
            try? await Task.sleep(nanoseconds: 700_000_000)

            let imageSnapshot =
                ClipPreviewWindowController.shared.automationSnapshot()
            let imagePreviewWithinScreen =
                previewSnapshotIsWithinScreen(imageSnapshot)
            let imageSelectionUpdatedPreview =
                imageSnapshot.isVisible
                && imageSnapshot.itemID == items[2].id
                && imageSnapshot.contentKind == .image
            let imageDecoded =
                imageSnapshot.imageSourcePixelSize != nil
                && imageSnapshot.imageDecodedPixelSize != nil
            let imageDecodeStayedBounded: Bool
            if let source = imageSnapshot.imageSourcePixelSize,
               let decoded = imageSnapshot.imageDecodedPixelSize {
                imageDecodeStayedBounded =
                    decoded.width <= source.width
                    && decoded.height <= source.height
                    && (decoded.width < source.width
                        || decoded.height < source.height)
                    && decoded.width <= 2_048
                    && decoded.height <= 2_048
            } else {
                imageDecodeStayedBounded = false
            }

            let thirdRightConsumed = right.map {
                controller.handleKey($0) == nil
            } ?? false
            try? await Task.sleep(nanoseconds: 500_000_000)

            let fileSnapshot =
                ClipPreviewWindowController.shared.automationSnapshot()
            let filePreviewWithinScreen =
                previewSnapshotIsWithinScreen(fileSnapshot)
            let previewSnapshots = [
                textSnapshot,
                richTextSnapshot,
                imageSnapshot,
                fileSnapshot,
            ]
            let previewAvoidedSelectedCards =
                previewSnapshots.allSatisfy(
                    previewSnapshotAvoidsSelectedCard
                )
            let arrowTrackedSelection =
                previewSnapshots.allSatisfy(
                    previewSnapshotArrowPointsToSelectedCard
                )
            let titleHeaderRemoved =
                previewSnapshots.allSatisfy { !$0.hasTitleHeader }
            let translucentBackground =
                previewSnapshots.allSatisfy(\.usesTranslucentBackground)
            let previewStayedWithinScreen =
                textPreviewWithinScreen
                && richTextPreviewWithinScreen
                && imagePreviewWithinScreen
                && filePreviewWithinScreen
            let fileSelectionUpdatedPreview =
                fileSnapshot.isVisible
                && fileSnapshot.itemID == items[3].id
                && fileSnapshot.contentKind == .quickLook
            let quickLookURLMatched =
                fileSnapshot.quickLookURL?.standardizedFileURL
                == fileURL.standardizedFileURL

            let escape = makeKeyEvent(
                keyCode: UInt16(kVK_Escape),
                characters: "\u{1B}"
            )
            let escapeConsumed = escape.map {
                controller.handleKey($0) == nil
            } ?? false
            let escapeClosedPreview =
                escapeConsumed
                && !ClipPreviewWindowController.shared.isVisible

            _ = space.map { controller.handleKey($0) }
            try? await Task.sleep(nanoseconds: 150_000_000)
            let spaceReopenedPreview =
                ClipPreviewWindowController.shared.isVisible
            _ = space.map { controller.handleKey($0) }
            let secondSpaceClosedPreview =
                !ClipPreviewWindowController.shared.isVisible

            let contentIndexRebuildCount =
                VirtualizedClipStripMetrics.contentIndexRebuildCount
            _ = space.map { controller.handleKey($0) }
            let printable = makeKeyEvent(
                keyCode: UInt16(kVK_ANSI_A),
                characters: "a"
            )
            let printableConsumed = printable.map {
                controller.handleKey($0) == nil
            } ?? false
            let printableKeyClosedPreview =
                printableConsumed
                && !ClipPreviewWindowController.shared.isVisible
            try? await Task.sleep(nanoseconds: 300_000_000)
            let printableKeyActivatedSearch =
                controller.store.searchText == "a"
                && controller.store.isSearchFieldActive

            let maximumContentIndexRebuildCount = 1
            let rightArrowConsumed =
                firstRightConsumed
                && secondRightConsumed
                && thirdRightConsumed
            let result = PreviewResult(
                phase: "preview",
                success:
                    spaceOpenedPreview
                    && textWasComplete
                    && longTextNeededVerticalScrolling
                    && richTextRendered
                    && previewStayedWithinScreen
                    && previewAvoidedSelectedCards
                    && arrowTrackedSelection
                    && titleHeaderRemoved
                    && translucentBackground
                    && rightArrowConsumed
                    && imageSelectionUpdatedPreview
                    && imageDecoded
                    && imageDecodeStayedBounded
                    && fileSelectionUpdatedPreview
                    && quickLookURLMatched
                    && escapeClosedPreview
                    && spaceReopenedPreview
                    && secondSpaceClosedPreview
                    && printableKeyClosedPreview
                    && printableKeyActivatedSearch
                    && contentIndexRebuildCount
                        <= maximumContentIndexRebuildCount,
                textObservedIndex: textSnapshot.itemID.flatMap {
                    id in items.firstIndex(where: { $0.id == id })
                },
                textObservedKind: textSnapshot.contentKind?.rawValue,
                textObservedCharacterCount:
                    textSnapshot.textCharacterCount,
                richTextRendered: richTextRendered,
                fileObservedIndex: fileSnapshot.itemID.flatMap {
                    id in items.firstIndex(where: { $0.id == id })
                },
                fileObservedKind: fileSnapshot.contentKind?.rawValue,
                textPreviewWithinScreen: textPreviewWithinScreen,
                richTextPreviewWithinScreen:
                    richTextPreviewWithinScreen,
                imagePreviewWithinScreen: imagePreviewWithinScreen,
                filePreviewWithinScreen: filePreviewWithinScreen,
                previewAvoidedSelectedCards:
                    previewAvoidedSelectedCards,
                arrowTrackedSelection: arrowTrackedSelection,
                titleHeaderRemoved: titleHeaderRemoved,
                translucentBackground: translucentBackground,
                spaceOpenedPreview: spaceOpenedPreview,
                textWasComplete: textWasComplete,
                longTextNeededVerticalScrolling:
                    longTextNeededVerticalScrolling,
                previewStayedWithinScreen: previewStayedWithinScreen,
                rightArrowConsumed: rightArrowConsumed,
                imageSelectionUpdatedPreview:
                    imageSelectionUpdatedPreview,
                imageDecoded: imageDecoded,
                imageDecodeStayedBounded: imageDecodeStayedBounded,
                fileSelectionUpdatedPreview:
                    fileSelectionUpdatedPreview,
                quickLookURLMatched: quickLookURLMatched,
                escapeClosedPreview: escapeClosedPreview,
                spaceReopenedPreview: spaceReopenedPreview,
                secondSpaceClosedPreview: secondSpaceClosedPreview,
                printableKeyClosedPreview: printableKeyClosedPreview,
                printableKeyActivatedSearch: printableKeyActivatedSearch,
                contentIndexRebuildCount: contentIndexRebuildCount,
                maximumContentIndexRebuildCount:
                    maximumContentIndexRebuildCount
            )
            controller.closePreview()
            controller.store.saveNow()
            writePreview(result)
            exit(result.success ? EXIT_SUCCESS : EXIT_FAILURE)
        }
    }

    private static func runExplanationBoardTest(controller: AppController) {
        let items = [
            ClipItem(
                type: .text,
                text: "Pesty explanation board first card",
                createdAt: Date()
            ),
            ClipItem(
                type: .text,
                text: "Pesty explanation board selected card",
                createdAt: Date().addingTimeInterval(-1)
            ),
        ]
        let item = items[1]
        controller.monitor.stop()
        controller.store.replaceHistoryForAutomatedKeyboardTest(items)
        AutomatedUITestProbe.reset()
        controller.showBar()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let explanationEvent = makeKeyEvent(
                keyCode: UInt16(ExplanationShortcut.defaultKeyCode),
                characters: "d",
                modifierFlags: [.command]
            )
            let shortcutOpenedBoard = (explanationEvent.map {
                controller.handleKey($0) == nil
            } ?? false) && ExplanationCenter.shared.isPresented

            let secondExplanationEvent = makeKeyEvent(
                keyCode: UInt16(ExplanationShortcut.defaultKeyCode),
                characters: "d",
                modifierFlags: [.command]
            )
            let shortcutClosedBoard = (secondExplanationEvent.map {
                controller.handleKey($0) == nil
            } ?? false) && !ExplanationCenter.shared.isPresented

            controller.store.selectedID = item.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                let selectedSecondCard = controller.store.selectedID == item.id
                ExplanationCenter.shared.showAutomatedProcessing(for: item)
                controller.presentAssistantPopoverForAutomatedTest(
                    kind: .explanation,
                    item: item
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    let processingIndicatorRendered =
                        AutomatedUITestProbe.assistantProcessingItemIDs.contains(
                            item.id
                        )
                    let markdownPreview = """
                    **核心含义：** 解释结果现在使用 Markdown 排版。

                    - 支持 `行内代码` 与粗体
                    - 列表更紧凑，减少滚动
                    """
                    ExplanationCenter.shared.showAutomatedPreview(
                        source: item.text ?? "",
                        explanation: markdownPreview,
                        itemID: item.id
                    )
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        let resultPasteboard = NSPasteboard(
                            name: NSPasteboard.Name(
                                "com.bifrostproxy.pesty.explanation-board-test"
                            )
                        )
                        let resultCopied = ExplanationCenter.shared.copyResult(
                            to: resultPasteboard
                        ) && resultPasteboard.string(forType: .string)
                            == markdownPreview
                        let boardRendered =
                            AutomatedUITestProbe.explanationBoardRendered
                        let previewContentRendered =
                            ExplanationCenter.shared.status == .explained
                            && ExplanationCenter.shared.explanationText
                                == markdownPreview
                            && AutomatedUITestProbe.explanationPreviewRendered
                        let popoverPresented =
                            AssistantPopoverController.shared.isPresented
                        let popoverAnchoredAboveCard =
                            isAssistantPopoverAnchoredAboveCard(item.id)
                        let processingIndicatorCleared =
                            !AutomatedUITestProbe.assistantProcessingItemIDs
                                .contains(item.id)
                        let result = ExplanationBoardResult(
                            phase: "explanation-board",
                            success: shortcutOpenedBoard
                                && shortcutClosedBoard
                                && selectedSecondCard
                                && processingIndicatorRendered
                                && processingIndicatorCleared
                                && boardRendered
                                && previewContentRendered
                                && popoverPresented
                                && popoverAnchoredAboveCard
                                && resultCopied,
                            shortcutOpenedBoard: shortcutOpenedBoard,
                            shortcutClosedBoard: shortcutClosedBoard,
                            boardRendered: boardRendered,
                            previewContentRendered: previewContentRendered,
                            popoverPresented: popoverPresented,
                            popoverAnchoredAboveCard: popoverAnchoredAboveCard,
                            selectedSecondCard: selectedSecondCard,
                            processingIndicatorRenderedOnSelectedCard:
                                processingIndicatorRendered,
                            processingIndicatorClearedAfterResult:
                                processingIndicatorCleared,
                            resultCopied: resultCopied,
                            explanationShortcut:
                                Settings.shared.explanationHotkeyDisplay
                        )
                        captureKeyWindowScreenshotIfRequested()
                        writeExplanationBoard(result)
                        let exitCode = result.success
                            ? EXIT_SUCCESS
                            : EXIT_FAILURE
                        let holdSeconds = TimeInterval(
                            ProcessInfo.processInfo.environment[
                                "PESTY_AUTOMATED_TEST_HOLD_SECONDS"
                            ] ?? ""
                        ) ?? 0
                        guard holdSeconds > 0 else {
                            controller.hideBar()
                            exit(exitCode)
                        }
                        DispatchQueue.main.asyncAfter(
                            deadline: .now() + holdSeconds
                        ) {
                            controller.hideBar()
                            exit(exitCode)
                        }
                    }
                }
            }
        }
    }

    /// Exercises Pesty's real translation path with a fixed synthetic string.
    /// This intentionally does not read, write, or persist clipboard contents.
    private static func runDoubaoLiveTranslationTest(controller: AppController) {
        controller.monitor.stop()
        let serviceSelected = Settings.shared.translationService == .doubao
        let configurationPresent = Settings.shared.doubaoTranslationConfigured
        let credentialReadState: String
        do {
            let apiKey = try SecureCredentialStore.read(account: "doubao-ark-api-key")
            credentialReadState = (apiKey?.isEmpty == false) ? "present" : "empty-or-missing"
        } catch let error as SecureCredentialStore.CredentialStoreError {
            credentialReadState = "keychain-status-\(error.status)"
        } catch {
            credentialReadState = "keychain-read-failed"
        }
        let modelPresent = !Settings.shared.doubaoTranslationModelID.isEmpty
        guard serviceSelected, configurationPresent else {
            writeDoubaoLiveTranslation(
                DoubaoLiveTranslationResult(
                    phase: "doubao-live",
                    success: false,
                    serviceSelected: serviceSelected,
                    configurationPresent: configurationPresent,
                    state: "not-configured",
                    provider: "",
                    translationLength: 0,
                    failureReason: "credential=\(credentialReadState), model=\(modelPresent)"
                )
            )
            exit(EXIT_FAILURE)
        }

        let item = ClipItem(
            type: .text,
            text: "Pesty live translation verification.",
            createdAt: Date()
        )
        TranslationCenter.shared.present(for: item)
        let deadline = Date().addingTimeInterval(35)

        func finish(
            success: Bool,
            state: String,
            translationLength: Int,
            failureReason: String? = nil
        ) {
            let result = DoubaoLiveTranslationResult(
                phase: "doubao-live",
                success: success,
                serviceSelected: serviceSelected,
                configurationPresent: configurationPresent,
                state: state,
                provider: TranslationCenter.shared.providerName,
                translationLength: translationLength,
                failureReason: failureReason
            )
            TranslationCenter.shared.dismiss()
            writeDoubaoLiveTranslation(result)
            exit(success ? EXIT_SUCCESS : EXIT_FAILURE)
        }

        func poll() {
            switch TranslationCenter.shared.status {
            case .translated:
                finish(
                    success: true,
                    state: "translated",
                    translationLength: TranslationCenter.shared.translatedText.count
                )
            case .failed(let message):
                finish(
                    success: false,
                    state: "failed",
                    translationLength: 0,
                    failureReason: TranslationCenter.shared.failureDiagnostic ?? message
                )
            case .unavailable(let message):
                finish(
                    success: false,
                    state: "unavailable",
                    translationLength: 0,
                    failureReason: message
                )
            case .idle:
                finish(success: false, state: "idle", translationLength: 0)
            case .checkingService, .translating:
                guard Date() < deadline else {
                    finish(success: false, state: "timeout", translationLength: 0)
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    poll()
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            poll()
        }
    }

    /// Exercises the exact explanation client with a fixed synthetic string.
    /// It never reads, writes, or persists a user's clipboard content.
    private static func runLiveExplanationTest(controller: AppController) {
        controller.monitor.stop()
        let configurationPresent = Settings.shared.explanationConfigured
        guard configurationPresent else {
            writeExplanationLive(ExplanationLiveResult(
                phase: "explanation-live",
                success: false,
                configurationPresent: false,
                state: "not-configured",
                provider: "",
                explanationLength: 0,
                failureReason: "no-configured-ai-provider"
            ))
            exit(EXIT_FAILURE)
        }

        let item = ClipItem(
            type: .text,
            text: "Pesty explanation verification: HTTP 429 means too many requests.",
            createdAt: Date()
        )
        ExplanationCenter.shared.present(for: item)
        let deadline = Date().addingTimeInterval(35)

        func finish(
            success: Bool,
            state: String,
            explanationLength: Int,
            failureReason: String? = nil
        ) {
            let result = ExplanationLiveResult(
                phase: "explanation-live",
                success: success,
                configurationPresent: configurationPresent,
                state: state,
                provider: ExplanationCenter.shared.providerName,
                explanationLength: explanationLength,
                failureReason: failureReason
            )
            ExplanationCenter.shared.dismiss()
            writeExplanationLive(result)
            exit(success ? EXIT_SUCCESS : EXIT_FAILURE)
        }

        func poll() {
            switch ExplanationCenter.shared.status {
            case .explained:
                finish(
                    success: true,
                    state: "explained",
                    explanationLength: ExplanationCenter.shared.explanationText.count
                )
            case .failed(let message):
                finish(
                    success: false,
                    state: "failed",
                    explanationLength: 0,
                    failureReason: ExplanationCenter.shared.failureDiagnostic ?? message
                )
            case .unavailable(let message):
                finish(
                    success: false,
                    state: "unavailable",
                    explanationLength: 0,
                    failureReason: message
                )
            case .idle:
                finish(success: false, state: "idle", explanationLength: 0)
            case .explaining:
                guard Date() < deadline else {
                    finish(success: false, state: "timeout", explanationLength: 0)
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    poll()
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            poll()
        }
    }

    /// Calls the exact production prompt with the fixed text from the reported failure.
    /// It never reads clipboard contents and never serializes the API key.
    private static func runDoubaoPromptDiagnostic(controller: AppController) {
        controller.monitor.stop()
        let configurationPresent = Settings.shared.doubaoTranslationConfigured
        guard configurationPresent,
              let apiKey = Settings.shared.doubaoTranslationAPIKey(),
              !apiKey.isEmpty else {
            writeDoubaoPromptDiagnostic(DoubaoPromptDiagnosticResult(
                phase: "doubao-prompt-diagnosis",
                success: false,
                configurationPresent: configurationPresent,
                httpStatus: nil,
                requestBody: nil,
                responseBody: nil,
                failureReason: "credentials-unavailable"
            ))
            exit(EXIT_FAILURE)
        }

        DoubaoTranslationClient.diagnosePrompt(
            text: "Evolving",
            source: .automatic,
            target: .simplifiedChinese,
            modelID: Settings.shared.doubaoTranslationModelID,
            apiKey: apiKey
        ) { result in
            switch result {
            case .success(let response):
                writeDoubaoPromptDiagnostic(DoubaoPromptDiagnosticResult(
                    phase: "doubao-prompt-diagnosis",
                    success: (200..<300).contains(response.statusCode),
                    configurationPresent: configurationPresent,
                    httpStatus: response.statusCode,
                    requestBody: response.requestBody,
                    responseBody: response.responseBody,
                    failureReason: nil
                ))
                exit((200..<300).contains(response.statusCode) ? EXIT_SUCCESS : EXIT_FAILURE)
            case .failure(let error):
                let diagnostic = error.localizedDescription
                writeDoubaoPromptDiagnostic(DoubaoPromptDiagnosticResult(
                    phase: "doubao-prompt-diagnosis",
                    success: false,
                    configurationPresent: configurationPresent,
                    httpStatus: nil,
                    requestBody: nil,
                    responseBody: nil,
                    failureReason: diagnostic
                ))
                exit(EXIT_FAILURE)
            }
        }
    }

    private static func previewSnapshotIsWithinScreen(
        _ snapshot: ClipPreviewAutomationSnapshot
    ) -> Bool {
        guard snapshot.isVisible,
              !snapshot.windowFrame.isEmpty else {
            return false
        }
        return NSScreen.screens.contains {
            $0.visibleFrame.insetBy(dx: -1, dy: -1)
                .contains(snapshot.windowFrame)
        }
    }

    private static func previewSnapshotAvoidsSelectedCard(
        _ snapshot: ClipPreviewAutomationSnapshot
    ) -> Bool {
        guard snapshot.isVisible,
              let cardFrame = snapshot.cardFrameInScreen else {
            return false
        }
        return snapshot.windowFrame.minY >= cardFrame.maxY
    }

    private static func previewSnapshotArrowPointsToSelectedCard(
        _ snapshot: ClipPreviewAutomationSnapshot
    ) -> Bool {
        guard let cardFrame = snapshot.cardFrameInScreen,
              let arrowTip = snapshot.arrowTipInScreen else {
            return false
        }
        return arrowTip.x >= cardFrame.minX - 1
            && arrowTip.x <= cardFrame.maxX + 1
            && arrowTip.y >= cardFrame.maxY
            && arrowTip.y <= cardFrame.maxY + 8
    }

    private static func failedPreviewResult() -> PreviewResult {
        PreviewResult(
            phase: "preview",
            success: false,
            textObservedIndex: nil,
            textObservedKind: nil,
            textObservedCharacterCount: 0,
            richTextRendered: false,
            fileObservedIndex: nil,
            fileObservedKind: nil,
            textPreviewWithinScreen: false,
            richTextPreviewWithinScreen: false,
            imagePreviewWithinScreen: false,
            filePreviewWithinScreen: false,
            previewAvoidedSelectedCards: false,
            arrowTrackedSelection: false,
            titleHeaderRemoved: false,
            translucentBackground: false,
            spaceOpenedPreview: false,
            textWasComplete: false,
            longTextNeededVerticalScrolling: false,
            previewStayedWithinScreen: false,
            rightArrowConsumed: false,
            imageSelectionUpdatedPreview: false,
            imageDecoded: false,
            imageDecodeStayedBounded: false,
            fileSelectionUpdatedPreview: false,
            quickLookURLMatched: false,
            escapeClosedPreview: false,
            spaceReopenedPreview: false,
            secondSpaceClosedPreview: false,
            printableKeyClosedPreview: false,
            printableKeyActivatedSearch: false,
            contentIndexRebuildCount: -1,
            maximumContentIndexRebuildCount: 1
        )
    }

    private static func descendantViews(of root: NSView?) -> [NSView] {
        guard let root else { return [] }
        return [root] + root.subviews.flatMap { descendantViews(of: $0) }
    }

    private static func isAssistantPopoverAnchoredAboveCard(_ itemID: UUID) -> Bool {
        guard let anchorFrame = SelectedClipPopoverAnchor.shared.screenFrame(for: itemID),
              let popoverFrame = AssistantPopoverController.shared.screenFrame else {
            return false
        }
        let verticallyAbove = popoverFrame.minY >= anchorFrame.maxY - 18
        let pointsAtCard = popoverFrame.minX - 24 <= anchorFrame.midX
            && anchorFrame.midX <= popoverFrame.maxX + 24
        return verticallyAbove && pointsAtCard
    }

    private static func captureKeyWindowScreenshotIfRequested() {
        guard let path = ProcessInfo.processInfo.environment[
            "PESTY_AUTOMATED_SCREENSHOT_PATH"
        ], !path.isEmpty else {
            return
        }
        let url = URL(fileURLWithPath: path)
        guard let view = AssistantPopoverController.shared.contentViewForScreenshot
            ?? visibleContentWindow()?.contentView else {
            return
        }
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            return
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url, options: Data.WritingOptions.atomic)
    }

    private static func visibleContentWindow() -> NSWindow? {
        if let keyWindow = NSApp.keyWindow, keyWindow.contentView != nil {
            return keyWindow
        }
        return NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil })
    }

    private static func runClearConfirmationTest(
        controller: AppController,
        runID: String
    ) {
        let items = (0..<4).map { index in
            ClipItem(
                type: .text,
                text: "pesty-clear-confirmation-\(runID)-\(index)",
                createdAt: Date(timeIntervalSinceNow: -Double(index))
            )
        }
        controller.monitor.stop()
        controller.store.replaceHistoryForAutomatedClearConfirmationTest(items)
        let pinboard = controller.store.addPinboard(
            name: "Automated Clear Confirmation"
        )
        controller.store.saveToPinboard(items[0], boardID: pinboard.id)

        controller.resolveClearHistoryConfirmation(confirmed: false)
        let countAfterCancellation = controller.store.history.count
        controller.resolveClearHistoryConfirmation(confirmed: true)
        let countAfterConfirmation = controller.store.history.count
        let pinboardCountAfterConfirmation =
            controller.store.pinboards.first(where: { $0.id == pinboard.id })?
                .items.count ?? 0
        let result = ClearConfirmationResult(
            phase: "clear-confirmation",
            success: countAfterCancellation == items.count
                && countAfterConfirmation == 0
                && pinboardCountAfterConfirmation == 1,
            initialCount: items.count,
            countAfterCancellation: countAfterCancellation,
            countAfterConfirmation: countAfterConfirmation,
            pinboardCountAfterConfirmation: pinboardCountAfterConfirmation
        )
        controller.store.saveNow()
        writeClearConfirmation(result)
        exit(result.success ? EXIT_SUCCESS : EXIT_FAILURE)
    }

    private static func seedDeletionSyncTest(
        controller: AppController,
        runID: String
    ) {
        let items = deletionSyncItems(runID: runID)
        let deletedText = deletionSyncDeletedText(runID: runID)
        guard let deletedItem = items.first(where: { $0.text == deletedText }),
              let staleURL = deletionSyncStaleSnapshotURL else {
            writeDeletionSyncFailure(phase: "deletion-sync-seed")
            exit(EXIT_FAILURE)
        }

        controller.monitor.stop()
        controller.store.replaceHistoryForAutomatedDeletionSyncTest(items)
        let staleSnapshot = ClipboardStoreSnapshot(
            history: items,
            pinboards: [
                Pinboard(
                    name: "Automated Deletion Sync",
                    items: [deletedItem]
                ),
            ],
            configuration: nil
        )
        do {
            let data = try JSONEncoder().encode(staleSnapshot)
            try data.write(to: staleURL, options: .atomic)
        } catch {
            writeDeletionSyncFailure(phase: "deletion-sync-seed")
            exit(EXIT_FAILURE)
        }

        controller.store.mergeSnapshotForAutomatedDeletionSyncTest(
            staleSnapshot
        )
        controller.store.delete(deletedItem)
        controller.store.mergeSnapshotForAutomatedDeletionSyncTest(
            staleSnapshot
        )
        finishDeletionSyncPhase(
            controller: controller,
            phase: "deletion-sync-seed",
            deletedText: deletedText,
            expectedHistoryCount: items.count - 1,
            staleSnapshotRejected: true,
            recopyAllowed: false
        )
    }

    private static func verifyDeletionSyncRestart(
        controller: AppController,
        runID: String,
        phase: String,
        allowRecopy: Bool
    ) {
        let deletedText = deletionSyncDeletedText(runID: runID)
        guard let staleSnapshot = readDeletionSyncStaleSnapshot() else {
            writeDeletionSyncFailure(phase: phase)
            exit(EXIT_FAILURE)
        }

        controller.monitor.stop()
        let absentAfterLoad = !controller.store.history.contains {
            $0.text == deletedText
        }
        controller.store.mergeSnapshotForAutomatedDeletionSyncTest(
            staleSnapshot
        )
        let absentAfterStaleMerge = !controller.store.history.contains {
            $0.text == deletedText
        }
        var recopyAllowed = false
        var expectedHistoryCount = staleSnapshot.history.count - 1
        if allowRecopy {
            controller.store.addCaptured(ClipItem(
                type: .text,
                text: deletedText,
                createdAt: Date(timeIntervalSince1970: 1)
            ))
            controller.store.mergeSnapshotForAutomatedDeletionSyncTest(
                staleSnapshot
            )
            recopyAllowed = controller.store.history.filter {
                $0.text == deletedText
            }.count == 1
            expectedHistoryCount = staleSnapshot.history.count
        }
        finishDeletionSyncPhase(
            controller: controller,
            phase: phase,
            deletedText: deletedText,
            expectedHistoryCount: expectedHistoryCount,
            staleSnapshotRejected: absentAfterLoad && absentAfterStaleMerge,
            recopyAllowed: recopyAllowed
        )
    }

    private static func finishDeletionSyncPhase(
        controller: AppController,
        phase: String,
        deletedText: String,
        expectedHistoryCount: Int,
        staleSnapshotRejected: Bool,
        recopyAllowed: Bool
    ) {
        controller.store.saveNow()
        let snapshot = readDeletionSyncActiveSnapshot()
        let deletedItemAbsent = !controller.store.history.contains {
            $0.text == deletedText
        }
        let deletedPinboardItemAbsent = !controller.store.pinboards.contains {
            $0.items.contains { $0.text == deletedText }
        }
        let tombstoneCount = snapshot?.deletions?.count ?? 0
        let expectsRecopy = phase == "deletion-sync-restart-2"
        let success = controller.store.history.count == expectedHistoryCount
            && staleSnapshotRejected
            && tombstoneCount == 1
            && deletedPinboardItemAbsent
            && (expectsRecopy ? recopyAllowed : deletedItemAbsent)
        writeDeletionSync(DeletionSyncResult(
            phase: phase,
            success: success,
            historyCount: controller.store.history.count,
            deletedItemAbsent: deletedItemAbsent,
            deletedPinboardItemAbsent: deletedPinboardItemAbsent,
            tombstoneCount: tombstoneCount,
            staleSnapshotRejected: staleSnapshotRejected,
            recopyAllowed: recopyAllowed
        ))
        exit(success ? EXIT_SUCCESS : EXIT_FAILURE)
    }

    private static func deletionSyncItems(runID: String) -> [ClipItem] {
        (0..<4).map { index in
            ClipItem(
                type: .text,
                text: "pesty-deletion-sync-\(runID)-\(index)",
                createdAt: Date(timeIntervalSinceNow: -Double(index + 10))
            )
        }
    }

    private static func deletionSyncDeletedText(runID: String) -> String {
        "pesty-deletion-sync-\(runID)-1"
    }

    private static var deletionSyncStaleSnapshotURL: URL? {
        ClipboardStore.automatedTestBase?
            .appendingPathComponent("deletion-sync-stale.json")
    }

    private static func readDeletionSyncStaleSnapshot()
        -> ClipboardStoreSnapshot? {
        guard let url = deletionSyncStaleSnapshotURL,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(
            ClipboardStoreSnapshot.self,
            from: data
        )
    }

    private static func readDeletionSyncActiveSnapshot()
        -> ClipboardStoreSnapshot? {
        guard let url = ClipboardStore.automatedTestBase?
            .appendingPathComponent("store.json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(
            ClipboardStoreSnapshot.self,
            from: data
        )
    }

    private static func writeDeletionSyncFailure(phase: String) {
        writeDeletionSync(DeletionSyncResult(
            phase: phase,
            success: false,
            historyCount: -1,
            deletedItemAbsent: false,
            deletedPinboardItemAbsent: false,
            tombstoneCount: -1,
            staleSnapshotRejected: false,
            recopyAllowed: false
        ))
    }

    private static func seedRetentionRestartTest(
        controller: AppController,
        runID: String
    ) {
        let items = (0..<150).map { index in
            ClipItem(
                type: .text,
                text: "pesty-retention-restart-\(runID)-\(index)",
                createdAt: Date(timeIntervalSinceNow: -Double(index))
            )
        }
        controller.monitor.stop()
        controller.store.replaceHistoryForAutomatedRetentionTest(items)
        Settings.shared.setHistoryRetentionSliderPosition(0)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let count = controller.store.history.count
            let result = RetentionRestartResult(
                phase: "retention-restart-seed",
                success: count == 150 && Settings.shared.historyLimitTrimAfter != nil,
                countAfterRestart: count,
                finalCount: count,
                expectedFinalCount: 100
            )
            controller.store.saveNow()
            writeRetentionRestart(result)
            exit(result.success ? EXIT_SUCCESS : EXIT_FAILURE)
        }
    }

    private static func verifyRetentionRestartTest(controller: AppController) {
        controller.monitor.stop()
        let countAfterRestart = controller.store.history.count
        let remainingDelay = max(
            0,
            Settings.shared.historyLimitTrimAfter?.timeIntervalSinceNow ?? 0
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + remainingDelay + 0.5) {
            let finalCount = controller.store.history.count
            let result = RetentionRestartResult(
                phase: "retention-restart-verify",
                success: countAfterRestart == 150 && finalCount == 100,
                countAfterRestart: countAfterRestart,
                finalCount: finalCount,
                expectedFinalCount: 100
            )
            controller.store.saveNow()
            writeRetentionRestart(result)
            exit(result.success ? EXIT_SUCCESS : EXIT_FAILURE)
        }
    }

    private static func seedRetentionSyncTest(
        controller: AppController,
        runID: String
    ) {
        let items = (0..<150).map { index in
            ClipItem(
                type: .text,
                text: "pesty-retention-sync-\(runID)-\(index)",
                createdAt: Date(timeIntervalSinceNow: -Double(index))
            )
        }
        controller.monitor.stop()
        controller.store.replaceHistoryForAutomatedRetentionTest(items)
        Settings.shared.setHistoryRetentionSliderPosition(0)
        controller.store.saveNow()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let configuration = Settings.shared.syncedHistoryRetention
            let result = RetentionSyncResult(
                phase: "retention-sync-seed",
                success: controller.store.history.count == 150
                    && Settings.shared.historyLimit == 100
                    && !Settings.shared.historyLimitUnlimited
                    && configuration?.limit == 100
                    && configuration?.unlimited == false
                    && configuration?.effectiveAt != nil
                    && Settings.shared.historyLimitTrimAfter != nil,
                countBeforeDeadline: controller.store.history.count,
                finalCount: controller.store.history.count,
                expectedFinalCount: 100,
                configuredLimit: Settings.shared.historyLimit,
                unlimited: Settings.shared.historyLimitUnlimited,
                hasSyncedConfiguration: configuration != nil,
                hasSharedEffectiveDate: configuration?.effectiveAt != nil
            )
            controller.store.saveNow()
            writeRetentionSync(result)
            exit(result.success ? EXIT_SUCCESS : EXIT_FAILURE)
        }
    }

    private static func verifyRetentionSyncTest(controller: AppController) {
        controller.monitor.stop()
        let countBeforeDeadline = controller.store.history.count
        let configuration = Settings.shared.syncedHistoryRetention
        let remainingDelay = max(
            0,
            Settings.shared.historyLimitTrimAfter?.timeIntervalSinceNow ?? 0
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + remainingDelay + 0.5) {
            let finalCount = controller.store.history.count
            let result = RetentionSyncResult(
                phase: "retention-sync-verify",
                success: countBeforeDeadline == 150
                    && finalCount == 100
                    && Settings.shared.historyLimit == 100
                    && !Settings.shared.historyLimitUnlimited
                    && configuration?.limit == 100
                    && configuration?.unlimited == false
                    && configuration?.effectiveAt != nil,
                countBeforeDeadline: countBeforeDeadline,
                finalCount: finalCount,
                expectedFinalCount: 100,
                configuredLimit: Settings.shared.historyLimit,
                unlimited: Settings.shared.historyLimitUnlimited,
                hasSyncedConfiguration: configuration != nil,
                hasSharedEffectiveDate: configuration?.effectiveAt != nil
            )
            controller.store.saveNow()
            writeRetentionSync(result)
            exit(result.success ? EXIT_SUCCESS : EXIT_FAILURE)
        }
    }

    private static func runRetentionDelayTest(
        controller: AppController,
        runID: String
    ) {
        let initialCount = 150
        let expectedFinalCount = 100
        let items = (0..<initialCount).map { index in
            ClipItem(
                type: .text,
                text: "pesty-retention-delay-\(runID)-\(index)",
                createdAt: Date(timeIntervalSinceNow: -Double(index))
            )
        }

        controller.monitor.stop()
        controller.store.replaceHistoryForAutomatedRetentionTest(items)
        Settings.shared.setHistoryRetentionSliderPosition(0)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let countDuringGracePeriod = controller.store.history.count
            Settings.shared.setHistoryRetentionSliderPosition(1)

            DispatchQueue.main.asyncAfter(
                deadline: .now() + HistoryRetentionPolicy.trimDelay
            ) {
                let countAfterCancellation = controller.store.history.count
                Settings.shared.setHistoryRetentionSliderPosition(0)

                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    let countDuringSecondGracePeriod = controller.store.history.count

                    DispatchQueue.main.asyncAfter(
                        deadline: .now() + HistoryRetentionPolicy.trimDelay
                    ) {
                        let finalCount = controller.store.history.count
                        let result = RetentionDelayResult(
                            phase: "retention-delay",
                            success: countDuringGracePeriod == initialCount
                                && countAfterCancellation == initialCount
                                && countDuringSecondGracePeriod == initialCount
                                && finalCount == expectedFinalCount,
                            initialCount: initialCount,
                            countDuringGracePeriod: countDuringGracePeriod,
                            countAfterCancellation: countAfterCancellation,
                            countDuringSecondGracePeriod: countDuringSecondGracePeriod,
                            finalCount: finalCount,
                            expectedFinalCount: expectedFinalCount
                        )
                        controller.store.saveNow()
                        writeRetentionDelay(result)
                        exit(result.success ? EXIT_SUCCESS : EXIT_FAILURE)
                    }
                }
            }
        }
    }

    private static func runKeyboardDeleteTest(
        controller: AppController,
        runID: String
    ) {
        let items = (0..<4).map { index in
            ClipItem(
                type: .text,
                text: "pesty-keyboard-delete-\(runID)-\(index)",
                createdAt: Date(timeIntervalSinceNow: -Double(index))
            )
        }
        controller.monitor.stop()
        controller.store.replaceHistoryForAutomatedKeyboardTest(items)
        controller.showBar()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let originalSearch = "pesty-keyboard-delete-\(runID)-"
            controller.store.searchText = originalSearch
            let searchBackspaceConsumed = makeKeyEvent(
                keyCode: UInt16(kVK_Delete),
                characters: "\u{7F}"
            ).map { controller.handleKey($0) == nil } ?? false
            let searchBackspacePreservedHistory =
                controller.store.history.map(\.id) == items.map(\.id)
                && controller.store.searchText == String(originalSearch.dropLast())
            controller.store.searchText = ""
            controller.store.selectFirst()

            let rightArrowConsumed = makeKeyEvent(
                keyCode: UInt16(kVK_RightArrow),
                characters: "\u{F703}"
            ).map { controller.handleKey($0) == nil } ?? false

            let plainBackspaceConsumed = makeKeyEvent(
                keyCode: UInt16(kVK_Delete),
                characters: "\u{7F}"
            ).map { controller.handleKey($0) == nil } ?? false
            let plainBackspacePreservedHistory =
                controller.store.history.map(\.id) == items.map(\.id)
                && controller.store.selectedID == items[1].id

            let forwardDeleteConsumed = makeKeyEvent(
                keyCode: UInt16(kVK_ForwardDelete),
                characters: "\u{F728}"
            ).map { controller.handleKey($0) == nil } ?? false
            let forwardDeletePreservedHistory =
                controller.store.history.map(\.id) == items.map(\.id)
                && controller.store.selectedID == items[1].id

            let firstCommandBackspaceConsumed = makeKeyEvent(
                keyCode: UInt16(kVK_Delete),
                characters: "\u{7F}",
                modifierFlags: [.command]
            ).map { controller.handleKey($0) == nil } ?? false
            let selectedFollowingItemAfterMiddleDelete =
                controller.store.selectedID == items[2].id

            let secondCommandBackspaceConsumed = makeKeyEvent(
                keyCode: UInt16(kVK_Delete),
                characters: "\u{7F}",
                modifierFlags: [.command]
            ).map { controller.handleKey($0) == nil } ?? false
            let selectedFollowingItemAfterSecondDelete =
                controller.store.selectedID == items[3].id

            let thirdCommandBackspaceConsumed = makeKeyEvent(
                keyCode: UInt16(kVK_Delete),
                characters: "\u{7F}",
                modifierFlags: [.command]
            ).map { controller.handleKey($0) == nil } ?? false
            let selectedPreviousItemAfterTailDelete =
                controller.store.selectedID == items[0].id
            let remainingItemMatches = controller.store.history.map(\.id) == [items[0].id]

            let result = KeyboardDeleteResult(
                phase: "keyboard-delete",
                success: rightArrowConsumed
                    && searchBackspaceConsumed
                    && searchBackspacePreservedHistory
                    && plainBackspaceConsumed
                    && plainBackspacePreservedHistory
                    && forwardDeleteConsumed
                    && forwardDeletePreservedHistory
                    && firstCommandBackspaceConsumed
                    && secondCommandBackspaceConsumed
                    && thirdCommandBackspaceConsumed
                    && selectedFollowingItemAfterMiddleDelete
                    && selectedFollowingItemAfterSecondDelete
                    && selectedPreviousItemAfterTailDelete
                    && remainingItemMatches,
                initialCount: items.count,
                finalCount: controller.store.history.count,
                searchBackspaceConsumed: searchBackspaceConsumed,
                searchBackspacePreservedHistory: searchBackspacePreservedHistory,
                rightArrowConsumed: rightArrowConsumed,
                plainBackspaceConsumed: plainBackspaceConsumed,
                plainBackspacePreservedHistory: plainBackspacePreservedHistory,
                forwardDeleteConsumed: forwardDeleteConsumed,
                forwardDeletePreservedHistory: forwardDeletePreservedHistory,
                commandBackspaceConsumed: firstCommandBackspaceConsumed
                    && secondCommandBackspaceConsumed
                    && thirdCommandBackspaceConsumed,
                selectedFollowingItemAfterMiddleDelete:
                    selectedFollowingItemAfterMiddleDelete,
                selectedFollowingItemAfterSecondDelete:
                    selectedFollowingItemAfterSecondDelete,
                selectedPreviousItemAfterTailDelete:
                    selectedPreviousItemAfterTailDelete,
                remainingItemMatches: remainingItemMatches
            )
            controller.store.saveNow()
            writeKeyboardDelete(result)
            exit(result.success ? EXIT_SUCCESS : EXIT_FAILURE)
        }
    }

    private static func makeKeyEvent(
        keyCode: UInt16,
        characters: String,
        modifierFlags: NSEvent.ModifierFlags = [],
        windowNumber: Int = 0
    ) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )
    }

    private static func runPerformanceTest(controller: AppController, runID: String) {
        let itemCount = 1_000
        let checkpointIndices = [0, 249, 499, 749, 999]
        let includeImages = ProcessInfo.processInfo.environment[
            "PESTY_PERFORMANCE_INCLUDE_IMAGES"
        ] == "1"
        controller.monitor.stop()
        let syntheticImageData = includeImages ? makePerformanceImageData() : nil
        let items = (0..<itemCount).map { index in
            if includeImages,
               index % 64 == 32,
               let syntheticImageData,
               let imageFileName = controller.store.storeImageData(
                    syntheticImageData
               ) {
                return ClipItem(
                    type: .image,
                    imageFileName: imageFileName,
                    imageHash: "pesty-performance-image-\(index)",
                    sourceBundleID: "com.bifrostproxy.pesty.performance-test",
                    sourceAppName: "Pesty Performance Test",
                    createdAt: Date(timeIntervalSinceNow: -Double(index))
                )
            }
            let prefix =
                "pesty-performance-\(runID)-\(String(format: "%04d", index))"
            let text = index % 250 == 0
                ? prefix + String(repeating: "-long-preview", count: 13_000)
                : prefix
            return ClipItem(
                type: .text,
                text: text,
                sourceBundleID: "com.bifrostproxy.pesty.performance-test",
                sourceAppName: "Pesty Performance Test",
                createdAt: Date(timeIntervalSinceNow: -Double(index))
            )
        }
        let expectedIDs = items.map(\.id)
        let expectedTexts = items.compactMap(\.text)
        let checkpointIDs = checkpointIndices.map { items[$0].id }
        let startedAt = Date()
        let previewBounded = items.allSatisfy {
            ClipCardPreview.text($0.text).count
                <= ClipCardPreview.maximumCharacterCount + 1
        }

        AutomatedUITestProbe.reset()
        VirtualizedClipStripMetrics.reset()
        controller.store.replaceHistoryForAutomatedStripTest(items)
        controller.showBar()

        visitCheckpoint(
            at: 0,
            checkpointIDs: checkpointIDs,
            controller: controller
        ) {
            guard let collectionView = firstCollectionView() else {
                finishPerformanceTest(
                    controller: controller,
                    items: items,
                    expectedIDs: expectedIDs,
                    expectedTexts: expectedTexts,
                    checkpointIDs: checkpointIDs,
                    checkpointIndices: checkpointIndices,
                    startedAt: startedAt,
                    previewBounded: previewBounded,
                    rapidScrollStepCount: -1
                )
                return
            }
            performRapidScrollStress(in: collectionView) { stepCount in
                finishPerformanceTest(
                    controller: controller,
                    items: items,
                    expectedIDs: expectedIDs,
                    expectedTexts: expectedTexts,
                    checkpointIDs: checkpointIDs,
                    checkpointIndices: checkpointIndices,
                    startedAt: startedAt,
                    previewBounded: previewBounded,
                    rapidScrollStepCount: stepCount
                )
            }
        }
    }

    private static func finishPerformanceTest(
        controller: AppController,
        items: [ClipItem],
        expectedIDs: [UUID],
        expectedTexts: [String],
        checkpointIDs: [UUID],
        checkpointIndices: [Int],
        startedAt: Date,
        previewBounded: Bool,
        rapidScrollStepCount: Int
    ) {
        let history = controller.store.history
        let visible = controller.store.visibleItems
        let rendered = AutomatedUITestProbe.renderedItemIDs
        let configured = VirtualizedClipStripMetrics.configuredItemIDs
        let source: String
        switch controller.store.source {
        case .history:
            source = "history"
        case .pinboard:
            source = "pinboard"
        }
        let maximumAllowedCells = 40
        let maximumHostingRootCreationCount = 40
        let maximumDurationMilliseconds = 6_000
        let durationMilliseconds = Int(Date().timeIntervalSince(startedAt) * 1_000)
        let finalSelectedIndex = controller.store.selectedID.flatMap {
            expectedIDs.firstIndex(of: $0)
        }
        let persistedInOrder = history.map(\.id) == expectedIDs
            && history.compactMap(\.text) == expectedTexts
        let visibleInOrder = visible.map(\.id) == expectedIDs
            && visible.compactMap(\.text) == expectedTexts
        let renderedCheckpoints = checkpointIDs.filter(rendered.contains).count
        let configuredCheckpoints = checkpointIDs.filter(configured.contains).count
        let result = PerformanceResult(
            phase: "performance",
            success: history.count == items.count
                && visible.count == items.count
                && persistedInOrder
                && visibleInOrder
                && renderedCheckpoints == checkpointIndices.count
                && configuredCheckpoints == checkpointIndices.count
                && configured.count == items.count
                && rapidScrollStepCount > 0
                && previewBounded
                && VirtualizedClipStripMetrics.createdCellCount
                    <= maximumAllowedCells
                && VirtualizedClipStripMetrics.maximumVisibleCellCount
                    <= maximumAllowedCells
                && VirtualizedClipStripMetrics.hostingRootCreationCount
                    <= maximumHostingRootCreationCount
                && finalSelectedIndex == checkpointIndices.last
                && source == "history"
                && controller.store.searchText.isEmpty
                && durationMilliseconds <= maximumDurationMilliseconds,
            historyCount: history.count,
            visibleCount: visible.count,
            expectedCount: items.count,
            persistedInOrder: persistedInOrder,
            visibleInOrder: visibleInOrder,
            checkpointCount: checkpointIndices.count,
            renderedCheckpoints: renderedCheckpoints,
            configuredCheckpoints: configuredCheckpoints,
            createdCellCount: VirtualizedClipStripMetrics.createdCellCount,
            maximumVisibleCellCount:
                VirtualizedClipStripMetrics.maximumVisibleCellCount,
            maximumAllowedCells: maximumAllowedCells,
            hostingRootCreationCount:
                VirtualizedClipStripMetrics.hostingRootCreationCount,
            maximumHostingRootCreationCount: maximumHostingRootCreationCount,
            cellConfigurationCount:
                VirtualizedClipStripMetrics.cellConfigurationCount,
            configuredItemCount: configured.count,
            rapidScrollStepCount: rapidScrollStepCount,
            previewBounded: previewBounded,
            imageItemCount: items.filter { $0.type == .image }.count,
            finalSelectedIndex: finalSelectedIndex,
            source: source,
            searchLength: controller.store.searchText.count,
            durationMilliseconds: durationMilliseconds,
            maximumDurationMilliseconds: maximumDurationMilliseconds
        )

        controller.store.saveNow()
        writePerformance(result)
        exit(result.success ? EXIT_SUCCESS : EXIT_FAILURE)
    }

    private static func performRapidScrollStress(
        in collectionView: NSCollectionView,
        attempt: Int = 0,
        completion: @escaping @MainActor (Int) -> Void
    ) {
        collectionView.layoutSubtreeIfNeeded()
        guard let scrollView = collectionView.enclosingScrollView else {
            completion(-1)
            return
        }
        let viewportWidth = scrollView.contentView.bounds.width
        let contentWidth = collectionView.collectionViewLayout?
            .collectionViewContentSize.width ?? collectionView.bounds.width
        let maximumX = max(0, contentWidth - viewportWidth)
        guard maximumX > 0 else {
            if attempt < 10 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    performRapidScrollStress(
                        in: collectionView,
                        attempt: attempt + 1,
                        completion: completion
                    )
                }
                return
            }
            completion(-1)
            return
        }

        let increment = max(Theme.cardWidth, viewportWidth * 0.95)
        var forward: [CGFloat] = []
        var position: CGFloat = 0
        while position < maximumX {
            forward.append(position)
            position += increment
        }
        forward.append(maximumX)
        let positions = Array(forward.reversed()) + forward

        func visit(_ index: Int) {
            guard index < positions.count else {
                DispatchQueue.main.async {
                    completion(positions.count)
                }
                return
            }
            var origin = scrollView.contentView.bounds.origin
            origin.x = positions[index]
            scrollView.contentView.scroll(to: origin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
            collectionView.layoutSubtreeIfNeeded()
            DispatchQueue.main.async {
                visit(index + 1)
            }
        }
        visit(0)
    }

    private static func makePerformanceImageData() -> Data? {
        autoreleasepool {
            guard let image = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: 1_024,
                pixelsHigh: 1_024,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ), let bitmapData = image.bitmapData else { return nil }
            memset(bitmapData, 0x7f, image.bytesPerRow * image.pixelsHigh)
            return image.representation(using: .png, properties: [:])
        }
    }

    private static func makePreviewImageData() -> Data? {
        autoreleasepool {
            guard let image = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: 2_048,
                pixelsHigh: 2_048,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ), let bitmapData = image.bitmapData else { return nil }
            memset(bitmapData, 0x5f, image.bytesPerRow * image.pixelsHigh)
            return image.representation(using: .png, properties: [:])
        }
    }

    private static func runMouseSelectionTest(
        controller: AppController,
        runID: String
    ) {
        let requestedItemCount = ProcessInfo.processInfo.environment[
            "PESTY_AUTOMATED_MOUSE_SELECTION_ITEM_COUNT"
        ].flatMap(Int.init)
        let itemCount = max(20, requestedItemCount ?? 20)
        let items = (0..<itemCount).map { index in
            ClipItem(
                type: .text,
                text: "pesty-mouse-selection-\(runID)-\(index)",
                sourceBundleID: "com.bifrostproxy.pesty.mouse-selection-test",
                sourceAppName: "Pesty Mouse Selection Test",
                createdAt: Date(timeIntervalSinceNow: -Double(index))
            )
        }

        controller.monitor.stop()
        VirtualizedClipStripMetrics.reset()
        controller.store.replaceHistoryForAutomatedStripTest(items)
        controller.showBar()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard let collectionView = firstCollectionView(),
                  let scrollView = collectionView.enclosingScrollView else {
                writeMouseSelection(MouseSelectionResult(
                    phase: "mouse-selection",
                    success: false,
                    itemCount: itemCount,
                    selectionChangedSynchronously: false,
                    selectionLatencyMilliseconds: -1,
                    maximumSelectionLatencyMilliseconds: 100,
                    selectionRendered: false,
                    renderLatencyMilliseconds: -1,
                    maximumRenderLatencyMilliseconds: 100,
                    textEditorFocusedBeforeClick: false,
                    textEditorReleasedByClick: false,
                    selectionPreservedEventSurface: false,
                    doubleClickSelectedItem: false,
                    doubleClickRequestedQuickPaste: false,
                    doubleClickQuickPasteRequestCount: 0,
                    rightArrowConsumedAfterClick: false,
                    rightArrowMovedSelectionAfterClick: false,
                    contentIndexRebuildCount: -1,
                    maximumContentIndexRebuildCount: 1,
                    visibleClickPreservedScrollPosition: false,
                    offscreenSelectionBecameVisible: false,
                    offscreenSelectionWasNotCentered: false
                ))
                exit(EXIT_FAILURE)
            }

            collectionView.layoutSubtreeIfNeeded()
            let visibleTargetIndex = min(1, items.count - 1)
            let visibleTargetPath = IndexPath(item: visibleTargetIndex, section: 0)
            guard let visibleCell = collectionView.item(
                at: visibleTargetPath
            ) as? ClipCollectionViewItem else {
                writeMouseSelection(MouseSelectionResult(
                    phase: "mouse-selection",
                    success: false,
                    itemCount: itemCount,
                    selectionChangedSynchronously: false,
                    selectionLatencyMilliseconds: -1,
                    maximumSelectionLatencyMilliseconds: 100,
                    selectionRendered: false,
                    renderLatencyMilliseconds: -1,
                    maximumRenderLatencyMilliseconds: 100,
                    textEditorFocusedBeforeClick: false,
                    textEditorReleasedByClick: false,
                    selectionPreservedEventSurface: false,
                    doubleClickSelectedItem: false,
                    doubleClickRequestedQuickPaste: false,
                    doubleClickQuickPasteRequestCount: 0,
                    rightArrowConsumedAfterClick: false,
                    rightArrowMovedSelectionAfterClick: false,
                    contentIndexRebuildCount: -1,
                    maximumContentIndexRebuildCount: 1,
                    visibleClickPreservedScrollPosition: false,
                    offscreenSelectionBecameVisible: false,
                    offscreenSelectionWasNotCentered: false
                ))
                exit(EXIT_FAILURE)
            }

            let initialOriginX = scrollView.contentView.bounds.origin.x
            let focusProbe = NSTextField(
                frame: NSRect(x: -2, y: -2, width: 1, height: 1)
            )
            collectionView.window?.contentView?.addSubview(focusProbe)
            controller.store.isSearchFieldActive = true
            _ = collectionView.window?.makeFirstResponder(focusProbe)
            let textEditorFocusedBeforeClick =
                collectionView.window?.firstResponder as? NSTextView != nil
            let eventSurfaceIdentity =
                visibleCell.eventSurfaceIdentityForAutomatedTest
            let startedAt = CFAbsoluteTimeGetCurrent()
            visibleCell.performPrimaryClickForAutomatedTest(clickCount: 1)
            let selectionLatencyMilliseconds =
                (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000
            let selectionChangedSynchronously =
                controller.store.selectedID == items[visibleTargetIndex].id
            let textEditorReleasedByClick =
                collectionView.window?.firstResponder as? NSTextView == nil
                && !controller.store.isSearchFieldActive
            let selectedCellAfterClick = collectionView.item(
                at: visibleTargetPath
            ) as? ClipCollectionViewItem
            let selectionPreservedEventSurface =
                selectedCellAfterClick === visibleCell
                && eventSurfaceIdentity != nil
                && selectedCellAfterClick?
                    .eventSurfaceIdentityForAutomatedTest
                    == eventSurfaceIdentity
            visibleCell.performPrimaryClickForAutomatedTest(clickCount: 2)
            let doubleClickSelectedItem =
                controller.store.selectedID == items[visibleTargetIndex].id
            let doubleClickRequestedQuickPaste =
                VirtualizedClipStripMetrics.lastQuickPasteItemID
                    == items[visibleTargetIndex].id
            let doubleClickQuickPasteRequestCount =
                VirtualizedClipStripMetrics.quickPasteRequestCount
            focusProbe.removeFromSuperview()
            let maximumSelectionLatencyMilliseconds = 100.0
            let maximumRenderLatencyMilliseconds = 100.0

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                let selectionRendered =
                    VirtualizedClipStripMetrics.lastSelectedItemID
                        == items[visibleTargetIndex].id
                let renderLatencyMilliseconds =
                    VirtualizedClipStripMetrics.lastSelectedConfigurationTime
                        .map { ($0 - startedAt) * 1_000 } ?? -1
                let visibleClickPreservedScrollPosition = abs(
                    scrollView.contentView.bounds.origin.x - initialOriginX
                ) < 0.5
                let rightArrowEvent = makeKeyEvent(
                    keyCode: UInt16(kVK_RightArrow),
                    characters: ""
                )
                let rightArrowConsumedAfterClick = rightArrowEvent.map {
                    controller.handleKey($0) == nil
                } ?? false
                let rightArrowMovedSelectionAfterClick =
                    controller.store.selectedID
                        == items[min(visibleTargetIndex + 1, items.count - 1)].id
                let offscreenIndex = items.count - 1
                controller.store.selectedID = items[offscreenIndex].id

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    collectionView.layoutSubtreeIfNeeded()
                    let selectedPath = IndexPath(
                        item: offscreenIndex,
                        section: 0
                    )
                    let selectedFrame = collectionView.collectionViewLayout?
                        .layoutAttributesForItem(at: selectedPath)?.frame
                    let visibleRect = collectionView.visibleRect
                    let offscreenSelectionBecameVisible =
                        selectedFrame.map(visibleRect.intersects) ?? false
                    let offscreenSelectionWasNotCentered = selectedFrame.map {
                        abs($0.midX - visibleRect.midX) > 1
                    } ?? false
                    let contentIndexRebuildCount =
                        VirtualizedClipStripMetrics.contentIndexRebuildCount
                    let maximumContentIndexRebuildCount = 1
                    let success = selectionChangedSynchronously
                        && selectionLatencyMilliseconds
                            <= maximumSelectionLatencyMilliseconds
                        && selectionRendered
                        && renderLatencyMilliseconds >= 0
                        && renderLatencyMilliseconds
                            <= maximumRenderLatencyMilliseconds
                        && textEditorFocusedBeforeClick
                        && textEditorReleasedByClick
                        && selectionPreservedEventSurface
                        && doubleClickSelectedItem
                        && doubleClickRequestedQuickPaste
                        && doubleClickQuickPasteRequestCount == 1
                        && rightArrowConsumedAfterClick
                        && rightArrowMovedSelectionAfterClick
                        && contentIndexRebuildCount
                            <= maximumContentIndexRebuildCount
                        && visibleClickPreservedScrollPosition
                        && offscreenSelectionBecameVisible
                        && offscreenSelectionWasNotCentered
                    controller.store.saveNow()
                    writeMouseSelection(MouseSelectionResult(
                        phase: "mouse-selection",
                        success: success,
                        itemCount: itemCount,
                        selectionChangedSynchronously:
                            selectionChangedSynchronously,
                        selectionLatencyMilliseconds:
                            selectionLatencyMilliseconds,
                        maximumSelectionLatencyMilliseconds:
                            maximumSelectionLatencyMilliseconds,
                        selectionRendered: selectionRendered,
                        renderLatencyMilliseconds:
                            renderLatencyMilliseconds,
                        maximumRenderLatencyMilliseconds:
                            maximumRenderLatencyMilliseconds,
                        textEditorFocusedBeforeClick:
                            textEditorFocusedBeforeClick,
                        textEditorReleasedByClick:
                            textEditorReleasedByClick,
                        selectionPreservedEventSurface:
                            selectionPreservedEventSurface,
                        doubleClickSelectedItem:
                            doubleClickSelectedItem,
                        doubleClickRequestedQuickPaste:
                            doubleClickRequestedQuickPaste,
                        doubleClickQuickPasteRequestCount:
                            doubleClickQuickPasteRequestCount,
                        rightArrowConsumedAfterClick:
                            rightArrowConsumedAfterClick,
                        rightArrowMovedSelectionAfterClick:
                            rightArrowMovedSelectionAfterClick,
                        contentIndexRebuildCount: contentIndexRebuildCount,
                        maximumContentIndexRebuildCount:
                            maximumContentIndexRebuildCount,
                        visibleClickPreservedScrollPosition:
                            visibleClickPreservedScrollPosition,
                        offscreenSelectionBecameVisible:
                            offscreenSelectionBecameVisible,
                        offscreenSelectionWasNotCentered:
                            offscreenSelectionWasNotCentered
                    ))
                    exit(success ? EXIT_SUCCESS : EXIT_FAILURE)
                }
            }
        }
    }

    private static func firstCollectionView() -> NSCollectionView? {
        for window in NSApp.windows where window.isVisible {
            if let collectionView = firstCollectionView(in: window.contentView) {
                return collectionView
            }
        }
        return nil
    }

    private static func firstCollectionView(in view: NSView?) -> NSCollectionView? {
        guard let view else { return nil }
        if let collectionView = view as? NSCollectionView {
            return collectionView
        }
        for subview in view.subviews {
            if let collectionView = firstCollectionView(in: subview) {
                return collectionView
            }
        }
        return nil
    }

    private static func visitCheckpoint(
        at position: Int,
        checkpointIDs: [UUID],
        controller: AppController,
        completion: @escaping @MainActor () -> Void
    ) {
        guard position < checkpointIDs.count else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                completion()
            }
            return
        }
        controller.store.selectedID = checkpointIDs[position]
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            visitCheckpoint(
                at: position + 1,
                checkpointIDs: checkpointIDs,
                controller: controller,
                completion: completion
            )
        }
    }

    private static func seed(
        _ expected: [String],
        controller: AppController,
        phase: String
    ) {
        let pasteboard = NSPasteboard.general
        let originalItems = snapshot(pasteboard)

        for (index, text) in expected.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8 * Double(index + 1)) {
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 4.2) {
            showAndVerify(
                expected,
                controller: controller,
                phase: phase,
                originalItems: originalItems
            )
        }
    }

    private static func showAndVerify(
        _ expected: [String],
        controller: AppController,
        phase: String,
        originalItems: [[NSPasteboard.PasteboardType: Data]]?
    ) {
        controller.showBar()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let historyTexts = Set(controller.store.history.compactMap(\.text))
            let visibleTexts = Set(controller.store.visibleItems.compactMap(\.text))
            let renderedTexts = AutomatedUITestProbe.renderedTexts
            let source: String
            switch controller.store.source {
            case .history:
                source = "history"
            case .pinboard:
                source = "pinboard"
            }
            let result = Result(
                phase: phase,
                success: expected.allSatisfy(historyTexts.contains)
                    && expected.allSatisfy(visibleTexts.contains)
                    && expected.allSatisfy(renderedTexts.contains),
                historyCount: controller.store.history.count,
                visibleCount: controller.store.visibleItems.count,
                expectedCount: expected.count,
                persistedMatches: expected.filter(historyTexts.contains).count,
                visibleMatches: expected.filter(visibleTexts.contains).count,
                renderedMatches: expected.filter(renderedTexts.contains).count,
                source: source,
                searchLength: controller.store.searchText.count
            )

            controller.store.saveNow()
            if ProcessInfo.processInfo.environment["PESTY_AUTOMATED_TEST_CLEANUP"] == "1" {
                let historyCountBeforeCleanup = controller.store.history.count
                controller.store.removeAutomatedTestItems(withTexts: Set(expected))
                let cleanupResult = CleanupResult(
                    phase: "cleanup",
                    success: expected.allSatisfy {
                        expectedText in
                        !controller.store.history.contains {
                            $0.text == expectedText
                        }
                    },
                    historyCount: controller.store.history.count,
                    removedCount: historyCountBeforeCleanup
                        - controller.store.history.count
                )
                writeCleanup(cleanupResult)
            }
            if let originalItems {
                restore(originalItems, to: .general)
            }
            write(result)
            exit(result.success ? EXIT_SUCCESS : EXIT_FAILURE)
        }
    }

    private static func snapshot(
        _ pasteboard: NSPasteboard
    ) -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        }
    }

    private static func restore(
        _ items: [[NSPasteboard.PasteboardType: Data]],
        to pasteboard: NSPasteboard
    ) {
        pasteboard.clearContents()
        let restored = items.map { values -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in values {
                item.setData(data, forType: type)
            }
            return item
        }
        if !restored.isEmpty {
            pasteboard.writeObjects(restored)
        }
    }

    private static func write(_ result: Result) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(result) else { return }
        FileHandle.standardOutput.write(Data("AUTOMATED_UI_TEST_RESULT ".utf8))
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func writeCleanup(_ result: CleanupResult) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(result) else { return }
        FileHandle.standardOutput.write(
            Data("AUTOMATED_UI_TEST_CLEANUP_RESULT ".utf8)
        )
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func writeRetentionDelay(_ result: RetentionDelayResult) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(result) else { return }
        FileHandle.standardOutput.write(Data("AUTOMATED_RETENTION_DELAY_RESULT ".utf8))
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func writeRetentionRestart(_ result: RetentionRestartResult) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(result) else { return }
        FileHandle.standardOutput.write(Data("AUTOMATED_RETENTION_RESTART_RESULT ".utf8))
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func writeRetentionSync(_ result: RetentionSyncResult) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(result) else { return }
        FileHandle.standardOutput.write(Data("AUTOMATED_RETENTION_SYNC_RESULT ".utf8))
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func writeClearConfirmation(_ result: ClearConfirmationResult) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(result) else { return }
        FileHandle.standardOutput.write(Data("AUTOMATED_CLEAR_CONFIRMATION_RESULT ".utf8))
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func writeDeletionSync(_ result: DeletionSyncResult) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(result) else { return }
        FileHandle.standardOutput.write(Data("AUTOMATED_DELETION_SYNC_RESULT ".utf8))
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func writeSearchInput(_ result: SearchInputResult) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(result) else { return }
        FileHandle.standardOutput.write(Data("AUTOMATED_SEARCH_INPUT_RESULT ".utf8))
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func writeTranslationBoard(_ result: TranslationBoardResult) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(result) else { return }
        FileHandle.standardOutput.write(Data("AUTOMATED_TRANSLATION_BOARD_RESULT ".utf8))
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func writeTranslationSettings(_ result: TranslationSettingsResult) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(result) else { return }
        FileHandle.standardOutput.write(Data("AUTOMATED_TRANSLATION_SETTINGS_RESULT ".utf8))
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func writeExplanationBoard(_ result: ExplanationBoardResult) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(result) else { return }
        FileHandle.standardOutput.write(Data("AUTOMATED_EXPLANATION_BOARD_RESULT ".utf8))
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func writeDoubaoLiveTranslation(_ result: DoubaoLiveTranslationResult) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(result) else { return }
        FileHandle.standardOutput.write(Data("AUTOMATED_DOUBAO_LIVE_TRANSLATION_RESULT ".utf8))
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func writeExplanationLive(_ result: ExplanationLiveResult) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(result) else { return }
        FileHandle.standardOutput.write(Data("AUTOMATED_EXPLANATION_LIVE_RESULT ".utf8))
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func writeDoubaoPromptDiagnostic(_ result: DoubaoPromptDiagnosticResult) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(result) else { return }
        FileHandle.standardOutput.write(Data("AUTOMATED_DOUBAO_PROMPT_DIAGNOSTIC_RESULT ".utf8))
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func writePreview(_ result: PreviewResult) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(result) else { return }
        FileHandle.standardOutput.write(
            Data("AUTOMATED_PREVIEW_RESULT ".utf8)
        )
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func writeQuickPaste(_ result: QuickPasteResult) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(result) else { return }
        FileHandle.standardOutput.write(Data("AUTOMATED_QUICK_PASTE_RESULT ".utf8))
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func writePerformance(_ result: PerformanceResult) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(result) else { return }
        FileHandle.standardOutput.write(Data("AUTOMATED_PERFORMANCE_TEST_RESULT ".utf8))
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func writeMouseSelection(_ result: MouseSelectionResult) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try! encoder.encode(result)
        FileHandle.standardOutput.write(Data("AUTOMATED_MOUSE_SELECTION_RESULT ".utf8))
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func writeKeyboardDelete(_ result: KeyboardDeleteResult) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(result) else { return }
        FileHandle.standardOutput.write(Data("AUTOMATED_KEYBOARD_DELETE_RESULT ".utf8))
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
