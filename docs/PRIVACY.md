# Pesty 隐私说明

最后更新：2026 年 7 月 27 日

Pesty 是一款 macOS 剪贴板历史工具。剪贴板内容默认只保存在本机；项目不提供
剪贴板云服务、账号系统、广告、分析或遥测。

## Pesty 保存什么

为了让你重新使用复制过的内容，Pesty 可以保存文本、链接、图片、文件、富文本和
颜色，以及 Pinboard 和相关显示信息。

本地数据默认保存在：

- `~/Library/Application Support/Pesty`
- `~/Library/Preferences/com.bifrostproxy.pesty.plist`

密码管理器标记为 concealed/隐藏的剪贴板内容会被忽略，不会写入历史记录。

## 可选的 iCloud 同步

iCloud 同步默认关闭。启用后，历史记录和 Pinboard 会存入你自己的 iCloud Drive，
并通过 Apple 的 iCloud 服务在你的 Mac 之间同步。项目维护者没有访问这些数据的
服务器或账号权限。

## 网络访问

Pesty 不会把剪贴板内容发送给项目维护者或第三方分析服务。应用只在以下产品功能
中访问网络：

- 启动时、每小时或手动检查更新时，读取公开的 GitHub Releases Feed。
- 用户确认安装更新后，从 GitHub Releases 下载发布包。
- 用户点击 GitHub 或“反馈问题”链接后，由系统浏览器打开相应页面。
- 用户主动启用 iCloud 同步后，由 macOS 和 iCloud Drive 处理同步。

更新请求不包含剪贴板历史、Pinboard 内容或用户文件内容。

## 辅助功能权限

“直接粘贴到当前应用”可以使用 macOS 辅助功能权限，向之前正在使用的应用发送
粘贴快捷键。Pesty 不使用该权限采集窗口内容、键盘输入或其他应用数据。

## 数据控制

可以在“设置 → 数据”中清除剪贴板历史。卸载应用不会自动删除所有本地或 iCloud
数据；需要时请参考[卸载说明](SUPPORT.md#如何卸载)并在删除前确认数据不再需要。

## 联系方式

隐私问题可以通过
[GitHub Issues](https://github.com/bifrost-proxy/pesty/issues) 提交。请勿在公开
Issue 中附带真实剪贴板内容或其他敏感信息。
