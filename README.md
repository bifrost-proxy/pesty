![Pesty 图标](docs/assets/icon.png)

# Pesty

一款原生、轻量、开源的 macOS 剪贴板历史工具。

[![最新版本](https://img.shields.io/github/v/release/bifrost-proxy/pesty?label=release&style=flat-square)](https://github.com/bifrost-proxy/pesty/releases/latest)
[![许可证](https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square)](LICENSE)
![系统要求](https://img.shields.io/badge/macOS-14%2B-black?style=flat-square&logo=apple)
![处理器](https://img.shields.io/badge/Apple%20Silicon%20%2B%20Intel-universal-orange?style=flat-square)

![Pesty 剪贴板历史面板演示](docs/assets/demo.gif)

## 产品介绍

Pesty 会在本机保存剪贴板历史。按下全局快捷键后，屏幕底部会显示剪贴板面板，可以搜索、选择并重新粘贴之前复制过的内容。

数据默认仅保存在本机。应用不会上传剪贴板内容，也不会接入分析或遥测服务。用户可以选择通过自己的 iCloud Drive 在多台 Mac 之间同步历史记录、Pinboard 和历史记录上限。

## 主要功能

- 支持文本、富文本、链接、图片、文件和颜色。
- 支持搜索、键盘导航和 `⌘1` 至 `⌘9` 快速粘贴。
- 支持 Pinboard，可长期保存常用内容。
- 根据来源应用显示图标和颜色。
- 可忽略密码管理器标记为隐藏的剪贴板内容。
- 可隐藏菜单栏图标；隐藏后重新从“应用程序”打开 Pesty 即可进入设置。
- 启动时及每小时自动检查更新，也支持手动检查；发现新版本后可在菜单栏
  或剪贴板面板中一键安装并重启。
- 正式版和 Beta 更新通道相互隔离，正式用户不会收到 Beta 版本。
- 自动跟随 macOS 系统外观，在亮色和暗色主题间切换。
- 支持中文和英文，并可在设置中即时切换。
- 原生 Swift 和 SwiftUI 实现，不依赖第三方运行时。
- 同时支持 Apple Silicon 和 Intel Mac。

## 安装

系统要求：macOS 14 Sonoma 或更高版本。

推荐使用 Homebrew 安装：

```bash
brew install --cask bifrost-proxy/pesty/pesty
```

也可以从 [GitHub Releases](https://github.com/bifrost-proxy/pesty/releases/latest) 下载 `Pesty-x.y.z.dmg`，将 `Pesty.app` 拖入“应用程序”目录。

> 当前社区发布不使用 Apple Developer ID 证书，因此发布包采用 ad-hoc 签名，无法获得 Apple 公证。Homebrew Cask 会先校验发布包 SHA-256，再移除隔离属性，以便正常启动。直接下载 DMG 时，需要在“系统设置 → 隐私与安全性”中确认打开，或自行移除隔离属性。

## 使用

1. 启动 Pesty。应用会常驻菜单栏。
2. 默认按 `⌘⇧V` 打开或关闭剪贴板面板。
3. 使用方向键选择内容，按 `Return` 粘贴。
4. 首次直接粘贴时，按照系统提示授予“辅助功能”权限。
5. 在“设置”中可以修改快捷键、历史记录数量、启动行为、菜单栏图标、iCloud 同步和界面语言。
6. 隐藏菜单栏图标后，可以从“应用程序”中再次打开 Pesty，重新唤起设置页面。
7. 菜单栏图标显示时，新版本会显示在菜单栏菜单中；图标隐藏时，新版本会显示在
   剪贴板面板顶部。点击更新按钮后，Pesty 会校验并安装更新，然后自动重启。

常用快捷键：

| 快捷键 | 功能 |
| --- | --- |
| `⌘⇧V` | 打开或关闭面板，可在设置中修改 |
| `←` `→` `↑` `↓` | 移动选择 |
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
- [常见问题与故障排查](docs/SUPPORT.md)
- [隐私说明](docs/PRIVACY.md)
- [参与开发](CONTRIBUTING.md)
- [版本记录](CHANGELOG.md)

Pesty 不维护独立宣传站点。项目文档均以 Markdown 保存在本仓库中。

## 许可证

[MIT](LICENSE)。本项目基于 `momenbasel/pesty` 派生，原始作者的版权与许可证声明继续保留。
