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
- With fixed bars behind windows, click a visible group label, empty bar area, and app tab. All bars should temporarily come forward while the original tab click, double-click, or drag still works. Turn off **Show all tab bars when clicking a tab or group** and verify these clicks no longer raise other bars; Show Tabs should still work. Click an unmanaged app or a resize handle and verify neither triggers the click reveal.
- Verify only SpaceTabs has a Dock/Command-Tab entry, including on a cold Settings launch. Select SpaceTabs through either control. Selected windows should come forward first, ending the external-window sequence in B; if Settings is still open, it should then receive focus above them. With Settings closed, B should keep focus and Settings should stay closed. Repeat with Settings covered, hidden, and minimized, with no managed windows, and while management is paused or Accessibility is denied.
- Close Settings while a workspace restore is pending and verify the completion does not reopen it. Choose another app or tab while restoration is pending and verify the cancelled request does not later raise Settings. Explicitly open Settings from the menu or + button to reopen it; assigning apps there must preserve its focus.

### Modifier-only shortcuts

- Tap Control + Option + Command in different press/release orders. Show Tabs should run once, after all three are released, both in Settings and in another app. Confirm Accessibility access for global keyboard observation.
- Use the same modifiers with arrow keys, another letter, Shift, Fn, a click, a drag, or scrolling. Releasing them must not also show tabs. Hold a regular key or mouse button before pressing the modifiers and verify cancellation.
- Edit, disable, restore defaults, and relaunch with a modifier-only binding. Existing explicit Control + Option + T and custom bindings must remain intact. Check registration warnings, shortcut labels in English/Spanish, and ordinary key shortcuts.

### Geometry and zoom

- Check all three templates, both resize handles, and minimum proportions.
- Check fixed bars and auto-hide bars with the macOS menu bar and Dock set to visible and auto-hidden.
- Leave **Keep fixed tab bars above all windows** unchecked, cover a bar with an unmanaged app, and verify the app stays unobstructed. Show Tabs should raise bars and resize handles without activating SpaceTabs, then lower them after five seconds without hiding them. Hover, context menus, and tab dragging should hold the reveal; an outside click should lower it immediately. Changing appearance or layout during a reveal must not restart its timer. Check the setting and verify floating behavior; also check pause/resume and auto-hide.
- Restart with saved tabs and verify the bars show **Loading tabs…** during initial discovery, then only in zones actively recovering saved windows. Unmatched saved windows should stop loading and show **Saved windows unavailable** in otherwise empty zones. With unmatched saved windows still pending, select Terminal in C and verify A and B do not show loading. Later unrelated scans should not show startup loading again. Check that denied permissions, pause, blocked configuration, and failed recovery do not leave a spinner running.
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

- Close a managed window using its red close button while the app remains running. Its app should stay visible as a Pending placeholder unless another managed window of that app already occupies the zone. Click that pending tab: if the app provides one new compatible window, it should return to the zone. If it does not create a window, creates ambiguous windows, or does not restore the saved document, the assignment must remain pending with an explanation. Existing windows of the same app, including windows on other desktops, must not be adopted by the explicit reopen path. Change desktop/profile or pause during reopening; no late result may move a window. Test Remove Saved Assignment, both successful persistence and a rejected write. Opening an app independently is still subject to strict window matching and is not equivalent to requesting an explicit replacement through a pending tab.

- Close the middle tab of three managed windows, then quit the remaining apps. Their saved assignments and original ordering should remain pending across a SpaceTabs restart. Save or replace a disposable named profile while these windows are closed and verify its saved window count includes them. Reopen uniquely identifiable windows and verify matching tabs return to their saved positions; closing a known browser window must not adopt a different browser window showing its former page. Release a live window explicitly and verify it is not added back as pending. Forget Pending Windows explicitly removes pending records. Opening missing apps and recreating closed windows remain separate planned work.

- Save, apply, replace, and delete a profile. Include closed apps and ambiguous window titles.
- Open both native Profiles submenus and verify saved names, deletion/updates on reopen, and disabled actions during pause or busy work. Enable manual app opening for a profile, close an assigned app, then apply from the menu and Settings. Verify it opens in the background and joins the correct zone without stealing Settings focus. A running app must not open again. Verify the default-off option, older profiles, failed app paths, failed layout commits, cancellation by another profile, and automatic display switching. Specific browser windows must not become broad app assignments merely because they were saved in a profile.
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

### Persistent diagnostics

- Verify both processes create local logs, then provoke a rejected resize or unavailable window. Check timestamps, source sites, operation IDs, typed error fields, and the affected PID/AX code where available. Replace the UI notice and restart; the earlier record must remain until rotation.
- Check **Copy Log History** and **Show Logs in Finder** in Settings. Verify they still work when the manager is unresponsive. Copy Full Diagnostics should include history alongside its live counters.
- In a disposable debug session, pause the manager main thread for more than three seconds and verify a single suspected-stall record is written before resuming. Resume and verify duration. A debugger pause is expected to trigger the detector and is not an app failure. Check the separate helper similarly, and ensure sleep/wake does not generate a stale stall warning.
- Force Quit a test process, relaunch, and check the missing shutdown marker. Quit normally and relaunch; there should be no interruption warning. Review rotation and permissions in temporary fixtures; never fill the user's production logs as a test.

Automated diagnostic tests use temporary directories and synthetic errors. They cover rotation, private files, rejected symlinks, retained history, interrupted versus clean sessions, source/error metadata, operation completion/slow-warning deduplication, heartbeat recovery, and scheduling gaps. They do not prove real-desktop hang detection or identify a real blocked stack.

## What to report

Record the toolchain, macOS version, apps, display setup, steps, observed behavior, and diagnostics. Avoid claiming that tests prove low CPU use or low latency on real apps.

Timing summaries show the most recent bounded samples, not a full benchmark. Use Instruments and the Accessibility signpost category for a performance investigation. Discovery can still wait for an individual synchronous AX call to time out.

The latest cleanup was checked locally with automated tests and release compilation. Gesture delivery, focus, display reconnection, permission persistence, and visual layout still require a graphical session.

### Browser page and pending-tab regressions

- Use a Chrome window with many web tabs. Changing or closing its active web tab must not create additional SpaceTabs tabs. Distinct assigned native Chrome windows must remain independent. Test with the same URL in two windows and overlapping window frames.
- Load a profile containing many legacy browser titles/URLs. The zone must show at most one pending placeholder for that app, named after the app. Once that zone has a managed Chrome window, old Chrome pending references must not add visible tabs. Do not silently delete those recovery records. Other zones may independently retain their own pending app placeholder.
- Explicitly remove a grouped pending app and verify only that app’s pending assignments in that zone are removed; live windows and other zones are preserved. A rejected checkpoint must retain the assignments.

### Synchronizing an already-open saved app

- Keep Godot or Mail open with one ordinary unassigned window. Click its pending app placeholder. Verify a scoped refresh discovers the running app even if it is absent from the installed-app catalog, and that the existing window joins the saved zone without launching a duplicate.
- Open two native Chrome windows with several web tabs. Clicking Chrome Pending must present two native-window choices. Choose one; only that window should join the zone. The other window and other zones remain unchanged. Repeat with identical page titles and overlapping frames; unproven window identities must not be guessed.
- Close the selected window, assign it elsewhere, or change desktop while its chooser is open. A stale choice must not move it. Dismissing the chooser keeps the assignment pending. Other-desktop, already-managed, or unidentifiable windows must produce an actionable message near the tab.
- Provoke a placement or storage failure when replacing a pending slot. Retain the pending assignment after successful rollback; retain original release frames if recovery fails. Explicit synchronization must not relax automatic saved-window matching.

### Window sizing during app startup

- With fixed tab bars and a three-zone template, reopen Firefox from its pending app placeholder. Check the final top edge and height after startup, including when Firefox restores a previously full-height frame. Repeat with auto-hide: the target should then use the full zone content height.
- Confirm that only the recovered window is corrected during the bounded startup checks. Another zone must not resize or change selection. A later single tab click preserves manual geometry as before.
- During the startup check interval, resize a window, change tabs, change native desktop, pause, or edit the layout. The stale correction must stop. Test a short completed drag as well as a held mouse button.
- Simulated-backend tests cover a late full-monitor height overwrite, fixed-header clearance, unaffected neighboring windows, stale/manual geometry, and rollback when a startup correction is rejected. These tests do not prove Firefox’s actual startup timing.

### Overnight display and shortcut recovery

- With no automatic display profile, sleep and wake or lock/unlock the Mac and change monitor availability. Show Tabs and normal zone shortcuts should work again after the display/Space transition settles, without Resume or Reapply Layouts. The selected display must remain the intended physical monitor.
- Disconnect the selected monitor: controls should wait for it, not relocate to another screen. Reconnect it, including through a dock that changes its runtime display number, and check automatic control/shortcut recovery. A changed physical identity requires an explicit display choice.
- Pause manually before sleep/display changes; it must remain paused. Repeat after a genuine recovery failure. Temporary display recovery must not resume either pause.
- Change native desktops while monitor wake/reconnect notifications arrive in either order. No transition task may remain pending after both debounces finish. Wake alone must not reapply a linked profile or raise external windows.
- Automated tests cover stable display identity, no fallback to another monitor, missing/returning monitors, manual pause retention, both Space/display event orders, repeated wake coalescing, and Show Tabs routing after recovery. Actual global key delivery and overnight panel restoration still require the desktop check.


## Workspace isolation acceptance (2026-11-05)

Automated tests cover separate record checkpoints, legacy migration without overwriting the old session, unsupported/invalid registry rejection, shared manager identity, UUID/native-window alias ownership reservations, pending intent without live claims, desktop availability without membership changes, preserved manual pause, and rejection of stale/unscoped Settings commands. These tests do not verify AppKit desktop assignment or external AX behavior.

On the packaged app:

1. In the main native desktop, create a workspace on each monitor through the Workspaces menu. Assign different windows and verify independent zone membership and layouts.
2. Create/switch to another native desktop. Existing bars must stay behind. Create another workspace there; switch back and verify the original tabs, selections, and geometry.
3. Open Jorge and test1 in the same destination. The previous instance must close and retain its slots; the new instance must use its own saved content without inheriting unlisted tabs.
4. Use separate windows of Chrome in two workspaces. A window already owned by another instance must not be available for reassignment or pending recovery; ambiguous unowned windows require choosing.
5. Resize a managed window and close another with its red button. Restore only that workspace; verify geometry/header clearance and pending app recovery. Other workspaces must retain their state. Show should end in B.
6. Close a workspace and open it on a different desktop; its controls must be recreated there, with its original slot intent retained.
7. Quit/relaunch SpaceTabs. Saved workspaces must be closed and independently reopenable here on the intended desktop/monitor. Do not claim automatic persistent native desktop binding.
8. Edit different zone names/appearance and switch Settings rapidly. Delayed controls from the previous snapshot must not change the newly selected workspace.
9. Test sleep/wake, monitor reconnect, full-screen apps, and manual pause. Confirm shortcuts recover, bars do not migrate, and pauses remain explicit.


## Desktop Finder menu

Follow [Desktop menu acceptance](DESKTOP_MENU.md#verification) after packaging. Automated request/authorization, storage, dispatch, and plist tests do not prove extension registration, sandbox read access, Finder menu placement, Launch Services delivery, or native desktop targeting. Verify these separately before claiming the right-click integration works on a user's setup.


The integrated Finder extension no longer traps on worker-thread callbacks, but a real Desktop menu test on macOS 15.7.7 found no SpaceTabs entry on the maintainer's iCloud/File Provider Desktop. This remains a platform/integration limitation, not a passed acceptance test. See [the recorded findings](DESKTOP_MENU.md#confirmed-icloud-limitation). Settings IPC tests cover true, false, and unknown cloud status without reading a user's files.

## Visual guide and status dashboard

- Open the menu with workspaces on the current desktop, another desktop, and closed. Check layout thumbnails, monitor names, state labels, scrolling, and Show/Restore availability. Buttons must close the menu and target their own workspace. Merely opening the menu must not move windows or change focus.
- Open How To using the question mark, with Settings both open and closed. Check all three illustrated cases, including the planned portrait badge, at minimum Settings size. Check English/Spanish and light/dark appearances without resetting the selected page.
- Ensure the guide distinguishes automatic workspace checkpoints from explicit profile saves and explains restart rebinding. The portrait drawing must not imply that a two-row template already exists.

## Setup renaming

- Rename a workspace using the pencil beside the Settings selector, including a closed workspace and one on another desktop. Its header, picker, status menu, and Finder snapshot should use the new name. Rename a profile through its ellipsis menu and check the profile list and menus. Neither rename should change the other name, move windows, open apps, or resume a paused workspace.
- Cancel the rename sheet and submit blank, overlong, accented, and emoji names. Cancel/invalid input must leave the saved name unchanged; valid names survive restarting SpaceTabs. Automatic tests cover typed transport, stale context rejection, unchanged recipe/UUID/link data, snapshot propagation, validation, and failed writes.
