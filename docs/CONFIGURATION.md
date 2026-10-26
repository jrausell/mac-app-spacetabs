# Configuration and data safety

SpaceTabs stores user data under:

```text
~/Library/Application Support/SpaceTabs/
  layout.json
  preferences.json
  applications.json
```

These files are local data. They are not scripts, shell commands, or app-launch instructions. Do not use a test run or a refactor to overwrite an existing user's files.

## Files and owners

| File | Owner | Contents |
| --- | --- | --- |
| `layout.json` | `PersistenceStore` / `PersistedLayout` | Current template, proportions, display, appearance, app rules, and saved window tabs. |
| `preferences.json` | `UserPreferencesStore` / `UserPreferences` | Shortcuts, optional zone names, profiles, display-profile links, the right-drag preference, and app language. |
| `applications.json` | `ApplicationCatalog` | Extra `.app` paths selected by the user. |

Launch-at-login state comes from `SMAppService`; it is not restored from JSON. Runtime timing samples, active tasks, pending focus revisions, gesture captures, and temporary zoom state are not written to these files.

## Storage boundary

`LocalConfigurationFile` accepts regular files owned by the current user. Reads reject symbolic links, shared write access, and files larger than 2 MiB. Writes use a private temporary file, `fsync`, and atomic rename within the destination directory.

Preferences have a tighter 512 KiB limit. Model validation also bounds item counts, names, paths, identifiers, geometry, colors, and finite numeric values.

Invalid session configuration blocks new management until it is reset through Settings. Invalid preferences block preference writes until repair. Repair preserves a backup; it does not silently discard the original file.

This is a defensive local-data boundary, not a claim that every process running as the same user is isolated from the app.

## Compatibility rules

`PersistedLayout.version` is currently 1. Older data supplies defaults for fields added later. Template values such as `twoColumns`, `splitLeft`, and `splitRight` are stored values, not UI labels. Do not translate or rename them during UI work.

Saved tabs have stable UUIDs and window identities. Matching requires a unique window/document match. A fallback based on process identity is limited to the same running process and launch date. Do not guess between duplicate titles.

Profiles store layout preferences, window identities, selections, and app rules. They exclude release/recovery frames and old process identities. Applying one does not launch closed apps. Unlisted managed windows keep their zone; C folds into A when switching to two columns.

Display-profile links use public display UUIDs, dimensions, and arrangement. They are not native Space IDs. Only one display is selected for zone placement at a time.

## Shared limits

`PreferenceLimits` is shared by validation and Settings controls. It defines name lengths, profile count, display links, and valid shortcut action IDs. If an action is added, update the schema bound and tests together.

Shortcut IDs are persistent numeric values. New defaults must not replace an existing custom shortcut: migration leaves the conflicting new action unbound. Decoder defaults keep older bindings enabled unless explicitly disabled.

## Language preference

`UserPreferences.language` stores `automatic`, `en`, or `es`. Older files default to `automatic`; an unsupported stored value is rejected without overwriting the file. This choice is separate from profiles. Changing it does not rename profiles, window identities, or saved enum values. See [Localization](LOCALIZATION.md).

## Stable app identities

`SpaceTabsIdentity` defines the main and Settings bundle IDs and the helper name/path. Resources contain matching plist metadata, checked by a contract test. The packaging script reads signing identifiers and the helper name from those plists.

Changing a display name is different from changing a bundle ID. Keep bundle IDs and signing identity stable to preserve macOS authorization behavior. See [Signing](../SIGNING.md).

## Changing the schema

1. Add an optional field or a decoder default for existing files.
2. Define validation before using the new value in window management.
3. Add a migration test with an older payload and a round-trip test with the new payload.
4. Keep invalid data intact and surface a useful error.
5. Update Settings commands/state if the helper needs the value.
6. Update this guide and the relevant limits.

Avoid committing real user data as fixtures. Tests should use temporary directories and synthetic app/document identities. A small explicit Unicode fixture verifies that non-English user data still round-trips across app languages.
