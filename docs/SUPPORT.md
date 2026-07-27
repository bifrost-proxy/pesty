# Pesty 常见问题与故障排查

## 如何反馈问题

请在 [GitHub Issues](https://github.com/bifrost-proxy/pesty/issues) 提交问题。
建议包含：

- Pesty 版本和 build 号
- macOS 版本与 Mac 处理器类型
- 可以稳定复现问题的操作步骤
- 不包含真实剪贴板内容的截图或错误信息

请勿在公开 Issue 中粘贴密码、令牌、个人文件内容或其他敏感剪贴板数据。

## Pesty 没有记录新复制的内容

1. 确认 Pesty 正在运行，并尝试按 `⌘⇧V` 打开面板。
2. 在“设置 → 关于”中检查是否已经使用最新版本。
3. 密码管理器标记为隐藏的内容会被主动忽略，这是预期行为。
4. 检查“历史记录上限”；超过上限的旧记录会被移除。
5. 如果启用了 iCloud，同步切换期间请等待存储迁移完成后再次测试。

如果历史面板始终只显示最后一条，请升级到最新版本后重新启动两次；问题仍存在
时再提交 Issue，并说明每次重启后面板中可见的记录数量。

## 无法直接粘贴到其他应用

打开“设置”，确认“直接粘贴到当前应用”已启用，并在“辅助功能”区域授予 Pesty
权限。授权后如果状态没有刷新，请重新启动 Pesty。

没有辅助功能权限时，Pesty 仍会把选中的内容写回系统剪贴板，你可以手动按
`⌘V` 粘贴。

## 找不到菜单栏图标

菜单栏图标可能已在设置中关闭。从“应用程序”中再次打开 Pesty，会重新显示设置
窗口；在其中启用“显示菜单栏图标”即可。

## iCloud 同步不可用

确认：

- 当前 Mac 已登录 iCloud。
- 系统设置中已经启用 iCloud Drive。
- Pesty 的“通过 iCloud Drive 同步剪贴板”设置已开启。
- 网络和 iCloud Drive 本身工作正常。

Pesty 只使用你的个人 iCloud Drive；项目维护者无法访问其中的数据。

## 检查更新失败

Pesty 通过公开的 GitHub Releases Feed 检查版本，不使用匿名 GitHub REST API
配额。请确认当前网络能够访问 `github.com`，然后在“设置 → 关于”中重新检查。

如果问题持续存在，请提交 Issue，并附上错误提示、Pesty 版本和发生时间。不要
附带剪贴板历史或其他敏感数据。

## 如何清除历史记录

打开“设置 → 数据”，点击“清除剪贴板历史记录”。该操作会清除当前启用存储中的
历史记录，请在操作前确认不再需要这些内容。

## 如何卸载

Homebrew 安装：

```bash
brew uninstall --cask pesty
```

DMG 安装：退出 Pesty，然后将“应用程序”中的 `Pesty.app` 移到废纸篓。

如需同时删除本地数据，可在确认不再需要历史记录后手动处理：

- `~/Library/Application Support/Pesty`
- `~/Library/Preferences/com.bifrostproxy.pesty.plist`

启用 iCloud 同步时，iCloud Drive 中的数据需要单独评估；不要在多台设备仍在同步
时直接删除。
