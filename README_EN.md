[中文 README](README.md) | [English README](README_EN.md) | [中文文档](docs/README.md) | [English Docs](docs/en/README.md)

# Pesty

A native, lightweight, open-source clipboard history app for macOS.

[![Latest Release](https://img.shields.io/github/v/release/bifrost-proxy/pesty?label=release&style=flat-square)](https://github.com/bifrost-proxy/pesty/releases/latest)
[![Total Downloads](https://img.shields.io/github/downloads/bifrost-proxy/pesty/total?style=flat-square)](https://github.com/bifrost-proxy/pesty/releases)
[![License](https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square)](LICENSE)
![Requirements](https://img.shields.io/badge/macOS-14%2B-black?style=flat-square&logo=apple)
![Architectures](https://img.shields.io/badge/Apple%20Silicon%20%2B%20Intel-universal-orange?style=flat-square)

![Pesty clipboard history panel demo](docs/assets/demo.gif)

## Overview

Pesty keeps a local history of your clipboard. Press the global shortcut to open
a panel at the bottom of the screen, where you can search, select, and paste
previously copied content.

Data stays on your Mac by default, and the app includes no analytics or
telemetry. Text is sent directly to a user-configured cloud AI service only when
the user explicitly invokes translation or explanation. You can also optionally
sync history, Pinboards, and the history limit between Macs through your own
iCloud Drive.

## Features and Usage

| Feature | What it does | How to use it |
| --- | --- | --- |
| Clipboard history | Automatically records text, rich text, links, images, files, and colors, together with the source app, copy time, and content type. Copying identical content again moves it to the front. | Copy normally with `⌘C`, then press `⌘⇧V` to open the history panel. |
| Search and selection | Searches content, custom titles, source apps, file paths, and color values, with full keyboard navigation. | Start typing while the panel is open, use the arrow keys to select an item, and press `Esc` to clear the search. |
| Content preview | Opens a larger view without pasting, which is useful for long text, images, links, files, and other content. | Select a card and press `Space` to open or close its preview. The preview follows the current selection. |
| Paste and copy | Pastes directly back into the previously active app, or copies an item to the system clipboard without pasting it. | Press `Return`, double-click a card, or use `⌘1` through `⌘9` to paste quickly. Choose “Copy” from the card’s context menu to copy only. Direct paste requires Accessibility permission. |
| Translation | Translates selected text in any app or a text-bearing Pesty card. It supports automatic source-language detection, language swapping, and a configurable target language. Apple Translation is available on macOS 15 and later; Doubao can be configured for macOS 14 or cloud-model use. | Select text in another app and press `⇧⌘T`. In Pesty, select a text card and press `⇧⌘T` or choose “Translate” from its context menu. See the [Translation Guide](docs/en/TRANSLATION.md). |
| Explanation | Uses a configured language model to explain selected text from any app or a Pesty text card. Results support Markdown and copying. | Configure Doubao or an OpenAI-compatible service under “Settings → Translate & Explain,” select text, and press `⇧⌘D`. Pesty cards also expose an “Explain” context-menu action. OpenAI-compatible services currently power explanation, not translation. |
| Pinboard | Keeps frequently reused or categorized content in one or more Pinboards. Pinboard content is not removed when normal history is cleared. | Right-click a card to save it to a new or existing Pinboard. Use the tabs at the top of the panel to switch, rename, or delete Pinboards. |
| Card management | Supports custom card titles, deleting individual records, and clearing all normal history. | Right-click a card to edit its title or delete it. Use `⌘⌫` to delete the selected card, or clear history under “Settings → General → Data.” Full clearing requires confirmation and does not delete Pinboards. |
| Retention and storage | New installations keep 5,000 items by default. You can choose 100 through 10,000 items or unlimited storage. Settings shows the current item count and data-directory size. | View storage information and change “History limit” under “Settings → General.” Lowering the limit uses a short grace period before deletion. |
| iCloud sync | Optionally syncs history, Pinboards, and the history limit through your own iCloud Drive. Shortcuts, appearance, and device permissions stay local to each Mac. | Sign in to iCloud and enable iCloud Drive in macOS, then turn on sync under “Settings → General → Sync.” |
| Privacy and security | History stays local by default, and Pesty can ignore content marked as concealed by password managers. Cloud translation and explanation send only the text the user explicitly processes. API keys are stored in macOS Keychain. | Enable “Ignore concealed content” under “Settings → General.” iCloud and cloud AI services remain opt-in. |
| Appearance and behavior | Follows the system light or dark appearance and supports panel height, sound, launch-at-login, menu-bar visibility, and Chinese or English UI settings. | Adjust these options under “Settings → General.” If the menu-bar icon is hidden, reopen Pesty from Applications to return to Settings. |
| App updates | Checks GitHub Releases at launch and every hour, with manual checks and in-app installation. Stable and Beta channels remain isolated. | Check manually under “Settings → About.” When an update is available, install it from the menu-bar menu or the top of the clipboard panel. |

## Installation

Requires macOS 14 Sonoma or later.

The recommended installation method is Homebrew:

```bash
brew install --cask bifrost-proxy/pesty/pesty
```

You can also download `Pesty-x.y.z.dmg` from
[GitHub Releases](https://github.com/bifrost-proxy/pesty/releases/latest) and
drag `Pesty.app` into Applications.

> Community releases are ad-hoc signed because the project does not use an
> Apple Developer ID certificate, so they cannot be notarized by Apple. The
> Homebrew Cask verifies the release SHA-256 and removes the quarantine
> attribute. For direct DMG downloads, you may need to approve the app under
> “System Settings → Privacy & Security” or remove the quarantine attribute
> yourself.

## Quick Start

1. Launch Pesty. By default, it remains available in the menu bar.
2. Copy a few items and press `⌘⇧V` to open the clipboard panel.
3. Use the arrow keys to select an item, then press `Return` or double-click the card to paste it.
4. When using direct paste for the first time, grant Accessibility permission when prompted. Without it, you can still choose “Copy” and paste manually with `⌘V`.
5. Start typing to search, press `Space` for a full preview, and press `Esc` to clear the search or close the panel.
6. To work directly with text in another app, select it and press `⇧⌘T` to translate or `⇧⌘D` to explain. Grant Accessibility permission when prompted.
7. Open Settings to configure its three panes:
   - General: panel shortcut, history limit, paste behavior, launch and menu-bar behavior, panel height, iCloud, UI language, and data clearing.
   - Translate & Explain: languages, services, translation and explanation shortcuts, Doubao, and OpenAI-compatible providers.
   - About: version information, update checks, and issue reporting.

Common shortcuts:

| Shortcut | Action |
| --- | --- |
| `⌘⇧V` | Open or close the panel; customizable in Settings |
| `⇧⌘T` | Globally translate selected text, or translate the selected Pesty text card while the panel is open; customizable in Settings |
| `⇧⌘D` | Globally explain selected text, or explain the selected Pesty text card while the panel is open; customizable in Settings |
| `T` | Swap source and target languages while the translation board is open and the source language is explicit |
| `←` `→` `↑` `↓` | Move the selection |
| `Space` | Open or close the preview for the selected item |
| `Return` | Paste the selected item |
| `⌘1` through `⌘9` | Quickly paste the item at that position |
| `⌘⌫` | Delete the selected item |
| Start typing | Search clipboard history |
| `Esc` | Clear the search, then close the panel when pressed again |

## Local Development

Requires Xcode 16 or a compatible Swift 6 toolchain.

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

Build a distributable universal app and DMG:

```bash
VERSION=1.2.0 BUILD=1 ./scripts/release_build.sh
./scripts/verify_release.sh 1.2.0
```

The build produces an ad-hoc-signed `packaging/Pesty.app` and
`packaging/Pesty-1.2.0.dmg`, then verifies the signature, bundle ID, version,
and both architectures.

A universal build requires full Xcode. With Command Line Tools only, you can
verify the current Mac architecture:

```bash
ARCHS=arm64 VERSION=1.2.0 BUILD=1 ./scripts/release_build.sh
EXPECTED_ARCHS=arm64 ./scripts/verify_release.sh 1.2.0
```

## Release Process

Stable releases use `vMAJOR.MINOR.PATCH` tags. Beta releases use
`vMAJOR.MINOR.PATCH-beta.N`. The tag must point to a commit reachable from
`main`. GitHub Actions runs tests, builds and verifies the universal DMG,
checks its ad-hoc signature, generates the Homebrew Cask, and publishes Beta
tags as GitHub prereleases.

The Homebrew tap is `bifrost-proxy/homebrew-pesty`. Each release includes the
generated `pesty.rb`; after the tap is updated, users can install that version
with the command above.

## Data Locations

- History and Pinboards: `~/Library/Application Support/Pesty`
- Settings: `~/Library/Preferences/com.bifrostproxy.pesty.plist`

## Documentation

- [English Documentation](docs/en/README.md)
- [User Guide](docs/en/USER_GUIDE.md)
- [Translation Guide](docs/en/TRANSLATION.md)
- [Support and Troubleshooting](docs/en/SUPPORT.md)
- [Privacy](docs/en/PRIVACY.md)
- [Contributing](CONTRIBUTING.md)
- [Changelog](CHANGELOG.md)

Pesty does not maintain a separate marketing site. Project documentation is
stored as Markdown in this repository.

## License

[MIT](LICENSE). This project is derived from `momenbasel/pesty`; the original
author’s copyright and license notices remain in effect.
