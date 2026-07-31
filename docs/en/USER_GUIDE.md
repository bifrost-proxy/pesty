[中文文档](../README.md) | [English Docs](README.md) | [中文版本](../USER_GUIDE.md)

# Pesty User Guide

Pesty automatically follows the macOS system appearance and switches between
light and dark modes without additional configuration.

## System Requirements

- macOS 14 Sonoma or later
- Apple Silicon or Intel Mac

## Installation

The recommended installation method is Homebrew:

```bash
brew install --cask bifrost-proxy/pesty/pesty
```

You can also download the DMG from
[GitHub Releases](https://github.com/bifrost-proxy/pesty/releases/latest) and
drag `Pesty.app` into Applications.

Community releases use an ad-hoc signature and are not notarized by Apple. The
Homebrew Cask verifies the SHA-256 and removes the quarantine attribute. When
installing directly from the DMG, macOS may require you to approve the app
under “System Settings → Privacy & Security.”

## Basic Usage

1. Launch Pesty. By default, it appears in the menu bar.
2. Copy text, links, images, files, rich text, or colors.
3. Press `⌘⇧V` to open the clipboard panel.
4. Use the arrow keys to select content and press `Return` to paste it.
5. Start typing to search history. Press `Esc` once to clear the search and again to close the panel.

Common shortcuts:

| Shortcut | Action |
| --- | --- |
| `⌘⇧V` | Open or close the panel; customizable in Settings |
| `⇧⌘T` | Globally translate selected text, or translate the selected text card while the panel is open; customizable in Settings |
| `⇧⌘D` | Globally explain selected text, or explain the selected text card while the panel is open; customizable in Settings |
| `T` | Swap source and target languages while the translation board is open and the source language is explicit |
| `←` `→` `↑` `↓` | Move the selection |
| `Space` | Open or close the preview for the selected item |
| `Return` | Paste the selected item |
| `⌘1` through `⌘9` | Quickly paste the item at that position |
| `⌘⌫` | Delete the selected item |
| Start typing | Search clipboard history |
| `Esc` | Clear the search or close the panel |

## Settings

Open Settings from the menu-bar menu to configure:

- Global shortcuts and the history limit
- Whether to paste directly into the active app
- Whether to ignore content marked as concealed by password managers
- Paste sound, launch at login, and menu-bar icon visibility
- Panel height
- Translation source and target languages, plus translation and explanation shortcuts
- Apple Translation, Doubao, and reusable compatible AI provider settings
- iCloud Drive sync
- Chinese or English interface language
- Clipboard history clearing

If the menu-bar icon is hidden, reopen Pesty from Applications to return to
Settings.

## Translation and Explanation

Select text in any app and press `⇧⌘T` to translate it or `⇧⌘D` to receive a
concise explanation. Reading selected text globally requires Accessibility
permission. Pesty does not read secure text fields.

You can use the same shortcuts after selecting a text card in Pesty, or choose
“Translate” or “Explain” from the card’s context menu. Results appear near the
selection or card. Click outside the result board to dismiss it.

- Apple Translation is available on macOS 15 and later.
- Apple Translation requires the relevant language packs, which you can inspect and download under “Settings → Translate & Explain.”
- Doubao translation or explanation requires a model and API key under “Settings → Translate & Explain.”
- OpenAI-compatible services currently power explanation only and require an endpoint, model, and API key.
- API keys are stored in macOS Keychain, not in Pesty preferences or iCloud.
- Cloud services receive only the text the user explicitly asks Pesty to process.

For service selection, Doubao configuration, supported languages, result
actions, and troubleshooting, see the [Translation Guide](TRANSLATION.md).

## Accessibility Permission

“Paste directly into the active app” requires macOS Accessibility permission.
Pesty uses that permission to send the paste shortcut to the previously active
app. Without permission, you can still select content in Pesty, copy it, and
paste manually.

Global translation and explanation also use Accessibility to read the text
selection only when you explicitly invoke the corresponding shortcut.

## iCloud Sync

iCloud sync is off by default. When enabled, Pesty uses your own iCloud Drive
to sync history, Pinboards, and the history limit between Macs. The retention
limit uses the most recently modified configuration and a shared effective
time so devices do not repeatedly delete and restore over-limit records.

Shortcuts, launch-at-login behavior, Accessibility permission, menu-bar
visibility, panel height, and interface language remain local to each Mac.
Sign in to iCloud and enable iCloud Drive in System Settings before turning
sync on.

## App Updates

Pesty checks for updates at launch and every hour. You can also check manually
under “Settings → About.”

- When the menu-bar icon is visible, the update action appears in its menu.
- When the icon is hidden, the update action appears at the top of the clipboard panel.
- Pesty downloads and verifies the release, replaces the app, and restarts automatically.
- Stable and Beta channels remain isolated. Stable builds never receive Betas, and Beta builds update only to later Betas.

For more help, see [Support and Troubleshooting](SUPPORT.md).
