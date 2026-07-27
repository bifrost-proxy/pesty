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
- Resolve conflict versions only after all readable versions have been merged
  and the merged snapshot has been saved successfully.
- On macOS 26, the horizontal `LazyHStack` used by the original panel created
  only the leading card even when `history` and `visibleItems` contained many
  entries. Do not reintroduce a lazy horizontal container without passing the
  real UI regression described below.
- The current deterministic `HStack`, explicit card height, and post-animation
  `NSHostingView` rebuild are correctness requirements. Any performance
  optimization must preserve the same rendered-card results on macOS 26.

## Required Fast Checks

Run these after every Swift source change:

```bash
swift build
swift run Pesty --verify-localization
git diff --check
git diff --cached --check
```

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

For documentation-only changes, use judgment and skip runtime mutation when it
cannot add evidence. For any optimization of the horizontal history strip, the
full macOS 26 UI regression is mandatory.
