# Changelog

Version numbers below describe local source milestones. They do not imply published or signed public releases.

## 0.9.0 — Unreleased

- Add automatic language detection, English fallback, and a language selector in General.
- Include complete English and Spanish translation catalogs for app-owned interface text, menus, errors, and diagnostics.
- Synchronize the saved choice between the manager and Settings helper.
- Package translation resources in both apps and add catalog checks and localization tests.
- Document how to add future languages.

## 0.8.2

- Organize source files by responsibility while retaining the two Swift modules.
- Split model actions, settings pages, data models, and diagnostics into focused files.
- Use English app text, scripts, comments, and maintained documentation.
- Rename the bundled Settings app to SpaceTabs Settings; keep both bundle IDs and saved data keys unchanged.
- Share app identities and preference limits across validation and UI.
- Validate layouts without constructing a store for a fake file path.
- Add formatter configuration, local check scripts, contributor/agent guides, issue and PR templates, and a CI workflow.
- Add contract checks for plist identities, shortcut schema bounds, and Unicode user data.

## 0.8.1

- Resolve zoom from the actual focused managed window instead of a cached zone selection.
- Read right-drag coordinates from Quartz and accept both drag and normal movement events.
- Preserve valid drops while AX capture finishes; reject cancelled or superseded captures.
- Show a moving outline and useful gesture diagnostics.

## 0.8.0

- Isolate AX work by process on serial GCD-backed executors and limit concurrent discovery.
- Add Control + right-drag, quick switching, temporary zoom, tab dragging, and directional navigation.
- Link profiles to physical display setups and add bounded latency diagnostics.

## 0.7.0

- Add profiles, custom shortcuts, zone names, launch at login, and the reversed three-zone template.
- Organize Settings into a sidebar with focused pages.

Earlier prototype work established external-window tabs, public AX placement/focus, safe local persistence, and a separate Settings process.
