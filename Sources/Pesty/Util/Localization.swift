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
    static var searchClipboard: String { text("Search", "搜索") }
    static var historyLimit: String { text("History limit", "历史记录上限") }
    static var unlimited: String { text("Unlimited", "无限") }
    static var historyLimitDelayDescription: String {
        text(
            "If a lower limit would remove existing items, deletion waits 10 seconds so you can undo it.",
            "如果降低上限会删除已有记录，Pesty 将等待 10 秒再清理，期间可以调高或切回无限。"
        )
    }
    static var storageUsed: String { text("Current storage used", "当前占用空间") }
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
    static var showMenuBarIcon: String { text("Show menu bar icon", "显示菜单栏图标") }
    static var showMenuBarIconDescription: String {
        text("When hidden, open Pesty again from Applications to show Settings.",
             "隐藏后，从“应用程序”中再次打开 Pesty 即可显示设置。")
    }
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
    static var clearHistoryConfirmationTitle: String {
        text(
            "Clear all clipboard history?",
            "确定清除全部剪贴板历史记录吗？"
        )
    }
    static var clearHistoryConfirmationMessage: String {
        text(
            "This permanently deletes all clipboard history and its stored images. This action cannot be undone. Pinboards will not be deleted.",
            "这会永久删除全部剪贴板历史记录及其图片，且无法撤销。Pinboard 中的内容不会被删除。"
        )
    }
    static var languageLabel: String { text("Language", "语言") }
    static var languageDescription: String {
        text("Choose the language used by Pesty.", "选择 Pesty 使用的语言。")
    }
    static var settingsWindowTitle: String { text("Pesty Settings", "Pesty 设置") }

    static var openPesty: String { text("Open Pesty", "打开 Pesty") }
    static var settings: String { text("Settings…", "设置…") }
    static var checkForUpdates: String { text("Check for Updates…", "检查更新…") }
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
    static var updateAvailable: String { text("Update Available", "发现新版本") }
    static func updateAvailableMessage(_ version: String) -> String {
        text("Pesty \(version) is ready to install.",
             "Pesty \(version) 已可安装。")
    }
    static func updateToVersion(_ version: String) -> String {
        text("Update to Pesty \(version)", "更新到 Pesty \(version)")
    }
    static func downloadingUpdate(_ version: String) -> String {
        text("Downloading Pesty \(version)…", "正在下载 Pesty \(version)…")
    }
    static func installingUpdate(_ version: String) -> String {
        text("Installing Pesty \(version)…", "正在安装 Pesty \(version)…")
    }
    static var installAndRestart: String {
        text("Install and Restart", "安装并重启")
    }
    static var later: String { text("Later", "稍后") }
    static var upToDate: String { text("Pesty Is Up to Date", "Pesty 已是最新版本") }
    static func upToDateMessage(_ version: String) -> String {
        text("You are running Pesty \(version).",
             "你正在使用 Pesty \(version)。")
    }
    static var updateCheckFailed: String {
        text("Unable to Check for Updates", "无法检查更新")
    }
    static var updateInstallFailed: String {
        text("Unable to Install Update", "无法安装更新")
    }
    static var updateRestoredPreviousVersion: String {
        text("The update could not be completed. Pesty restored and reopened the previous version.",
             "更新未能完成。Pesty 已恢复并重新打开之前的版本。")
    }
    static var updateAlreadyInProgress: String {
        text("An update operation is already in progress.", "更新操作正在进行中。")
    }
    static var updateInvalidResponse: String {
        text("The update server returned an invalid response.", "更新服务器返回了无效响应。")
    }
    static var updateInvalidRelease: String {
        text("The latest release metadata is invalid.", "最新版本的元数据无效。")
    }
    static func updateMissingAsset(_ name: String) -> String {
        text("The release is missing \(name).", "该版本缺少 \(name)。")
    }
    static var updateMissingDigest: String {
        text("The release does not include a valid SHA-256 digest.",
             "该版本未提供有效的 SHA-256 摘要。")
    }
    static var updateUntrustedURL: String {
        text("The release download URL is not trusted.", "版本下载地址不受信任。")
    }
    static var updateDownloadFailed: String {
        text("The update could not be downloaded.", "无法下载更新。")
    }
    static var updateChecksumFailed: String {
        text("The downloaded update failed SHA-256 verification.",
             "下载的更新未通过 SHA-256 校验。")
    }
    static func updateDiskImageFailed(_ detail: String) -> String {
        text("The update disk image could not be opened: \(detail)",
             "无法打开更新磁盘映像：\(detail)")
    }
    static var updateMissingApp: String {
        text("The update does not contain Pesty.app.", "更新包中没有 Pesty.app。")
    }
    static var updateInvalidBundle: String {
        text("The update has an invalid application identity.", "更新的应用身份无效。")
    }
    static func updateVersionMismatch(_ version: String) -> String {
        text("The update contains unexpected version \(version).",
             "更新包中的版本 \(version) 与预期不符。")
    }
    static var updateInvalidArchitecture: String {
        text("The update is not a Universal Apple Silicon and Intel build.",
             "更新不是同时支持 Apple Silicon 和 Intel 的通用构建。")
    }
    static func updateSignatureFailed(_ detail: String) -> String {
        text("The update failed code-signature verification: \(detail)",
             "更新未通过代码签名校验：\(detail)")
    }
    static var updateAppNotWritable: String {
        text("Pesty cannot replace its current application. Reinstall it in Applications using your user account.",
             "Pesty 无法替换当前应用。请使用当前用户将它重新安装到“应用程序”。")
    }
    static var updateHelperFailed: String {
        text("The update installer could not be prepared.", "无法准备更新安装程序。")
    }
    static var updateMountPointMissing: String {
        text("The mounted update has no readable volume.", "挂载的更新没有可读取的卷。")
    }
    static var updateUnknownError: String {
        text("Unknown update error", "未知更新错误")
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
    static let pestyMenuBarIconVisibilityDidChange =
        Notification.Name("PestyMenuBarIconVisibilityDidChange")
    static let pestyUpdateStateDidChange =
        Notification.Name("PestyUpdateStateDidChange")
}
