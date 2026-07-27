# Changelog

All notable changes to Pesty are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/), and this project adheres to
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.5.1] - 2026-07-27

### Changed

- Virtualized the horizontal clipboard strip with reusable native collection
  cells so 1,000-item histories stay below the 100 MB memory gate.
- Downsampled image previews asynchronously with a bounded thumbnail cache.

### Fixed

- Made Backspace delete the selected clipboard item when search is empty and
  move selection to the following item, with previous-item fallback at the end.
- Kept Backspace editing the search query while a query is active.
- Removed the post-animation root view rebuild and fixed the panel's initial
  height so AppKit does not enter an undefined collection layout.

[1.5.1]: https://github.com/bifrost-proxy/pesty/releases/tag/v1.5.1

## [1.5.0] - 2026-07-27

### Added

- Added automatic light and dark appearances that follow the macOS system
  setting, with deterministic appearance and contrast verification in CI.

### Changed

- Moved the user guide, support information, and privacy notice into Markdown
  files maintained directly in the repository.

### Removed

- Removed the standalone static website, SEO files, and site-only image assets.

[1.5.0]: https://github.com/bifrost-proxy/pesty/releases/tag/v1.5.0

## [1.4.0] - 2026-07-27

### Added

- Added a manual update check and an automatic check at launch and every hour.
- Added isolated Stable and Beta channels so stable installs ignore
  prereleases and Beta installs only advance to newer `beta.N` releases.
- Added mutually exclusive update indicators in the menu bar or clipboard bar,
  with one-click download, verified installation, and application restart.
- Added SHA-256, release URL, bundle identity, Universal architecture, and code
  signature verification before an update can replace the installed app.
- Uses the GitHub Releases Atom feed for production checks so manual and hourly
  checks do not depend on the anonymous REST API's shared rate limit.

[1.4.0]: https://github.com/bifrost-proxy/pesty/releases/tag/v1.4.0

## [1.3.2] - 2026-07-27

### Added

- Added an automated clipboard UI regression that verifies persistence,
  filtering, and rendered cards across two complete application restarts.
- Added repository-wide development, testing, installation, and release
  guidance for future contributors and coding agents.

### Fixed

- Fixed the history strip showing only the newest card on macOS 26 even though
  all clipboard entries existed in memory and on disk.
- Coordinated iCloud history writes, merged readable conflict versions, and
  reattached the file watcher after atomic replacements.
- Reconciled the active store and rebuilt the SwiftUI hosting tree when opening
  the panel so persisted history is reflected in the visible UI.

[1.3.2]: https://github.com/bifrost-proxy/pesty/releases/tag/v1.3.2

## [1.3.1] - 2026-07-27

### Fixed

- Kept launch-at-login silent when the menu bar icon is hidden, while
  preserving Settings recovery for a manual launch from Applications.

[1.3.1]: https://github.com/bifrost-proxy/pesty/releases/tag/v1.3.1

## [1.3.0] - 2026-07-27

### Added

- A setting to hide or restore the Pesty menu bar icon.
- A recovery path that opens Settings when a hidden Pesty is launched or
  reopened from Applications.
- Automated verification for menu bar visibility and Settings recovery.

[1.3.0]: https://github.com/bifrost-proxy/pesty/releases/tag/v1.3.0

## [1.2.0] - 2026-07-27

### Added

- English and Simplified Chinese user interfaces with live language switching.
- A certificate-free release pipeline that builds and verifies an ad-hoc signed
  universal DMG.
- A generated Homebrew Cask for the `bifrost-proxy/pesty` tap.
- Automated localization, release-package, architecture, signature, and Cask
  validation in CI.

### Changed

- Moved repository, support, release, and documentation links to
  `bifrost-proxy/pesty`.
- Changed the application bundle identifier to `com.bifrostproxy.pesty`.
- Rewrote the README in Chinese and removed unrelated marketing content.

[1.2.0]: https://github.com/bifrost-proxy/pesty/releases/tag/v1.2.0

## [1.1.0] - 2026-06-26

Visual overhaul to match Paste, plus iCloud sync.

### Added
- iCloud Drive sync (opt-in) for history and pinboards across your Macs.
- Live Accessibility permission status in Settings, with a Restart button.

### Changed
- Redesigned cards: per-source-app colored header band, app-icon tile, type
  label, verbose relative time, and a footer with character count + quick-paste
  number — a faithful match to Paste.
- Spring animations for selection, hover, and scrolling; taller default strip.
- Top bar now has a sync toggle, search indicator, a "Clipboard" tab, and a
  "…" overflow menu.

### Fixed
- Search input and keyboard navigation reliability.
- Removed the unnecessary Apple Events entitlement.

[1.1.0]: https://github.com/bifrost-proxy/pesty/releases/tag/v1.1.0

## [1.0.0] - 2026-06-26

Initial public release.

### Added
- Slide-up clipboard strip with a global hotkey (default `⌘⇧V`).
- Color-coded cards for text, rich text, links, images, files, and colors, each
  showing source app, editable title, copy time, preview, and character count.
- Pinboards: named, color-tagged collections of saved clips.
- Instant search across the full history.
- Keyboard navigation: arrows to move, `return` to paste, `⌘1`–`⌘9` quick-paste,
  `⌘⌫` to delete, `esc` to close.
- Direct paste into the previously active app via synthesized `⌘V`.
- Privacy: ignores concealed (password-manager) clips.
- Menu-bar item, preferences window, configurable hotkey, launch at login.
- Universal binary (Apple Silicon + Intel), signed with Developer ID and
  notarized by Apple.

[1.0.0]: https://github.com/bifrost-proxy/pesty/releases/tag/v1.0.0
