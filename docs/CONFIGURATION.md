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

## Diagnostic history

Runtime problem history is separate from configuration, in `~/Library/Logs/SpaceTabs/`. The manager and Settings each keep a private current JSON-lines file and one previous generation, capped at 1 MiB each (4 MiB total). Writes use a bounded background queue, reject links and unsafe files, and drop excess queued records rather than block the UI. Dropped counts appear in subsequent records. Logs are local, are never executed, and are not uploaded automatically. See [Troubleshooting](TROUBLESHOOTING.md) for sharing and diagnostic limits.

## Storage boundary

`LocalConfigurationFile` accepts regular files owned by the current user. Reads reject symbolic links, shared write access, and files larger than 2 MiB. Writes use a private temporary file, `fsync`, and atomic rename within the destination directory.

Preferences have a tighter 512 KiB limit. Model validation also bounds item counts, names, paths, identifiers, geometry, colors, and finite numeric values.

Invalid session configuration blocks new management until it is reset through Settings. Invalid preferences block preference writes until repair. Repair preserves a backup; it does not silently discard the original file.

This is a defensive local-data boundary, not a claim that every process running as the same user is isolated from the app.

## Compatibility rules

`PersistedLayout.version` is currently 1. Older data supplies defaults for fields added later. Template values such as `twoColumns`, `splitLeft`, and `splitRight` are stored values, not UI labels. Do not translate or rename them during UI work.

Saved tabs have stable UUIDs and window identities. Sessions also save an optional public macOS window number. It takes priority over page titles and document URLs only when the app PID and launch date still match. This lets a browser window survive changing or closing its active page while several browser windows are open. If that numbered window has closed, a different window showing the old page is not substituted.

Discovery retains unavailable managed windows as pending saved tabs before dropping their live snapshots. Closing an external window or quitting its app therefore does not erase its saved assignment at the next checkpoint. Pending tabs retain their place among live tabs; matching windows return to that order on recovery. A live selection takes priority over a pending selection in the same zone. Explicit window release still removes live membership, and Forget Pending Windows explicitly clears pending records. Saving or replacing a named profile now includes pending windows, stripped of process-local identities and release frames. Named profiles still require explicit saves; this is the retention foundation for the [workspace profiles plan](WORKSPACE_PROFILES_PLAN.md), not automatic profile saving or app/window recreation.

Unavailable assignments appear as at most one Pending app placeholder per zone, labeled with the app name rather than a saved web page or document title. A managed live window of that app in the same zone suppresses the placeholder. Saved window records remain intact for recovery and diagnostics; grouping changes presentation only. Clicking a placeholder first requests scoped discovery for that running app and waits for the existing discovery pipeline. One compatible unassigned native window visible on the current desktop is synchronized directly; several candidates produce an anchored window chooser. The chooser is revalidated against current public Window Server visibility and ownership before assigning. This explicit app-level action may replace the clicked legacy window identity even when its title/document changed; other pending records and zones are retained. It uses the chosen live window’s own release state. Assigned windows, other desktops, and unnumbered or ambiguous physical identities are excluded. Runtime app names and bundle URLs supplement the installation catalog, and explicit saved-app discovery includes accessory apps. If the app has no discovered compatible windows, the action resolves its app URL from running-app metadata, the unique catalog entry, or Launch Services, then requests normal app reopening. Existing bundle validation still applies before launch. This requests normal app reopening, not arbitrary document/session reconstruction. Before opening, a bounded public Window Server metadata snapshot records existing window numbers across desktops on the existing GCD executor. For up to 15 seconds, event-driven recovery may bind one compatible, unassigned window with a new public number and matching bundle ID; a saved document must still match exactly. Existing, unnumbered, or ambiguous windows are not adopted. Failure keeps the assignment pending and reports a manual recovery step. There is no discovery polling or automatic app opening at startup.

This explicit reopen path is separate from `WindowReconciler`: normal automatic recovery still refuses to substitute another window for a closed known window in the same running process. Switching desktop/profile, disconnecting displays, pausing, forgetting the assignment, or terminating cancels pending reopen requests. A replacement window uses its own release state. Request tokens prevent a late cancelled task from clearing a newer request. Reopen requests, metadata baselines, and task state are not persisted. Settings uses typed `reopenPendingTab`, `synchronizePendingWindow`, `dismissPendingWindowChoice`, and `forgetPendingTab` commands and mirrors tab order, reopen status, candidate IDs, and per-tab failure messages in its snapshot. Window choices and failures appear next to the pending tab instead of failing silently; dismissal preserves the saved assignment. These choices/messages are transient and are cleared on desktop/profile changes or cancellation. The grouped placeholder’s Forget Saved Windows for This App in This Zone action removes only that app’s pending records in the chosen zone after a successful checkpoint. Other zones, apps, and live windows remain unchanged. The individual forgetPendingTab command remains available for specific-record operations.

Discovery associates Accessibility windows with window numbers only when their process and bounds give a unique match. Overlapping indistinguishable windows remain unresolved. Older sessions without numbers still require a unique document/title match, or exactly one saved and live window in the same running process. Reassign an unmatched legacy browser window once to record its number. After the browser itself restarts, document/title matching is still required; process-local window numbers cannot identify new windows safely.

`TabAppearance.backgroundOpacity` stores a finite value from 0 to 1 and defaults to 0.9 for older layouts and profiles. Settings → Design → Colors and Appearance exposes it as a percentage. It affects the tab bar background; text, controls, and zone borders retain their opacity. The existing appearance command and snapshot carry the value between Settings and the manager.

`TabAppearance.keepFixedBarsBehindWindows` defaults to true and is saved with layouts and profiles. Configurations without this field use the background default; existing explicit choices are preserved. Under Design → Colors and Appearance → Tab Bar Visibility, **Keep fixed tab bars above all windows** inverts this stored preference: leave it unchecked to place fixed bars and resize handles below normal app windows. Show Tabs temporarily raises them for five seconds; hovering, tab dragging, and context menus hold the reveal, and clicking outside lowers them immediately. Expiry lowers fixed bars without hiding them or changing window geometry. Routine assignments and layout updates do not raise background bars. Checking the option restores floating fixed bars. Auto-hidden bars retain their existing behavior.

`TabAppearance.revealAllBarsOnClick` defaults to true, including when decoding older layouts and profiles. **Show all tab bars when clicking a tab or group** controls this under Tab Bar Visibility. A left click anywhere in a bar uses the same temporary reveal as Show Tabs. The option also covers native app-tab buttons without replacing their click or drag handling. Turning it off leaves the Show Tabs command available. Clicks on external windows or resize handles do not trigger this reveal.

Profiles store layout preferences, window identities, selections, and app rules. They exclude release/recovery frames and old process identities. The standalone legacy resolver keeps unlisted managed windows; workspace profile opening instead starts with that profile’s own saved assignments. C folds into A when switching to two columns.

`WorkspaceProfile.openAssignedApps` defaults to false for new and older profiles. Its checkbox in Settings → Profiles controls opening closed assigned apps on a manual Apply, menu selection, or quick-switcher profile selection. Automatic startup/display links never launch apps. The typed `profileOpenApps` command updates the preference in the manager; `SettingsState.preferences` mirrors it to Settings. Replacing a saved profile preserves its launch choice.

Launches begin only after the profile's layout and persistence transaction succeeds. The queue skips running app paths, validates each saved `.app` against its bundle ID and package type, and opens one app at a time without requesting activation. New windows use existing event-driven assignments and bounded startup discovery. A newer profile application, desktop suspension, or shutdown stops queued launches; an OS launch already requested may still finish. Window snapshots alone do not create app launch rules, and browser pages/documents are not recreated.

Display-profile links use public display UUIDs, dimensions, and arrangement. They are not native Space IDs. Each workspace instance selects one display; separate instances can run concurrently. Legacy display-profile links no longer replace the global layout in workspace mode.

Renaming a profile updates only its name through the typed `renameProfile` command; it keeps the UUID, saved layout, app-launch choice, and display links. Renaming a workspace uses `renameWorkspace` and atomically changes only its registry name before publishing it to models and summaries. The two names are independent: neither rename operation renames the other object. Both trim surrounding whitespace, reject empty names and names over `PreferenceLimits.profileNameCharacters` (60), and keep the previous published name on storage failure. Existing Settings snapshot fields carry the resulting names; no schema migration is needed.

## Shared limits

`PreferenceLimits` is shared by validation and Settings controls. It defines name lengths, profile count, display links, and valid shortcut action IDs. If an action is added, update the schema bound and tests together.

Shortcut IDs are persistent numeric values. New defaults must not replace an existing custom shortcut: migration leaves the conflicting new action unbound. Decoder defaults keep older bindings enabled unless explicitly disabled.

Show Tabs defaults to a Control + Option + Command modifier tap. `ShortcutBinding.key = 127` represents **Modifiers only**; ordinary key codes remain 0–126. Modifier-only bindings require at least two modifiers, including Control, Option, or Command. Existing explicit bindings (including the previous Control + Option + T) and disabled bindings remain unchanged. A clean tap fires after all modifiers are released; regular keys, mouse buttons, scrolling, Fn, or extra modifiers cancel it. These bindings use passive event monitors rather than exclusive Carbon registration, so conflicts with other apps cannot be detected.

## Language preference

`UserPreferences.language` stores `automatic`, `en`, or `es`. Older files default to `automatic`; an unsupported stored value is rejected without overwriting the file. This choice is separate from profiles. Changing it does not rename profiles, window identities, or saved enum values. See [Localization](LOCALIZATION.md).

## Stable app identities

`SpaceTabsIdentity` defines the main and Settings bundle IDs and the helper name/path. Resources contain matching plist metadata, checked by a contract test. The packaging script reads signing identifiers and the helper name from those plists.

The Settings helper has `LSUIElement=true` and accessory activation policy, so only the manager appears in the Dock and Command-Tab. This changes presentation without renaming either bundle ID. The authenticated `presentIfOpen` packet follows a completed workspace activation and does not launch Settings or reopen a closed window.

Changing a display name is different from changing a bundle ID. Keep bundle IDs and signing identity stable to preserve macOS authorization behavior. See [Signing](../SIGNING.md).

## Changing the schema

1. Add an optional field or a decoder default for existing files.
2. Define validation before using the new value in window management.
3. Add a migration test with an older payload and a round-trip test with the new payload.
4. Keep invalid data intact and surface a useful error.
5. Update Settings commands/state if the helper needs the value.
6. Update this guide and the relevant limits.

Avoid committing real user data as fixtures. Tests should use temporary directories and synthetic app/document identities. A small explicit Unicode fixture verifies that non-English user data still round-trips across app languages.


## Independent workspace registry

`~/Library/Application Support/SpaceTabs/workspaces.json` is the version-1 authoritative session document for workspace instances. Each record contains a UUID, name, optional named-profile UUID, physical display UUID, `PersistedLayout`, and zone names. Records are bounded to 16; IDs and non-null profile associations must be unique. Every embedded layout and metadata field is validated before load/save. The shared private atomic helper enforces ownership, symlink rejection, and the total 2 MiB limit. A failed or unsupported registry does not fall back to overwriting the legacy layout.

First migration copies `layout.json` into one Main workspace and preserves the legacy file and preferences. Later restarts load each workspace's slots independently but leave native desktop association unconfirmed until explicit Open here. Native desktop IDs and anchor window numbers are not persisted. Each workspace checkpoint updates only its own record; global preferences propagate between models while preserving per-workspace zone names. Display-setup links stay on disk but do not automatically replace workspace instances.


## Ephemeral desktop menu snapshot

`~/Library/Application Support/SpaceTabs/Finder/menu.json` contains only a bounded menu snapshot and per-run URL capability/context for the Finder extension. It is generated runtime data, not editable configuration, and contains no commands or document titles. It is private, atomically replaced, limited to 64 KiB, and marked unavailable when the manager quits. Do not share it in bug reports. The extension's read-only sandbox exception covers only this dedicated directory. [Desktop menu](DESKTOP_MENU.md) describes URL validation and activation.
