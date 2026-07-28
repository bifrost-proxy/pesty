# Changelog

All notable changes to Pesty are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/), and this project adheres to
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.6.6] - 2026-07-28

### Added

- Added double-click quick paste that restores the previously focused input,
  pastes automatically, and promotes the clip after the panel is hidden.
- Added vertical mouse-wheel support for the horizontal clipboard strip.

### Changed

- Shortened and widened the clipboard cards, placed the panel over the Dock,
  and made panel presentation and dismissal faster.
- Expanded link cards to show the complete copied URL.

### Fixed

- Prevented card clicks from being mistaken for outside clicks that dismiss
  the panel.
- Kept modal rename and new-Pinboard text fields independent from clipboard
  search keyboard handling.
- Migrated the legacy 430-pixel panel height to the current 350-pixel default.

[1.6.6]: https://github.com/bifrost-proxy/pesty/releases/tag/v1.6.6

## [1.6.5] - 2026-07-28

### Added

- Added a click-through blue guide over Accessibility Settings that highlights
  the Pesty permission row and tells the user to turn on its switch.
- Added a safe whole-list fallback for System Settings window layouts that do
  not match the verified Pesty-row geometry.

### Changed

- Kept the Accessibility guide aligned while System Settings moves, and hid it
  after authorization, when leaving System Settings, or after three minutes.

[1.6.5]: https://github.com/bifrost-proxy/pesty/releases/tag/v1.6.5

## [1.6.4] - 2026-07-28

### Added

- Added guided Accessibility onboarding for first installs and app
  replacements, with authorization polling and a restart action after access
  is granted.

### Changed

- Redesigned Settings with persistent General/About navigation, a taller
  780-pixel default height, and vertical resizing while keeping its width
  fixed.

### Fixed

- Waited for the old Pesty process to exit before restarting after
  Accessibility authorization.

[1.6.4]: https://github.com/bifrost-proxy/pesty/releases/tag/v1.6.4

## [1.6.3] - 2026-07-28

### Added

- Added a one-click Accessibility permission repair action that clears Pesty's
  stale authorization record, requests access again, and opens the correct
  System Settings pane.

### Changed

- Synced the history retention limit through the iCloud-backed store so all
  Macs converge on the same finite or unlimited policy.
- Delayed destructive trimming after a remotely received lower limit, giving
  other devices time to receive and reconcile the shared configuration.

### Fixed

- Preserved complete histories while migrating legacy iCloud snapshots and
  deterministically resolved concurrent retention-setting updates.

[1.6.3]: https://github.com/bifrost-proxy/pesty/releases/tag/v1.6.3

## [1.6.2] - 2026-07-27

### Changed

- Made the clipboard panel substantially more transparent and switched to the
  stronger native macOS sidebar material so background blur and vibrancy are
  immediately visible.
- Changed the default clipboard panel height for new installations to 350
  pixels without overriding an existing saved height.

### Fixed

- Restored Command-Backspace as the only keyboard shortcut that deletes a
  selected clipboard item, preventing plain Backspace or Forward Delete from
  removing history when the search query is empty.

[1.6.2]: https://github.com/bifrost-proxy/pesty/releases/tag/v1.6.2

## [1.6.1] - 2026-07-27

### Changed

- Increased the clipboard panel's native frosted-glass transparency while
  preserving the stronger card opacity needed for readable clipboard content.

[1.6.1]: https://github.com/bifrost-proxy/pesty/releases/tag/v1.6.1

## [1.6.0] - 2026-07-27

### Added

- Added a history-retention slider with a 5,000-item default, discrete limits
  through 10,000 items, and an unlimited option.
- Added live clipboard storage usage to Settings.
- Added a native, width-adaptive search field with complete Chinese and other
  input-method composition support.

### Changed

- Refreshed the clipboard panel with a native macOS frosted-glass background
  while keeping cards more opaque and readable.
- Delays history trimming for 10 seconds after lowering the limit so the change
  can be cancelled by raising the limit or returning to unlimited.

### Fixed

- Added a destructive-action confirmation before clearing all clipboard
  history from Settings, the menu bar, or the clipboard panel.

[1.6.0]: https://github.com/bifrost-proxy/pesty/releases/tag/v1.6.0

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
