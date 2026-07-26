import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case chinese = "zh-Hans"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .chinese: return "中文"
        }
    }

    static var systemDefault: AppLanguage {
        Locale.current.language.languageCode?.identifier == "zh" ? .chinese : .english
    }
}

enum L10n {
    static var currentLanguage: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: "language") ?? "")
            ?? AppLanguage.systemDefault
    }

    static func text(_ english: String, _ chinese: String) -> String {
        currentLanguage == .chinese ? chinese : english
    }

    static var general: String { text("General", "通用") }
    static var about: String { text("About", "关于") }
    static var activation: String { text("Activation", "快捷操作") }
    static var showPesty: String { text("Show Pesty", "显示 Pesty") }
    static var historyLimit: String { text("History limit", "历史记录上限") }
    static func items(_ count: Int) -> String {
        currentLanguage == .chinese ? "\(count) 项" : "\(count) items"
    }
    static var behavior: String { text("Behavior", "行为") }
    static var pasteDirectly: String {
        text("Paste directly into the active app", "直接粘贴到当前应用")
    }
    static var ignorePasswords: String {
        text("Ignore passwords (concealed clips)", "忽略密码（隐藏的剪贴板内容）")
    }
    static var playSound: String { text("Play sound on paste", "粘贴时播放声音") }
    static var launchAtLogin: String { text("Launch at login", "登录时启动") }
    static var barHeight: String { text("Bar height", "面板高度") }
    static var px: String { text("px", "像素") }
    static var selectClip: String {
        text("Select a clip to copy it, then press ⌘V to paste it into your app.",
             "选择一条剪贴内容进行复制，然后按 ⌘V 粘贴到当前应用。")
    }
    static var sync: String { text("Sync", "同步") }
    static var syncClipboard: String {
        text("Sync clipboard via iCloud Drive", "通过 iCloud Drive 同步剪贴板")
    }
    static var syncAvailable: String {
        text("Keeps your history and pinboards in sync across your Macs through iCloud Drive.",
             "通过 iCloud Drive 在你的 Mac 之间同步历史记录和 Pinboard。")
    }
    static var syncUnavailable: String {
        text("Sign in to iCloud and enable iCloud Drive to use sync.",
             "请登录 iCloud 并启用 iCloud Drive 以使用同步功能。")
    }
    static var permissions: String { text("Permissions", "权限") }
    static var accessibility: String { text("Accessibility", "辅助功能") }
    static var accessibilityGranted: String {
        text("Granted — direct paste is enabled.", "已授权 — 直接粘贴已启用。")
    }
    static var accessibilityWaiting: String {
        text("Waiting… toggle Pesty on in System Settings.",
             "等待中……请在系统设置中打开 Pesty。")
    }
    static var accessibilityRequired: String {
        text("Required to paste directly into other apps.",
             "直接粘贴到其他应用需要此权限。")
    }
    static var openSettings: String { text("Open Settings", "打开设置") }
    static var restartPesty: String { text("Restart Pesty", "重启 Pesty") }
    static var data: String { text("Data", "数据") }
    static var clearClipboardHistory: String {
        text("Clear Clipboard History", "清除剪贴板历史记录")
    }
    static var languageLabel: String { text("Language", "语言") }
    static var languageDescription: String {
        text("Choose the language used by Pesty.", "选择 Pesty 使用的语言。")
    }
    static var settingsWindowTitle: String { text("Pesty Settings", "Pesty 设置") }

    static var openPesty: String { text("Open Pesty", "打开 Pesty") }
    static var settings: String { text("Settings…", "设置…") }
    static var clearHistory: String { text("Clear History", "清除历史记录") }
    static var aboutPesty: String { text("About Pesty", "关于 Pesty") }
    static var quitPesty: String { text("Quit Pesty", "退出 Pesty") }
    static var iCloudUnavailable: String { text("iCloud Drive Unavailable", "iCloud Drive 不可用") }
    static var iCloudUnavailableMessage: String {
        text("Sign in to iCloud and enable iCloud Drive in System Settings to sync your clipboard across your Macs.",
             "请登录 iCloud 并在系统设置中启用 iCloud Drive，以在你的 Mac 之间同步剪贴板。")
    }
    static var aboutDescription: String {
        text("A free, open-source clipboard manager for macOS.\nInspired by Paste.",
             "一款免费、开源的 macOS 剪贴板管理工具。\n灵感来自 Paste。")
    }
    static func version(_ value: String) -> String {
        text("Version \(value)", "版本 \(value)")
    }
    static var reportIssue: String { text("Report an Issue", "反馈问题") }
    static var licenseDescription: String {
        text("MIT Licensed · Made with SwiftUI", "MIT 许可 · 使用 SwiftUI 制作")
    }

    static var clipboard: String { text("Clipboard", "剪贴板") }
    static var rename: String { text("Rename…", "重命名…") }
    static var deletePinboard: String { text("Delete Pinboard", "删除 Pinboard") }
    static var newPinboard: String { text("New Pinboard", "新建 Pinboard") }
    static var enterNewName: String { text("Enter a new name", "输入新名称") }
    static var ok: String { text("OK", "好") }
    static var cancel: String { text("Cancel", "取消") }

    static var nothingCopied: String { text("Nothing copied yet", "还没有复制内容") }
    static func noMatches(_ query: String) -> String {
        text("No matches for “\(query)”", "没有匹配“\(query)”的内容")
    }
    static var iCloudSyncOn: String { text("iCloud sync on", "iCloud 同步已开启") }
    static var turnOnICloudSync: String { text("Turn on iCloud sync", "开启 iCloud 同步") }

    static var paste: String { text("Paste", "粘贴") }
    static var copy: String { text("Copy", "复制") }
    static var saveToPinboard: String { text("Save to Pinboard", "保存到 Pinboard") }
    static var saveToNewPinboard: String { text("Save to New Pinboard…", "保存到新 Pinboard…") }
    static var name: String { text("Name", "名称") }
    static var editTitle: String { text("Edit Title…", "编辑标题…") }
    static var cardTitle: String { text("Card title", "卡片标题") }
    static var delete: String { text("Delete", "删除") }
    static var file: String { text("File", "文件") }
    static func fileCount(_ count: Int) -> String {
        currentLanguage == .chinese ? "\(count) 个文件" : "\(count) file\(count == 1 ? "" : "s")"
    }
    static var image: String { text("Image", "图片") }
    static var color: String { text("Color", "颜色") }
    static func characterCount(_ count: Int) -> String {
        currentLanguage == .chinese ? "\(count) 个字符" : "\(count) characters"
    }
    static var pressKeys: String { text("Press keys…", "请按下快捷键…") }

    static func clipType(_ type: ClipType) -> String {
        switch type {
        case .text: return text("Text", "文本")
        case .richText: return text("Rich Text", "富文本")
        case .link: return text("Link", "链接")
        case .image: return text("Image", "图片")
        case .file: return text("File", "文件")
        case .color: return text("Color", "颜色")
        }
    }

    static var now: String { text("Now", "刚刚") }
    static var justNow: String { text("Just now", "刚刚") }
    static var localeIdentifier: String { currentLanguage == .chinese ? "zh_CN" : "en_US" }
}

extension Notification.Name {
    static let pestyLanguageDidChange = Notification.Name("PestyLanguageDidChange")
}
