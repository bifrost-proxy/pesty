# Pesty Repository Guide

This file applies to the entire repository. It defines the expected development,
testing, local-installation, and release workflow for Codex and other coding
agents.

## Product and Runtime Facts

- Pesty is a native macOS 14+ clipboard-history application written with
  AppKit, SwiftUI, and Observation.
- The package uses a Swift 6 toolchain while compiling in Swift 5 language mode.
- The direct-download app is an `LSUIElement` menu-bar accessory with bundle ID
  `com.bifrostproxy.pesty`.
- The clipboard monitor polls `NSPasteboard.general` every 0.4 seconds.
- History is local by default. When iCloud sync is enabled, the active store is
  `~/Library/Mobile Documents/com~apple~CloudDocs/Pesty/store.json`.
- Settings are stored in
  `~/Library/Preferences/com.bifrostproxy.pesty.plist`.
- Release builds are ad-hoc signed. They are not Developer ID signed or
  notarized.

## Documentation Policy

- Pesty does not maintain or deploy a standalone marketing or documentation
  website.
- Keep user and project documentation as Markdown in `README.md`, `docs/`, and
  the repository's other top-level Markdown files.
- Do not add GitHub Pages deployment, HTML landing pages, SEO/robots/sitemap
  files, `llms.txt`, or site-only social-preview assets unless the user
  explicitly reverses this decision.
- Images used directly by Markdown documentation may remain in `docs/assets`.

## Source-of-Truth Layers

Never collapse these layers into one conclusion:

| Layer | Evidence |
| --- | --- |
| Clipboard capture | Pasteboard read logs and `ClipboardMonitor` behavior |
| In-memory history | `ClipboardStore.history` |
| Persisted history | Decoded `store.json` snapshot |
| Selected/filter state | `source`, `searchText`, and `visibleItems` |
| Rendered UI | `ClipCardView` instances recorded by the automated UI probe |
| iCloud transport | File Provider upload, download, and conflict state |

A growing `store.json` does not prove that the panel renders every card. A
visible card does not prove persistence across restart. A live process does not
prove either.

## Non-Negotiable Development Rules

- Inspect `git status --short --branch` before editing. Preserve unrelated,
  staged, and unstaged user changes.
- Keep clipboard contents private. Tests and diagnostics may report counts,
  types, IDs, and synthetic test strings, but must not print real clipboard
  contents.
- Do not clear history, disable iCloud, delete conflict versions, or overwrite a
  store as a diagnostic shortcut.
- Before replacing `/Applications/Pesty.app`, move the exact existing app into
  a `mktemp -d` backup directory. Keep the backup until the new app has passed
  startup and UI tests.
- Quit Pesty gracefully and wait for the process to exit before replacement.
  Do not run two normal Pesty instances against the same store.
- Treat application restart as an interrupting action. Obtain user
  authorization unless restart is already explicitly included in the request.
- Do not tag, push, publish a GitHub Release, or update the Homebrew tap without
  explicit user authorization.
- Do not silently swallow new persistence errors. Log errors without logging
  clipboard content.

## UI and Persistence Invariants

- Opening the bar must select `.history`, clear search, and select the first
  visible item.
- Search must use a native text field, not manual character appending. Clicking
  it or typing the first printable key must synchronously focus its AppKit field
  editor and pass the same event through to macOS. Preserve marked-text and
  composition events for non-English input methods, let the field edit
  non-empty queries, and grow it with the rendered query width. Do not eagerly
  create the input-method context merely by opening the panel. Pesty may
  intercept navigation, paste, and deletion shortcuts only when the text editor
  is not composing marked text.
- A newly captured item must be present in all three places:
  `history`, `visibleItems`, and the rendered card set.
- Clipboard entries must survive at least two complete application
  quit-and-launch cycles.
- Duplicate content may move to the front, but different content must not
  replace earlier entries.
- Writes to an iCloud-backed store must use file coordination.
- Atomic replacement can emit `.rename` or `.delete`; the file watcher must
  reattach after those events, including ignored self-write events.
- External snapshots must merge by content and timestamp. They must never
  replace the complete in-memory history with a stale or partial snapshot.
- New installations default to a 5,000-item history limit. Settings use a
  discrete slider with 100-item nodes from 100 through 1,000, 1,000-item nodes
  from 2,000 through 10,000, and an unlimited node immediately after 10,000.
  Unlimited mode must also remain unlimited while merging iCloud snapshots.
- Lowering the limit must never trim immediately. Persist a deadline at least
  10 seconds in the future, keep all records during that grace period (including
  across restart and iCloud merge), and cancel or reschedule deletion when the
  user raises the limit or selects unlimited.
- Settings must show the logical byte size of the active Pesty data directory,
  including the JSON store and image files. Calculate it off the main thread
  and refresh it after persistence or active-store changes.
- Every entry point that clears the complete clipboard history must show the
  same destructive confirmation first. Cancellation and window dismissal must
  preserve all records; only the explicit destructive button may call
  `ClipboardStore.clearHistory()`.
- Resolve conflict versions only after all readable versions have been merged
  and the merged snapshot has been saved successfully.
- On macOS 26, the horizontal `LazyHStack` used by the original panel created
  only the leading card even when `history` and `visibleItems` contained many
  entries. Do not reintroduce a lazy horizontal container without passing the
  real UI regression described below.
- The history strip uses a horizontal `NSCollectionView` with reusable
  `NSHostingView` cells. Do not replace it with either an eager `HStack` or a
  SwiftUI `LazyHStack`: the former has unbounded memory growth, while the latter
  lost off-screen cards on macOS 26.
- Keep the explicit card height and the post-animation collection-layout
  invalidation. Rebuilding the complete root `NSHostingView` after every panel
  presentation defeats reuse and is not allowed.
- The clipboard panel uses one native `NSVisualEffectView` behind a lightly
  tinted translucent overlay. Keep panel tint opacity between 0.20 and 0.45.
  Cards must remain substantially more opaque (0.86 through 0.95) so desktop
  content never harms clipboard readability. Do not add one visual-effect view
  per card; that breaks the memory and scrolling budget.

## Required Fast Checks

Run these after every Swift source change:

```bash
swift build
swift run Pesty --verify-localization
swift run Pesty --verify-history-settings
git diff --check
git diff --cached --check
```

For history-retention Settings changes, also run the real 10-second grace and
cancellation regression with isolated data and preferences:

```bash
test_dir="$(mktemp -d)"
suite="com.bifrostproxy.pesty.retention-test.$(date +%s)"
PESTY_AUTOMATED_TEST_DATA_DIR="$test_dir" \
PESTY_AUTOMATED_TEST_DEFAULTS_SUITE="$suite" \
PESTY_AUTOMATED_UI_TEST=retention-delay \
PESTY_AUTOMATED_TEST_ID="retention-$(date +%s)" \
  .build/debug/Pesty
defaults delete "$suite" >/dev/null 2>&1 || true
```

Require `AUTOMATED_RETENTION_DELAY_RESULT` to show 150 items during both
grace-period checks and after cancellation, then exactly 100 after the second
10-second grace period.

Also reuse one isolated data directory and defaults suite across
`retention-restart-seed` and `retention-restart-verify`. Require both
`AUTOMATED_RETENTION_RESTART_RESULT` lines to succeed, with 150 items still
present immediately after restart and 100 only after the persisted deadline.

For changes to complete-history deletion, run `clear-confirmation` with an
isolated test directory. Require `AUTOMATED_CLEAR_CONFIRMATION_RESULT` to show
four records after cancellation and zero only after explicit confirmation.

For search UI, key routing, or text-input changes, run `search-input` with an
isolated test directory. Require `AUTOMATED_SEARCH_INPUT_RESULT` to confirm a
native text editor is focused after direct typing, the first keyboard event is
replayed into the field, marked text becomes active, and a navigation key is
passed through while composition is active. It must also prove that a long
Chinese query receives more width than a short query and fits its measured
rendered width.

For menu-bar visibility, reopen behavior, or Settings changes, also run the
existing settings verification with no production store access:

```bash
test_dir="$(mktemp -d)"
PESTY_AUTOMATED_TEST_DATA_DIR="$test_dir" \
  swift run Pesty --verify-settings-access
```

## Automated Clipboard and UI Regression

`AutomatedUITestRunner` is the authoritative regression entrypoint. It writes
four unique synthetic text clips, opens the panel, and emits one JSON line
prefixed with `AUTOMATED_UI_TEST_RESULT`.

The result is a pass only when all of the following are true:

- `"success": true`
- `"persistedMatches": 4`
- `"visibleMatches": 4`
- `"renderedMatches": 4`
- `"source": "history"`
- `"searchLength": 0`

The seed phase snapshots and restores the original pasteboard. If the process
is interrupted before restoration, restore or warn about the clipboard state.

### Isolated three-launch test

Use a fresh directory and reuse one run ID across all phases:

```bash
test_dir="$(mktemp -d)"
run_id="isolated-$(date +%s)"

PESTY_AUTOMATED_TEST_DATA_DIR="$test_dir" \
PESTY_AUTOMATED_UI_TEST=seed \
PESTY_AUTOMATED_TEST_ID="$run_id" \
  .build/debug/Pesty

PESTY_AUTOMATED_TEST_DATA_DIR="$test_dir" \
PESTY_AUTOMATED_UI_TEST=restart-1 \
PESTY_AUTOMATED_TEST_ID="$run_id" \
  .build/debug/Pesty

PESTY_AUTOMATED_TEST_DATA_DIR="$test_dir" \
PESTY_AUTOMATED_UI_TEST=restart-2 \
PESTY_AUTOMATED_TEST_ID="$run_id" \
  .build/debug/Pesty
```

Afterward, decode the isolated store and verify that all four strings remain in
newest-first order:

```bash
jq --arg prefix "pesty-auto-$run_id-" \
  '{historyCount:(.history|length),
    matches:[.history[] | select(.text | startswith($prefix)) | .text]}' \
  "$test_dir/store.json"
```

Never count only the seed phase as sufficient. Both restart phases are required.

### Horizontal strip performance test

Build the release executable and run the deterministic 1,000-item test:

```bash
swift build -c release
scripts/test_strip_performance.sh .build/release/Pesty
```

The result must report all of the following:

- `historyCount`, `visibleCount`, and the decoded persisted store are exactly
  1,000, in the original order. The test uses the volatile
  `-historyLimit 5000` argument and must not change the user's saved setting.
- The checkpoints at indexes 0, 249, 499, 749, and 999 are progressively
  configured and actually rendered as selection scrolls across the strip.
- At most 40 collection cells are created or simultaneously visible.
- The five-checkpoint traversal completes within 6,000 milliseconds.
- AppKit emits no undefined `NSCollectionViewFlowLayout` size warning.
- Maximum resident set size is at most 100,000,000 bytes. Override
  `PESTY_MAX_RSS_BYTES` only for diagnosis; do not weaken the release gate.

Run this test for every change to the strip, card layout, image loading, search
filtering, or panel presentation lifecycle.

### Keyboard deletion regression

Backspace with an empty search deletes the selected card. Selection must move
to the following card that shifts into the deleted index; deleting the final
card falls back to the preceding card. Backspace continues to edit the query
instead of deleting a card while search is non-empty.

Run the isolated keyboard regression for changes to keyboard handling,
selection, deletion, filtering, or strip navigation:

```bash
test_dir="$(mktemp -d)"
PESTY_AUTOMATED_TEST_DATA_DIR="$test_dir" \
PESTY_AUTOMATED_UI_TEST=keyboard-delete \
PESTY_AUTOMATED_TEST_ID="keyboard-$(date +%s)" \
  .build/debug/Pesty
```

Require `AUTOMATED_KEYBOARD_DELETE_RESULT` to report `"success": true`.

### Real iCloud three-launch test

Run this for changes to clipboard capture, store merging, iCloud sync, panel
state, or card layout.

Do **not** invoke `/Applications/Pesty.app/Contents/MacOS/Pesty` directly for a
real iCloud test. macOS can attribute iCloud access to the terminal process,
causing `iCloudBase` to appear unavailable and silently exercising the local
fallback store instead. Such a result is invalid.

Launch every phase through LaunchServices:

```bash
out_file="$(mktemp)"
err_file="$(mktemp)"
run_id="real-$(date +%s)"

open -n \
  --stdout "$out_file" \
  --stderr "$err_file" \
  --env "PESTY_AUTOMATED_UI_TEST=seed" \
  --env "PESTY_AUTOMATED_TEST_ID=$run_id" \
  /Applications/Pesty.app
```

Wait for the phase's Pesty PID to exit, read `out_file`, and enforce all six
success fields listed above. Then repeat through LaunchServices with phases
`restart-1` and `restart-2`, reusing the same run ID.

The final phase must remove only its own four records:

```bash
open -n \
  --stdout "$out_file" \
  --stderr "$err_file" \
  --env "PESTY_AUTOMATED_UI_TEST=restart-2" \
  --env "PESTY_AUTOMATED_TEST_ID=$run_id" \
  --env "PESTY_AUTOMATED_TEST_CLEANUP=1" \
  /Applications/Pesty.app
```

Record the real history count before seeding and after cleanup. The post-cleanup
count and store size must return to the pre-test state. If any phase fails after
the seed phase, use the same run ID in a cleanup phase; never leave synthetic
records in the user's history.

The automated mode disables the normal key-to-search monitor so user typing
cannot make the test nondeterministic. Normal application launches must retain
key-to-search behavior.

## iCloud Verification

Use File Provider state as transport evidence:

```bash
fileproviderctl evaluate \
  "$HOME/Library/Mobile Documents/com~apple~CloudDocs/Pesty/store.json"
```

Before handoff, require:

- `isUploaded = 1`
- `isUploading = 0`
- stable file size after test cleanup

Report `hasUnresolvedConflicts` separately. A conflict flag is not proof of data
loss, and passing UI tests do not prove that the flag has been cleared. Do not
claim conflict resolution unless File Provider reports it. Do not forcibly
delete conflict versions without a verified merged backup and explicit scope.

## Local Build and Installation

For a current-machine development build:

```bash
ARCHS=arm64 VERSION=MAJOR.MINOR.PATCH BUILD=BUILD_NUMBER \
  ./scripts/build_app.sh

packaging/Pesty.app/Contents/MacOS/Pesty --verify-localization
codesign --verify --deep --strict --verbose=2 packaging/Pesty.app
plutil -extract CFBundleShortVersionString raw -o - \
  packaging/Pesty.app/Contents/Info.plist
lipo -archs packaging/Pesty.app/Contents/MacOS/Pesty
```

Use the host architecture instead of hard-coding `arm64` when running on Intel.

Installation procedure:

1. Gracefully quit the installed Pesty and wait until `pgrep -x Pesty` is empty.
2. Create a backup directory with `mktemp -d`.
3. Move exactly `/Applications/Pesty.app` into that backup.
4. Copy the verified build with `ditto packaging/Pesty.app
   /Applications/Pesty.app`.
5. Verify the installed signature, version, build, and architecture.
6. Run the isolated three-launch test against the installed binary.
7. Run the real iCloud three-launch test when the changed surface requires it.
8. Launch the app normally and confirm a stable PID from
   `/Applications/Pesty.app/Contents/MacOS/Pesty`.
9. Keep the previous app backup until the user confirms the installed build.

If copy or startup fails, restore the exact backup. Never delete the previous
app before the replacement has passed.

## Application Update Requirements

The direct-download build checks the public GitHub Releases Atom feed at launch
and every 3,600 seconds. Do not switch production checks back to the anonymous
REST API: its 60-request shared-IP limit can make manual checks fail. Stable
versions select only stable entries. Versions named `MAJOR.MINOR.PATCH-beta.N`
select only newer entries with the same Beta naming scheme. It also exposes a
manual "Check for Updates" action. Do not weaken these updater invariants:

- A release must be newer by numeric stable or `beta.N` comparison.
- Stable installs must reject all prereleases. Beta installs must reject stable
  releases and non-`beta.N` prereleases. Drafts, wrong-channel releases, missing
  DMGs, and missing SHA-256 digests must be rejected.
- Production downloads must use the exact
  `https://github.com/bifrost-proxy/pesty/releases/download/` path.
- Release notes must retain the workflow-generated `SHA-256: <digest>` line;
  the Atom parser treats entries without that digest as invalid.
- Before replacement, verify the downloaded SHA-256, bundle ID, exact version,
  ad-hoc code signature integrity, and both `arm64` and `x86_64` architectures.
- When the menu bar icon is visible, show the update only in the menu bar icon
  and menu. When the icon is hidden, show it only in the clipboard bar's top
  toolbar. The two update indicators must never appear at the same time.
- Clicking the visible update action starts installation immediately.
- Replacement must wait for the old PID to exit, keep an exact adjacent backup,
  verify the installed copy, relaunch through LaunchServices, and remove the
  backup only after the new process writes its health marker.
- If copy or validation fails, restore and reopen the previous app.
- Never print clipboard data in updater logs.

Run the deterministic updater contract verifier after updater, release, menu
bar, localization, or Settings changes:

```bash
swift run Pesty --verify-updater
```

Before publishing a stable updater change, perform a real GitHub Beta E2E:

1. Publish and install `MAJOR.MINOR.PATCH-beta.N`.
2. Publish `MAJOR.MINOR.PATCH-beta.(N+1)` from the intended source commit.
3. Launch the installed lower Beta normally and require the real GitHub API,
   DMG download, replacement helper, health marker, and restart to reach the
   higher Beta.
4. Launch the latest stable build and prove it reports up-to-date instead of
   seeing either Beta.

For a machine-readable real-feed channel check, launch the packaged app through
LaunchServices with `PESTY_AUTOMATED_UPDATE_CHECK_ONLY=1`, capture the
`AUTOMATED_UPDATE_CHECK_RESULT` JSON line, and assert `channel`, `outcome`, and
`availableVersion` explicitly.

For an earlier local dry run, use a locally hosted GitHub-release fixture
containing a higher-version Universal DMG. Install the lower-version test build
into `/Applications`, launch it through LaunchServices with
`PESTY_UPDATE_FEED_URL`, `PESTY_UPDATE_ALLOW_INSECURE_TEST_FEED=1`, and
`PESTY_AUTOMATED_UPDATE_INSTALL=1`, then require:

1. the higher version replaces the lower version;
2. the new PID is running from `/Applications/Pesty.app`;
3. the updater health marker caused the adjacent backup to be removed;
4. the update log contains no restore or validation failure;
5. the user's original app is restored after the test unless the new version is
   the intended handoff build.

## Release Workflow

Official releases must be universal unless an explicitly scoped local
validation says otherwise:

```bash
VERSION=MAJOR.MINOR.PATCH BUILD=BUILD_NUMBER \
  ./scripts/release_build.sh

./scripts/verify_release.sh MAJOR.MINOR.PATCH
```

The release gate must verify:

- localization
- deterministic updater verification
- Swift debug and release builds
- the isolated and real three-launch UI regression when relevant
- valid DMG and app signatures
- bundle ID `com.bifrostproxy.pesty`
- exact version and build metadata
- both `arm64` and `x86_64` architectures
- generated Homebrew Cask consistency
- clean `git diff --check`
- release tag `vMAJOR.MINOR.PATCH` is reachable from `main`

Read back the generated DMG and Cask rather than trusting command exit status
alone. Publishing and tap updates remain separate, explicitly authorized
actions.

If a tag-triggered workflow fails before creating its GitHub Release, do not
delete or move the published tag. Fix the workflow on `main`, then dispatch the
Release workflow with the exact existing tag. The retry must check out that tag,
verify that its commit is reachable from `main`, and rebuild all assets before
publishing.

## Definition of Done

A clipboard, history, iCloud, or panel change is not complete until:

1. Fast checks pass.
2. Four distinct clips pass persistence, visibility, and rendered-card checks.
3. The same four clips pass after two complete restarts.
4. The packaged and installed binaries pass, not only the debug executable.
5. Real iCloud testing uses LaunchServices, not a terminal-direct binary.
6. Synthetic records are removed and the original pasteboard is restored.
7. The final normal app process is running the expected version and build.
8. iCloud upload is complete and any remaining conflict flag is reported.
9. Unrelated workspace changes and user history remain untouched.

An updater change is additionally incomplete until the hourly interval,
exclusive menu/panel placement, malicious or incomplete release rejection,
verified Universal DMG installation, health-marked restart, and rollback path
have been tested.

For documentation-only changes, use judgment and skip runtime mutation when it
cannot add evidence. For any optimization of the horizontal history strip, the
full macOS 26 UI regression is mandatory.
