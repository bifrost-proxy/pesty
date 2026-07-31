[中文文档](../README.md) | [English Docs](README.md) | [中文版本](../PRIVACY.md)

# Pesty Privacy Notice

Last updated: July 31, 2026

Pesty is a clipboard history app for macOS. Clipboard content stays on your Mac
by default. The project provides no clipboard cloud service, account system,
advertising, analytics, or telemetry. Selected text is sent directly to a
user-configured cloud AI service only when the user explicitly invokes
translation or explanation.

## Data Stored by Pesty

To help you reuse copied content, Pesty can store text, links, images, files,
rich text, colors, Pinboards, and related display information.

Local data is stored by default in:

- `~/Library/Application Support/Pesty`
- `~/Library/Preferences/com.bifrostproxy.pesty.plist`

Content marked as concealed or hidden by password managers is ignored and
never added to history.

## Optional iCloud Sync

iCloud sync is off by default. When enabled, history, Pinboards, and the history
retention limit are stored in your own iCloud Drive and synchronized between
your Macs through Apple’s iCloud service. Project maintainers have no server
or account access to that data.

## Network Access

Pesty does not send clipboard content to project maintainers or third-party
analytics services. The app accesses the network only for these product
features:

- When the user explicitly uses Doubao to translate or explain selected text.
- When the user explicitly uses a compatible AI service to explain selected text.
- At launch, every hour, or during a manual update check, to read the public GitHub Releases Feed.
- After the user confirms an update, to download the release from GitHub Releases.
- When the user clicks GitHub or “Report an Issue” links, which open in the system browser.
- After the user explicitly enables iCloud sync, which is handled by macOS and iCloud Drive.

Cloud translation and explanation send only the text the user explicitly asks
Pesty to process. They never bulk-upload clipboard history, Pinboard content,
or user files. API keys are stored in macOS Keychain and are not written to
preferences or iCloud. Update requests contain no clipboard history, Pinboard
content, or user file contents.

## Accessibility Permission

“Paste directly into the active app” uses macOS Accessibility permission to
send the paste shortcut to the previously active app. When the user explicitly
invokes global translation or explanation, Pesty also uses Accessibility to
read the current text selection and its location so it can process the text
and place the result near the selection.

If an app does not expose its selection directly, Pesty may issue a temporary
Copy command, read the selected text, and then fully restore the original
clipboard. The temporary text is not written to history. Pesty does not read
secure text fields and does not use Accessibility to continuously collect
window contents, keystrokes, or other app data.

## Data Control

You can clear clipboard history under “Settings → Data.” Uninstalling Pesty
does not automatically remove all local or iCloud data. When necessary, follow
the [uninstallation instructions](SUPPORT.md#uninstall-pesty) and confirm that
the data is no longer needed before deleting it.

## Contact

Submit privacy questions through
[GitHub Issues](https://github.com/bifrost-proxy/pesty/issues). Never include
real clipboard content or other sensitive information in a public issue.
