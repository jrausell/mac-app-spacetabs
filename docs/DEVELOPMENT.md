# Development

## Toolchain

The reference environment is macOS 15, Xcode 26.3, Swift 6.2.4, and Apple's `swift-format` 6.2.3. `Package.swift` requires Swift tools 6.0 and targets macOS 15. A newer compatible toolchain may compile the code, but formatting can differ between formatter versions.

Check your selected tools:

```sh
xcodebuild -version
swift --version
xcrun swift-format --version
```

Open `Package.swift` in Xcode or use the scripts below. Source folders are included recursively by Swift Package Manager; moving a file within a target does not require an Xcode project update.

## Commands

| Command | Purpose |
| --- | --- |
| `Scripts/build.sh` | Compile debug code without app packaging. |
| `Scripts/build.sh release` | Compile optimized code without a personal certificate. |
| `Scripts/build-app.sh release` | Build, package, generate icons, sign, and replace `dist/SpaceTabs.app` after successful verification. |
| `Scripts/test.sh` | Run the default Swift Testing suites. |
| `Scripts/format.sh` | Format maintained Swift code using `.swift-format`. |
| `Scripts/lint.sh` | Check formatting without editing files. |
| `Scripts/check-docs.py` | Check local Markdown links without network access. |
| `Scripts/check-localizations.py` | Check language coverage, duplicate keys, and interpolation placeholders. |
| `Scripts/verify.sh` | Run local checks, package the app, and inspect the signed bundle. |

The build and test scripts place compiler caches under `.build`. They do not install dependencies or change global developer settings.

## Packaging and signing

The package has one executable and two app bundles. The Settings helper is signed before the enclosing app. The helper's display name comes from `Resources/Settings-Info.plist`; runtime identities are checked against plist metadata by a test.

Use [Signing](../SIGNING.md) to configure a stable identity. `.local/signing-identity` is ignored and belongs only to your machine. If signing fails, the staging package remains under `.build` and the previous `dist` app is preserved. A compilation success is not a packaging success.

After an update, quit both SpaceTabs and SpaceTabs Settings before opening the new bundle.

## Formatting and code style

Use four spaces and a target line length of 120 characters. The formatter configuration defines exact layout. Prefer small functions with clear ownership and named limits over unrelated helper layers or repeated numeric constants.

Keep Swift comments in plain English. Explain a constraint or reason, especially around AX, cancellation, persistence, and nonactivating panels. Avoid comments that merely restate the next line.

English is the source and fallback language; app-owned text goes through `L10n` with English and Spanish catalog entries. See [Localization](LOCALIZATION.md) for adding text or languages. Keep non-English user data intact. Changing displayed text must not rename persisted enum values or action IDs.

## Adding files and features

Put a new value policy in the matching `SpaceTabsCore` folder. Native APIs and views belong in `SpaceTabs`. Add related behavior to the focused `AppModel` extension, or create one if it has a distinct responsibility. Do not put window writes in views.

For settings, update command, state, validation, persistence, and helper UI together. For window actions, use the existing backend protocols and transaction/recovery logic.

See [Architecture](ARCHITECTURE.md) for the full ownership model and [AGENTS.md](../AGENTS.md) for repository instructions used by coding agents.

## CI

The GitHub Actions workflow uses `macos-15` with Xcode 26.3. It checks formatting, documentation links, localization catalogs, tests including the local listener, and release compilation. It does not require a signing certificate, grant Accessibility access, register a login item, or operate external windows.

The workflow is prepared for a future public repository; it has not been run on GitHub from this local workspace. Review runner availability when updating Xcode. The referenced runner software is documented by [GitHub](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md).

## Local-only files

`.build`, `.swiftpm`, `dist`, `.local`, and `.DS_Store` are ignored. User sessions are stored outside the repository under Application Support. Do not copy them into example files or bug reports without removing personal data.
