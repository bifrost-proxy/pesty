import Foundation

enum LocalizationVerifier {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    static func run() throws {
        let key = "language"
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        try verify(
            language: .english,
            key: key
        ) {
            [
                (L10n.settings, "Settings…"),
                (L10n.showMenuBarIcon, "Show menu bar icon"),
                (L10n.items(2), "2 items"),
                (L10n.fileCount(1), "1 file"),
                (L10n.fileCount(2), "2 files"),
                (L10n.version("1.2.3"), "Version 1.2.3"),
            ]
        }
        guard ClipType.richText.label == "Rich Text" else {
            throw Failure(description: "English clip type label is incomplete")
        }

        try verify(
            language: .chinese,
            key: key
        ) {
            [
                (L10n.settings, "设置…"),
                (L10n.showMenuBarIcon, "显示菜单栏图标"),
                (L10n.items(2), "2 项"),
                (L10n.fileCount(2), "2 个文件"),
                (L10n.version("1.2.3"), "版本 1.2.3"),
            ]
        }
        guard ClipType.richText.label == "富文本" else {
            throw Failure(description: "Simplified Chinese clip type label is incomplete")
        }
    }

    private static func verify(
        language: AppLanguage,
        key: String,
        expectations: () -> [(actual: String, expected: String)]
    ) throws {
        UserDefaults.standard.set(language.rawValue, forKey: key)
        for expectation in expectations() where expectation.actual != expectation.expected {
            throw Failure(
                description: "\(language.rawValue): expected \(expectation.expected), got \(expectation.actual)"
            )
        }
    }
}
