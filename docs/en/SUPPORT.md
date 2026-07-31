[中文文档](../README.md) | [English Docs](README.md) | [中文版本](../SUPPORT.md)

# Pesty Support and Troubleshooting

## Report an Issue

Submit issues through
[GitHub Issues](https://github.com/bifrost-proxy/pesty/issues). Please include:

- Pesty version and build number
- macOS version and Mac processor type
- Steps that reproduce the problem consistently
- Screenshots or error messages that contain no real clipboard content

Never paste passwords, tokens, personal file contents, or other sensitive
clipboard data into a public issue.

## Pesty Does Not Record Newly Copied Content

1. Confirm that Pesty is running and try pressing `⌘⇧V` to open the panel.
2. Check for the latest version under “Settings → About.”
3. Content marked as concealed by password managers is intentionally ignored.
4. Check “History limit.” Older records are removed after the limit is exceeded.
5. If iCloud is enabled, wait for the storage migration to finish before testing again after changing sync state.

If the history panel consistently shows only the latest item, update to the
latest release and restart Pesty twice. If the problem continues, submit an
issue and report the number of records visible after each restart.

## Pesty Cannot Paste Directly into Another App

Open Settings, confirm that “Paste directly into the active app” is enabled,
and grant Pesty permission in the Accessibility section. If the status does not
refresh after authorization, restart Pesty.

Without Accessibility permission, Pesty can still place the selected content
on the system clipboard so you can paste manually with `⌘V`.

## The Menu-Bar Icon Is Missing

The menu-bar icon may have been disabled in Settings. Reopen Pesty from
Applications to display Settings again, then enable “Show menu bar icon.”

## iCloud Sync Is Unavailable

Confirm that:

- The current Mac is signed in to iCloud.
- iCloud Drive is enabled in System Settings.
- “Sync clipboard via iCloud Drive” is enabled in Pesty.
- The network and iCloud Drive itself are working normally.

Pesty uses only your personal iCloud Drive. Project maintainers cannot access
the data stored there.

## Update Checks Fail

Pesty checks the public GitHub Releases Feed and does not use the anonymous
GitHub REST API quota. Confirm that the current network can reach `github.com`,
then check again under “Settings → About.”

If the problem continues, submit an issue with the error message, Pesty
version, and time of failure. Do not attach clipboard history or other
sensitive data.

## Clear Clipboard History

Open “Settings → Data” and click “Clear Clipboard History.” This removes
history from the currently active storage location. Confirm that you no longer
need the records before continuing.

## Uninstall Pesty

For a Homebrew installation:

```bash
brew uninstall --cask pesty
```

For a DMG installation, quit Pesty and move `Pesty.app` from Applications to
the Trash.

To remove local data as well, first confirm that the history is no longer
needed, then handle these paths manually:

- `~/Library/Application Support/Pesty`
- `~/Library/Preferences/com.bifrostproxy.pesty.plist`

If iCloud sync is enabled, assess the data in iCloud Drive separately. Do not
delete it directly while multiple devices are still synchronizing.
