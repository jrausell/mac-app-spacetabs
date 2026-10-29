# Signing and Accessibility identity

macOS checks the running app's code identity for Accessibility access. Keeping only the app name and bundle ID is not enough when every build has a different ad hoc signature.

SpaceTabs uses stable bundle IDs:

- Main app: `dev.spacetabs.mac`
- Settings helper: `dev.spacetabs.mac.settings`

The helper has a separate Dock identity. It does not request Accessibility access or register itself at login; the main app owns those operations.

## Configure your own development identity

List identities in your normal Terminal:

```sh
security find-identity -v -p codesigning
```

Choose the 40-character SHA-1 fingerprint for your signing certificate:

```sh
Scripts/configure-signing.sh YOUR_40_CHARACTER_SHA1_FINGERPRINT
Scripts/build-app.sh release
```

The first command validates the fingerprint and stores it in `.local/signing-identity`, which is ignored. The private key stays in your keychain. Existing local configuration may use a certificate's exact name; fingerprints are preferred when configuring a new machine.

You may also pass an identity for one build:

```sh
SPACETABS_SIGN_IDENTITY='Your Code Signing Identity' Scripts/build-app.sh release
```

To require a stable identity rather than allow the unconfigured ad hoc default:

```sh
SPACETABS_REQUIRE_STABLE_SIGNING=1 Scripts/build-app.sh release
```

These commands do not create a certificate or change keychain access controls. Use your own identity; no maintainer certificate is distributed with the source.

## Build behavior

The script compiles, creates a staging app, generates icons, signs the helper, signs the main app, and verifies both before replacing `dist`. It preserves the previous app if signing fails. It does not silently choose another identity.

Quit both SpaceTabs and SpaceTabs Settings before opening an updated package. Authorize the packaged main app in System Settings → Privacy & Security → Accessibility. Keep using the same intended bundle and certificate across rebuilds.

Inspect an app's identity with:

```sh
codesign -d -r- dist/SpaceTabs.app
codesign -dv --verbose=4 dist/SpaceTabs.app
codesign --verify --deep --strict dist/SpaceTabs.app
```

A stable identity is intended to reduce repeated authorization. Permission persistence must still be tested across actual builds on macOS; the app cannot grant itself access.

## Restricted development environments

A coding agent may be able to compile but unable to use the private key in the user keychain. In that case, use `Scripts/build.sh release` for compilation and run signed packaging from your Terminal. Do not claim the package was updated when signing failed.

Automated tests request an ad hoc linker signature for their own transport identity checks. That is separate from the certificate used for your packaged app.

## Public distribution

Development signing is not a complete public-release process. The source code license is [GNU GPLv3](LICENSE). A public release still needs confirmed asset permissions, a distribution signing/notarization plan, and actual desktop validation. None of these steps is performed automatically by CI.

Background: [Apple TN3127, code-signing requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).
