# Testing

Keep four results separate: compilation, automated tests, signed packaging, and real desktop behavior. Passing one does not prove the others.

## Automated checks

```sh
Scripts/lint.sh
Scripts/check-docs.py
Scripts/check-localizations.py
Scripts/test.sh
Scripts/build.sh release
```

Tests use Swift Testing. The scripts disable XCTest discovery and the SwiftPM sandbox where needed for local caches and socket-pair checks. Tests do not grant permissions, launch external apps, register login items, or move real windows.

The suite covers layout and coordinates, tab order and selection, placement verification and recovery, focus cancellation, refresh grouping, bounded process work, gesture policy, profile matching, migration, file validation, settings messages, transport framing, and peer identity checks.

Tests for AX behavior use fake backends behind the window-operation protocols. AppKit-level unit tests check coordination and the custom executor without exercising real external windows.

## Optional local-listener test

```sh
SPACETABS_TEST_LOCAL_LISTENER=1 Scripts/test.sh
```

The default suite uses socket pairs for transport checks. The optional test binds a real local Unix socket. Restricted coding environments may reject that bind. Treat it as an unavailable integration check, not as proof that IPC works on the desktop.

CI enables the optional test. Test executables use an ad hoc linker signature so peer-validation tests have a code identity on both Intel and Apple Silicon. This does not use a developer certificate or update `dist`.

## Desktop checks

Use a disposable test document and normal app windows. Close both SpaceTabs processes, build the package, reopen it, and note the exact version and bundle path.

### Tabs and focus

- Open Settings, close its window, and reopen it. The same helper and selected page should return without another process launch. On a first launch, the window should render its connecting state before authentication finishes, then enable its controls after a snapshot arrives. Explicitly quit Settings to exercise the cold path. Quit the manager during startup and verify no orphan helper or socket remains; a disconnected helper should terminate.

- Assign windows from at least two different apps to A and B; include C in a three-zone template.
- Switch each group's tabs and check that the other groups keep their selection and geometry.
- Place two windows from the same app in different zones and verify that the requested window receives focus.
- Click tabs rapidly, open Settings during a pending action, and check that an older action does not steal focus.
- Select SpaceTabs through the Dock and Command-Tab. All selected windows should come forward and B should receive final focus.
- Select SpaceTabs Settings through the same controls. It should open Settings without restoring the workspace.

### Geometry and zoom

- Check all three templates, both resize handles, and minimum proportions.
- Check fixed bars and auto-hide bars with the macOS menu bar and Dock set to visible and auto-hidden.
- Leave **Keep fixed tab bars above all windows** unchecked, cover a bar with an unmanaged app, and verify the app stays unobstructed. Show Tabs should raise bars and resize handles without activating SpaceTabs, then lower them after five seconds without hiding them. Hover, context menus, and tab dragging should hold the reveal; an outside click should lower it immediately. Changing appearance or layout during a reveal must not restart its timer. Check the setting and verify floating behavior; also check pause/resume and auto-hide.
- Restart with saved tabs and verify the bars show **Loading tabs…** during discovery and recovery, then show restored windows. Unmatched saved windows should stop loading and show **Saved windows unavailable** in otherwise empty zones. A later unrelated scan should not show startup loading again. Check that denied permissions, pause, and blocked configuration do not leave a spinner running.
- Include a display with negative coordinates or a vertical offset.
- Resize a managed window manually. A single tab click should preserve its size; double-click should fill the zone.
- Drag the column divider from 25% to 20% and verify the preview line shows Left 20% / Right 80%. Row dragging should show Top / Bottom percentages. Preview must not write external window frames. If an app rejects the new size, the prior layout settings should return and Settings should name the app that rejected it; verify rollback and release still work.
- Focus a window in B while A was selected earlier, then zoom. The focused B window must expand. Repeat the shortcut to restore its previous frame.
- Focus an unmanaged window and try zoom. It must not enlarge a different window in A.

### Drag gestures

- Test Command + Shift with a normal title-bar drag.
- Test Control + right-drag from a window's content. An outline should follow the pointer after capture; the real window moves only on a valid drop.
- Try a quick drag that ends while capture is pending.
- Release Control before mouse-up. No assignment should happen, even if Control is pressed again before mouse-up.
- Start another gesture or click another app after a deferred drop. A late response must not assign the old window.
- Drop outside every zone. The original window should remain unchanged.
- Verify normal right-click with and without the optional gesture enabled.
- Check Diagnostics for raw right-button events, motion events, captures, and cancellation reasons.
- Drag tabs within and between groups. The destination and order should be clear and bars should remain visible during the drag.

### Languages

- Switch between Automatic, English, and Español from General; the selected Settings page and unsaved text should remain in place.
- Check the main menu, status menu, Settings menu/window title, shortcuts, resize handles, tooltips, and quick switcher.
- Relaunch both apps and verify the saved override survives. With Automatic, test Spanish regional preferences and an unsupported language falling back to English.
- Verify profile names, zone names, app names, and document titles are unchanged.
- Test a packaged app outside its build directory with the build resources unavailable.
- Existing event history may retain its original language; new events should use the selected language.

### Profiles and lifecycle

- Save, apply, replace, and delete a profile. Include closed apps and ambiguous window titles.
- Open three Chrome windows across two displays and assign only one. Switch and close browser tabs inside it, then restart SpaceTabs while Chrome keeps running. The same window should recover even if its title and page URL changed. Closing that entire window must not cause a different Chrome window showing its former page to be assigned. Older unmatched sessions need one manual reassignment to record a window number.
- Link a profile to the current display setup, disconnect and reconnect a display, then restart without the previously selected display.
- Pause manually before a display or Space change. An automatic profile must not resume that pause.
- Change native Spaces, enter and leave native full screen, sleep and wake, and lock and unlock the session.
- Test an app that rejects AX notifications or temporarily stops responding. Other apps should remain usable.
- Release a window, release all, and quit. Check recovery of the original frames.

### Permissions and signing

- Build twice using the same certificate and verify actual Accessibility behavior across both builds.
- Check that the running bundle path is the package you intended to test.
- Test denied or revoked Accessibility access without deleting user configuration.
- Enable and disable launch at login only in your normal user session, then verify the system's reported state.

## What to report

Record the toolchain, macOS version, apps, display setup, steps, observed behavior, and diagnostics. Avoid claiming that tests prove low CPU use or low latency on real apps.

Timing summaries show the most recent bounded samples, not a full benchmark. Use Instruments and the Accessibility signpost category for a performance investigation. Discovery can still wait for an individual synchronous AX call to time out.

The latest cleanup was checked locally with automated tests and release compilation. Gesture delivery, focus, display reconnection, permission persistence, and visual layout still require a graphical session.
