import AppKit
import Darwin
import Foundation

@MainActor
enum AutomatedUITestProbe {
    private(set) static var renderedTexts = Set<String>()

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["PESTY_AUTOMATED_UI_TEST"] != nil
    }

    static func reset() {
        renderedTexts.removeAll()
    }

    static func record(_ item: ClipItem) {
        guard isEnabled, let text = item.text else { return }
        renderedTexts.insert(text)
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
        let finalSelectedIndex: Int?
        let source: String
        let searchLength: Int
        let durationMilliseconds: Int
        let maximumDurationMilliseconds: Int
    }

    static func start(controller: AppController) {
        let environment = ProcessInfo.processInfo.environment
        let phase = environment["PESTY_AUTOMATED_UI_TEST"] ?? "verify"
        let runID = environment["PESTY_AUTOMATED_TEST_ID"] ?? "default"
        if phase == "performance" {
            runPerformanceTest(controller: controller, runID: runID)
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

    private static func runPerformanceTest(controller: AppController, runID: String) {
        let itemCount = 1_000
        let checkpointIndices = [0, 249, 499, 749, 999]
        let items = (0..<itemCount).map { index in
            ClipItem(
                type: .text,
                text: "pesty-performance-\(runID)-\(String(format: "%04d", index))",
                sourceBundleID: "com.bifrostproxy.pesty.performance-test",
                sourceAppName: "Pesty Performance Test",
                createdAt: Date(timeIntervalSinceNow: -Double(index))
            )
        }
        let expectedIDs = items.map(\.id)
        let expectedTexts = items.compactMap(\.text)
        let checkpointIDs = checkpointIndices.map { items[$0].id }
        let checkpointTexts = checkpointIndices.compactMap { items[$0].text }
        let startedAt = Date()

        controller.monitor.stop()
        AutomatedUITestProbe.reset()
        VirtualizedClipStripMetrics.reset()
        controller.store.replaceHistoryForAutomatedPerformanceTest(items)
        controller.showBar()

        visitCheckpoint(
            at: 0,
            checkpointIDs: checkpointIDs,
            controller: controller
        ) {
            let history = controller.store.history
            let visible = controller.store.visibleItems
            let rendered = AutomatedUITestProbe.renderedTexts
            let configured = VirtualizedClipStripMetrics.configuredItemIDs
            let source: String
            switch controller.store.source {
            case .history:
                source = "history"
            case .pinboard:
                source = "pinboard"
            }
            let maximumAllowedCells = 40
            let maximumDurationMilliseconds = 6_000
            let durationMilliseconds = Int(Date().timeIntervalSince(startedAt) * 1_000)
            let finalSelectedIndex = controller.store.selectedID.flatMap {
                expectedIDs.firstIndex(of: $0)
            }
            let persistedInOrder = history.map(\.id) == expectedIDs
                && history.compactMap(\.text) == expectedTexts
            let visibleInOrder = visible.map(\.id) == expectedIDs
                && visible.compactMap(\.text) == expectedTexts
            let renderedCheckpoints = checkpointTexts.filter(rendered.contains).count
            let configuredCheckpoints = checkpointIDs.filter(configured.contains).count
            let result = PerformanceResult(
                phase: "performance",
                success: history.count == itemCount
                    && visible.count == itemCount
                    && persistedInOrder
                    && visibleInOrder
                    && renderedCheckpoints == checkpointIndices.count
                    && configuredCheckpoints == checkpointIndices.count
                    && VirtualizedClipStripMetrics.createdCellCount <= maximumAllowedCells
                    && VirtualizedClipStripMetrics.maximumVisibleCellCount <= maximumAllowedCells
                    && finalSelectedIndex == checkpointIndices.last
                    && source == "history"
                    && controller.store.searchText.isEmpty
                    && durationMilliseconds <= maximumDurationMilliseconds,
                historyCount: history.count,
                visibleCount: visible.count,
                expectedCount: itemCount,
                persistedInOrder: persistedInOrder,
                visibleInOrder: visibleInOrder,
                checkpointCount: checkpointIndices.count,
                renderedCheckpoints: renderedCheckpoints,
                configuredCheckpoints: configuredCheckpoints,
                createdCellCount: VirtualizedClipStripMetrics.createdCellCount,
                maximumVisibleCellCount: VirtualizedClipStripMetrics.maximumVisibleCellCount,
                maximumAllowedCells: maximumAllowedCells,
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
    }

    private static func visitCheckpoint(
        at position: Int,
        checkpointIDs: [UUID],
        controller: AppController,
        completion: @escaping @MainActor () -> Void
    ) {
        guard position < checkpointIDs.count else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                completion()
            }
            return
        }
        controller.store.selectedID = checkpointIDs[position]
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7 * Double(index + 1)) {
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.4) {
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
                controller.store.removeAutomatedTestItems(withTexts: Set(expected))
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

    private static func writePerformance(_ result: PerformanceResult) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(result) else { return }
        FileHandle.standardOutput.write(Data("AUTOMATED_PERFORMANCE_TEST_RESULT ".utf8))
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
