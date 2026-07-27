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

    static func start(controller: AppController) {
        let environment = ProcessInfo.processInfo.environment
        let phase = environment["PESTY_AUTOMATED_UI_TEST"] ?? "verify"
        let runID = environment["PESTY_AUTOMATED_TEST_ID"] ?? "default"
        let expected = (1...4).map { "pesty-auto-\(runID)-\($0)" }

        AutomatedUITestProbe.reset()
        if phase == "seed" {
            seed(expected, controller: controller, phase: phase)
        } else {
            showAndVerify(expected, controller: controller, phase: phase, originalItems: nil)
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
}
