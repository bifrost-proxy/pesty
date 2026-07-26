import AppKit

extension ClipboardStore {
    func seedDemo() {
        let now = Date()
        let demo: [ClipItem] = [
            ClipItem(type: .text,
                     text: "The quickest way to paste is to press Return on the highlighted card.",
                     sourceBundleID: "com.apple.Notes", sourceAppName: "Notes",
                     createdAt: now.addingTimeInterval(-12)),
            ClipItem(type: .link,
                     text: "https://github.com/bifrost-proxy/pesty",
                     sourceBundleID: "com.apple.Safari", sourceAppName: "Safari",
                     createdAt: now.addingTimeInterval(-90)),
            ClipItem(type: .text,
                     text: "func paste(_ item: ClipItem) {\n    pasteboard.clearContents()\n    pasteboard.setString(item.text, forType: .string)\n}",
                     sourceBundleID: "com.apple.dt.Xcode", sourceAppName: "Xcode",
                     createdAt: now.addingTimeInterval(-340)),
            ClipItem(type: .color, colorHex: "#5B8DEF",
                     sourceBundleID: "com.apple.dt.Xcode", sourceAppName: "Xcode",
                     createdAt: now.addingTimeInterval(-600)),
            ClipItem(type: .text,
                     text: "hello@example.com",
                     sourceBundleID: "com.apple.mail", sourceAppName: "Mail",
                     createdAt: now.addingTimeInterval(-1200)),
            ClipItem(type: .file,
                     text: "Q3-Report.pdf",
                     fileURLs: ["file:///Users/me/Documents/Q3-Report.pdf"],
                     sourceBundleID: "com.apple.finder", sourceAppName: "Finder",
                     createdAt: now.addingTimeInterval(-3600)),
            ClipItem(type: .link,
                     text: "https://pasteapp.io",
                     sourceBundleID: "com.apple.Safari", sourceAppName: "Safari",
                     createdAt: now.addingTimeInterval(-7200)),
            ClipItem(type: .text,
                     text: "Remember to verify the release before publishing it.",
                     sourceBundleID: "com.apple.reminders", sourceAppName: "Reminders",
                     createdAt: now.addingTimeInterval(-9000))
        ]
        for item in demo.reversed() { addCaptured(item) }
        selectFirst()
    }
}
