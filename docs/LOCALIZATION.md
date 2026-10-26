# Localization

English is the source and fallback language. Spanish is included. The first launch uses **Automatic**, which follows the Mac's preferred languages and chooses the first supported language. Regional variants such as `es-MX` match Spanish. If no supported language matches, the app uses English.

Choose **Settings → General → Language** to select Automatic, English, or Español. The choice is stored in `preferences.json`, sent as a typed Settings command, and mirrored back in the Settings snapshot. It applies to both processes without restarting or resetting the current Settings page.

## Source map

- `SpaceTabsCore/Localization/AppLanguage.swift`: stable stored codes and automatic matching.
- `SpaceTabsCore/Localization/LocalizedMessage.swift`: English keys and interpolation arguments.
- `SpaceTabsCore/Localization/L10n.swift`: catalog loading, fallback, and thread-safe language selection.
- `SpaceTabsCore/Localization/Resources/en.lproj/Localizable.strings`: English source catalog.
- `SpaceTabsCore/Localization/Resources/es.lproj/Localizable.strings`: Spanish translations.
- `SpaceTabs/Interface/AppLocalization.swift`: SwiftUI observation dependency.
- App delegates: native menu/title updates and locale-change notifications.

Translations cover Settings, desktop controls, shortcuts, menus, help, app-owned errors, and explanatory diagnostics. Technical AX attribute names, bundle IDs, keyboard symbols, command-line diagnostic JSON keys, and log identifiers remain stable. External app names, window/document titles, user profile names, and zone names are never translated. Messages supplied by macOS or another app may follow that provider's language.

An existing event or error message keeps the language in which it was produced; new messages use the current language. Switching languages updates interface labels and menus immediately. Diagnostic event history is not rewritten.

## Add app text

Use an English literal through `L10n.tr`:

```swift
Text(L10n.tr("Save Profile"))
message = L10n.tr("Profile “\(profile.name)” saved.")
```

The second example looks up `Profile “{0}” saved.` and supplies the name separately. Add the English key/value and translations to every catalog. Do not use a fully interpolated `String` as a key, concatenate translated sentence fragments, or send user text through translation lookup.

`L10n.text` is for a known catalog key held in a stable enum, such as Settings section titles. Enum raw values, persisted identifiers, and Settings commands must not change when the language changes.

Catalogs use standard Apple `.strings` files. Keep each entry on one line, with JSON-compatible quoted strings and escapes. This makes them readable in text editors and lets the checker catch duplicate keys. Example:

```text
"Profile “{0}” saved." = "Perfil «{0}» guardado.";
```

Keep the same numbered placeholders, including their counts. Translators may reorder them. Percent signs, braces, and format-looking text inside user arguments are inserted literally; no printf or executable format string is evaluated. For new count messages, prefer labels such as `Windows: {0}` when a sentence would require language-specific plural rules. The current interpolation helper does not implement `.stringsdict` plural rules or grammatical inflection.

## Add a language

1. Add an `AppLanguage` case with a base language code, such as `case french = "fr"`. Keep existing codes stable.
2. Add its native display name, such as `Français`, to `displayName`.
3. Copy `en.lproj/Localizable.strings` to a new `fr.lproj` folder and translate every value. Keep keys in English.
4. Add the code to `CFBundleLocalizations` in both plist files under `Resources`.
5. Run the catalog checker, formatter, tests, and release build.
6. Test the language selector, both native menus, long labels, non-ASCII user data, and app packaging on a real desktop.

The language picker enumerates the registered cases. Automatic matching and catalog loading use that same list. SwiftPM processes the resources; the packaging script copies the resource bundle into both apps before signing. A packaged app uses its own resources and does not look in a developer's build directory. Missing translations fall back to English keys.

## Checks

```sh
Scripts/check-localizations.py
Scripts/lint.sh
Scripts/test.sh
Scripts/build.sh release
```

Tests cover automatic matching, explicit overrides, old preference defaults, stored choices, typed Settings messages, complete Spanish key coverage, bundle loading, and safe interpolation with Unicode and placeholder-looking user text. They do not prove that long translations fit every real desktop control.
