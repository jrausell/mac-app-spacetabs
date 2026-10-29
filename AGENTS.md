# Working on SpaceTabs

Read this file before editing. It applies to human contributors and coding agents throughout the repository. Use plain English in code comments, docs, scripts, and source translation keys. Localized app text belongs in language catalogs.

## Start here

1. Read `README.md` for current features and limits.
2. Read `docs/ARCHITECTURE.md` for ownership, concurrency, and behavior contracts.
3. Read `docs/TESTING.md` before changing focus, gestures, placement, persistence, or settings IPC.
4. For configuration changes, also read `docs/CONFIGURATION.md`.
5. For app text or language changes, read `docs/LOCALIZATION.md`.

Use the current source and tests as evidence. The old root-level planning documents now point to current guides; do not treat old version notes as requirements.

## Source map

- `Sources/SpaceTabs/Application`: entry point and AppKit lifecycle.
- `Sources/SpaceTabs/Model`: main-actor state and focused `AppModel` extensions.
- `Sources/SpaceTabs/WindowManagement`: public AX adapter, per-process actors, and GCD executors.
- `Sources/SpaceTabs/Input`: global shortcuts and drag controllers.
- `Sources/SpaceTabs/Settings`: separate Settings process and authenticated local transport.
- `Sources/SpaceTabs/Interface`: SwiftUI pages and desktop controls.
- `Sources/SpaceTabsCore`: geometry, window operations, policies, validation, and data models.
- `Tests`: Swift Testing suites for both modules.
- `Scripts`: local build, formatting, tests, and checks.

## Behavior that must remain true

- Use public macOS APIs only. Do not disable SIP, inject code, or embed external windows.
- Tabs use real windows. Switching a tab must not minimize other tabs or enforce focus continuously.
- A tab selection preserves the other zones' selections. Restoring all zones ends with focus in B.
- Zoom resolves the actual focused managed window. Never fall back to A when focus is unknown.
- Settings assignments must not steal focus from Settings.
- AX handles stay within their per-process session. Synchronous AX calls use `AXQueueExecutor`, not the main actor or Swift's cooperative executor.
- Keep discovery event-driven, bounded, and separate from interactive work. Do not add periodic full scans.
- Gesture callbacks do not query AX or render UI. No window writes happen during a drag preview.
- Releasing a gesture modifier before mouse-up cancels assignment. A valid mouse-up may wait for its own capture, but not reuse a cancelled or newer gesture.
- Failed recovery must keep original window states available for release.
- Manual pauses must not be cleared by desktop notifications or automatic profiles.
- The manager and Settings helper do not manage their own windows.

## Data and identity

Route app-owned text through `L10n`, keep English keys and Spanish translations complete, and never translate external window titles or user names. New SwiftUI views must observe `AppLocalization.shared.language` so they update without resetting local state.

Keep bundle IDs and configuration keys stable. Shared runtime identities are in `SpaceTabsIdentity`; plist contract tests check them. English display names may change without renaming persisted enum values.

Use the existing validated, bounded storage helpers. Configuration is data, not shell commands or executable scripts. Keep `.local`, `.build`, `dist`, certificates, and user configuration out of public commits. Do not reset TCC permissions or change a user's signing identity as a cleanup step.

A settings feature usually needs both a typed command and a snapshot field. Commands run in the manager; the helper is not another window manager. See `docs/ARCHITECTURE.md` for the full path.

## Upstream contributions

Read `CONTRIBUTING.md` before proposing an upstream change. External pull requests require explicit maintainer agreement on scope before implementation. Do not generate speculative PRs, credit-seeking changes, or batches of cosmetic fixes. A direct task from the maintainer in the current session is authorization to do that work; it does not authorize publishing or opening a PR.

## Checks

From the repository root:

```sh
Scripts/format.sh
Scripts/lint.sh
Scripts/check-docs.py
Scripts/check-localizations.py
Scripts/test.sh
Scripts/build.sh release
```

Add tests for meaningful policy or failure behavior. Do not write tests that only repeat a view modifier or copy the implementation.

`SPACETABS_TEST_LOCAL_LISTENER=1 Scripts/test.sh` also checks a bound Unix listener. Restricted environments may deny binding; the default suite still tests framing and peer validation with socket pairs.

## Reporting work

State what changed, why, and what was verified. Separate compilation, automated tests, signing, and desktop interaction. A passing test suite does not prove that real AX events, focus, or gestures work on the user's desktop.

App packaging is `Scripts/build-app.sh release`. If signing fails, say that `dist` still contains the previous app. Do not silently switch to ad hoc signing or claim an app was updated.

SpaceTabs source code is licensed under GNU GPL version 3; see `LICENSE`. Keep licensing statements consistent with that choice. Do not invent a repository URL, release status, or security contact. Use `docs/ROADMAP.md` for the remaining publication decisions.
