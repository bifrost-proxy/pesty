[中文 README](README.md) | [English README](README_EN.md) | [中文文档](docs/README.md) | [English Docs](docs/en/README.md)

# Pesty

一款原生、轻量、开源的 macOS 剪贴板历史工具。

[![最新版本](https://img.shields.io/github/v/release/bifrost-proxy/pesty?label=release&style=flat-square)](https://github.com/bifrost-proxy/pesty/releases/latest)
[![累计下载](https://img.shields.io/github/downloads/bifrost-proxy/pesty/total?style=flat-square)](https://github.com/bifrost-proxy/pesty/releases)
[![许可证](https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square)](LICENSE)
![系统要求](https://img.shields.io/badge/macOS-14%2B-black?style=flat-square&logo=apple)
![处理器](https://img.shields.io/badge/Apple%20Silicon%20%2B%20Intel-universal-orange?style=flat-square)

![Pesty 剪贴板历史面板演示](docs/assets/demo.gif)

## 产品介绍

Pesty 会在本机保存剪贴板历史。按下全局快捷键后，屏幕底部会显示剪贴板面板，可以搜索、选择并重新粘贴之前复制过的内容。

数据默认仅保存在本机，应用不接入分析或遥测服务。只有当用户主动调用翻译或解释，
并选择自己配置的云端 AI 服务时，当前选中的文本才会直接发送给该服务。用户还可以
选择通过自己的 iCloud Drive 在多台 Mac 之间同步历史记录、Pinboard 和历史记录上限。

## 功能与用法

| 功能 | 基础介绍 | 怎么使用 |
| --- | --- | --- |
| 剪贴板历史 | 自动记录文本、富文本、链接、图片、文件和颜色，并显示来源应用、复制时间和内容类型。重复复制同一内容时会将它移到最前面。 | 正常使用 `⌘C` 复制即可；按 `⌘⇧V` 打开历史面板。 |
| 查找与选择 | 可以按内容、自定义标题、来源应用、文件路径或颜色值搜索，并使用键盘在结果间移动。 | 面板打开后直接输入搜索词；使用方向键选择，按 `Esc` 清空搜索。 |
| 内容预览 | 在不粘贴的情况下放大查看当前卡片，适合长文本、图片、链接和文件等内容。 | 选中卡片后按 `Space` 打开或关闭预览；切换卡片时预览会跟随选择。 |
| 粘贴与复制 | 可以直接粘贴回之前使用的应用，也可以只把内容复制回系统剪贴板。 | 选中后按 `Return`、双击卡片或按 `⌘1` 至 `⌘9` 快速粘贴；右键卡片选择“复制”可只复制不粘贴。直接粘贴需要辅助功能权限。 |
| 翻译 | 可以翻译任意应用中选中的文字，也可以翻译 Pesty 内含有文本的卡片；支持自动识别原文语言、交换语言和选择目标语言。macOS 15 及以上可使用 Apple Translation；macOS 14 或需要云端模型时可自行配置豆包。 | 在其他应用中选中文字后按 `⇧⌘T`；在 Pesty 中选中文本卡片后也可按 `⇧⌘T`，或右键选择“翻译”。详见[翻译功能使用指南](docs/TRANSLATION.md)。 |
| 内容解释 | 可以让已配置的大模型解释任意应用中选中的文字或 Pesty 的文本卡片，结果支持 Markdown 和复制。 | 在“设置 → 翻译&解释”中配置豆包或 OpenAI 兼容服务，选中文字后按 `⇧⌘D`；Pesty 卡片还可通过右键菜单调用。OpenAI 兼容服务当前用于解释，不用于翻译。 |
| Pinboard | 将需要长期保留或分类复用的内容保存到一个或多个 Pinboard，不受清空普通历史记录影响。 | 右键卡片，保存到已有 Pinboard 或新建 Pinboard；在面板顶部切换、重命名或删除 Pinboard。 |
| 卡片管理 | 支持自定义卡片标题、删除单条记录和清空全部普通历史记录。 | 右键卡片可编辑标题或删除；`⌘⌫` 删除当前卡片；在“设置 → 通用 → 数据”中清空历史。完整清空前会要求确认，且不会删除 Pinboard。 |
| 历史保留与存储 | 新安装默认保留 5,000 条，可选择 100 至 10,000 条或不限数量；设置页会显示当前记录数和数据目录占用空间。 | 在“设置 → 通用”中查看记录与存储信息并调整“历史记录上限”。降低上限后不会立即删除，短暂宽限期内仍可改回。 |
| iCloud 同步 | 可选地通过用户自己的 iCloud Drive 同步历史、Pinboard 和历史记录上限。快捷键、界面和设备权限等设置仍分别保存在每台 Mac。 | 先在 macOS 登录 iCloud 并启用 iCloud Drive，再在“设置 → 通用 → 同步”中打开。 |
| 隐私与安全 | 历史默认只保存在本机；可忽略密码管理器标记为隐藏的内容。云端翻译或解释只发送用户主动处理的当前文本，API Key 保存在 macOS 钥匙串。 | 在“设置 → 通用”中启用“忽略隐藏内容”；是否使用 iCloud 或云端 AI 由用户自行选择。 |
| 外观与行为 | 自动跟随系统亮色/暗色外观，并可调整面板高度、提示音、登录启动、菜单栏图标和中英文界面。 | 在“设置 → 通用”中调整。隐藏菜单栏图标后，从“应用程序”再次打开 Pesty 即可重新进入设置。 |
| 应用更新 | 启动时和每小时检查 GitHub Releases，也支持手动检查和应用内安装。Stable 与 Beta 更新通道相互隔离。 | 在“设置 → 关于”手动检查；有新版本时，从菜单栏菜单或剪贴板面板顶部点击更新。 |

## 安装

系统要求：macOS 14 Sonoma 或更高版本。

推荐使用 Homebrew 安装：

```bash
brew install --cask bifrost-proxy/pesty/pesty
```

也可以从 [GitHub Releases](https://github.com/bifrost-proxy/pesty/releases/latest) 下载 `Pesty-x.y.z.dmg`，将 `Pesty.app` 拖入“应用程序”目录。

> 当前社区发布不使用 Apple Developer ID 证书，因此发布包采用 ad-hoc 签名，无法获得 Apple 公证。Homebrew Cask 会先校验发布包 SHA-256，再移除隔离属性，以便正常启动。直接下载 DMG 时，需要在“系统设置 → 隐私与安全性”中确认打开，或自行移除隔离属性。

## 快速开始

1. 启动 Pesty。应用会常驻菜单栏。
2. 正常复制几条内容，默认按 `⌘⇧V` 打开剪贴板面板。
3. 使用方向键选择内容，按 `Return` 或双击卡片粘贴。
4. 首次直接粘贴时，按照系统提示授予“辅助功能”权限；不授权时仍可右键选择“复制”，再手动按 `⌘V`。
5. 直接输入文字搜索，按 `Space` 查看完整预览，按 `Esc` 清空搜索或关闭面板。
6. 要直接处理其他应用中的文字，选中文字后按 `⇧⌘T` 翻译或按 `⇧⌘D` 解释；首次使用时按提示授予辅助功能权限。
7. 打开“设置”可修改三个功能页中的选项：
   - “通用”：打开面板的快捷键、历史记录上限、粘贴行为、启动与菜单栏、面板高度、iCloud、界面语言和数据清理。
   - “翻译&解释”：翻译语言与服务、翻译和解释快捷键、豆包及 OpenAI 兼容服务。
   - “关于”：版本信息、检查更新和问题反馈。

常用快捷键：

| 快捷键 | 功能 |
| --- | --- |
| `⌘⇧V` | 打开或关闭面板，可在设置中修改 |
| `⇧⌘T` | 全局翻译当前选中的文字；Pesty 面板打开时翻译当前文本卡片，可在设置中修改 |
| `⇧⌘D` | 全局解释当前选中的文字；Pesty 面板打开时解释当前文本卡片，可在设置中修改 |
| `T` | 翻译看板打开且原文语言明确时，交换原文和目标语言 |
| `←` `→` `↑` `↓` | 移动选择 |
| `Space` | 预览或关闭预览当前内容 |
| `Return` | 粘贴当前内容 |
| `⌘1` 至 `⌘9` | 快速粘贴对应位置的内容 |
| `⌘⌫` | 删除当前内容 |
| 直接输入 | 搜索历史记录 |
| `Esc` | 清空搜索，再次按下时关闭面板 |

## 本地开发

需要 Xcode 16 或兼容的 Swift 6 工具链。

```bash
git clone https://github.com/bifrost-proxy/pesty.git
cd pesty
swift build
swift run Pesty --verify-localization
swift run Pesty --verify-translation
swift run Pesty --verify-appearance
swift run Pesty --verify-updater
swift run
```

构建可分发的通用应用和 DMG：

```bash
VERSION=1.2.0 BUILD=1 ./scripts/release_build.sh
./scripts/verify_release.sh 1.2.0
```

构建过程会生成 ad-hoc 签名的 `packaging/Pesty.app` 和 `packaging/Pesty-1.2.0.dmg`，并验证签名、Bundle ID、版本号及双架构。

通用构建需要完整 Xcode。仅安装 Command Line Tools 时，可以验证当前 Mac 架构：

```bash
ARCHS=arm64 VERSION=1.2.0 BUILD=1 ./scripts/release_build.sh
EXPECTED_ARCHS=arm64 ./scripts/verify_release.sh 1.2.0
```

## 正式发布

正式版本使用 `vMAJOR.MINOR.PATCH` 标签，Beta 使用
`vMAJOR.MINOR.PATCH-beta.N`。标签必须指向 `main` 可达的提交。GitHub
Actions 会自动执行测试、构建通用 DMG、验证 ad-hoc 签名、生成 Homebrew
Cask，并把 Beta 标签创建为 GitHub Prerelease。

Homebrew tap 位于 `bifrost-proxy/homebrew-pesty`。Release 附带生成后的 `pesty.rb`，tap 更新后即可通过上面的安装命令获取对应版本。

## 数据位置

- 历史记录与 Pinboard：`~/Library/Application Support/Pesty`
- 设置：`~/Library/Preferences/com.bifrostproxy.pesty.plist`

## 文档

- [使用指南](docs/USER_GUIDE.md)
- [翻译功能使用指南](docs/TRANSLATION.md)
- [常见问题与故障排查](docs/SUPPORT.md)
- [隐私说明](docs/PRIVACY.md)
- [参与开发](CONTRIBUTING.md)
- [版本记录](CHANGELOG.md)

Pesty 不维护独立宣传站点。项目文档均以 Markdown 保存在本仓库中。

## 许可证

[MIT](LICENSE)。本项目基于 `momenbasel/pesty` 派生，原始作者的版权与许可证声明继续保留。
