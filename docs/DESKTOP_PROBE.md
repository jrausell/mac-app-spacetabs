# Native desktop feasibility probe

Phase 0 of the [workspace profiles plan](WORKSPACE_PROFILES_PLAN.md). Status: the first desktop run passed on the maintainer's two-monitor setup on 2026-11-03. This probe does not establish native Space IDs or implement multi-desktop management.

## Build and launch

```sh
zsh Scripts/build-desktop-probe.sh
```

Open the app path printed by the script. It is a separate accessory app with an `ST?` menu bar item. Quit it from that menu. It does not read SpaceTabs configuration, query Accessibility, inspect external window titles, move external windows, or register shortcuts. SpaceTabs can remain open. The probe has its own disposable ad hoc signature, requires no Accessibility access, and does not replace `dist/SpaceTabs.app` or change its signing identity.

Use the probe menu's **Create marker on…** on the intended display while its intended desktop is visible. Each action creates one labeled, nonactivating visible panel and one immediately ordered-out anchor. Both use `managed` and `fullScreenNone`, with neither `moveToActiveSpace` nor `canJoinAllSpaces`. The probe never shows an existing panel again after a desktop change. This isolates whether AppKit retains the association without a control following the active desktop.

## First check: two desktops on one monitor

1. On the first desktop, create a marker on that monitor. Note its number and whether the previously focused app keeps focus.
2. Switch to a second desktop using your normal gesture or Mission Control. The first marker should disappear. Create a second marker on the same monitor.
3. Switch between the two desktops twice. Only the marker created on the visible desktop should appear. Open `ST?` and choose **Record checkpoint** on each desktop after the transition finishes.
4. On the first desktop, choose **Hide visible marker 1** (or its actual number). Switch to the second desktop and record a checkpoint, then return to the first and record another. This tests whether ordered-out windows retain useful active-Space information after the visible control disappears.
5. Quit the probe. Its markers should disappear. Report whether the markers stayed on their original desktops, whether any focus/desktop jump occurred, and that the run is finished. The coding agent can inspect the local report directly.

No external apps need to be closed for this check. If a marker follows you or appears on both desktops, record checkpoints on both desktops before quitting; that is useful failure evidence.

## Second check: independent desktops per monitor

With two connected monitors and your existing separate-Spaces setting, create one marker per monitor. Change the desktop on just one monitor and record a checkpoint. Its marker should disappear while the unchanged monitor's marker remains. Create another marker on the changed monitor, switch back, and record again. Also note whether creating a marker on a monitor with no active menu bar attaches it to the intended desktop.

Do not change a system preference or log out just to run the first check. The report records `NSScreen.screensHaveSeparateSpaces`; testing the alternate setting is a later session if needed.

## Remaining acceptance matrix

| Scenario | Status |
| --- | --- |
| Visible panel stays on its desktop | Passed in the first session |
| Hidden anchor distinguishes visited desktops | Passed in the first session |
| Ordered-out visible panel retains a useful association | Passed in the first session |
| One monitor changes desktop independently | Passed in the first session |
| Shared-Spaces display setting | Awaiting observation |
| Native full screen / Stage Manager | Awaiting observation |
| Desktop reordering or deletion | Awaiting observation |
| Display disconnect/reconnect, sleep/wake | Awaiting observation |
| Focus remains in the user's external app | Probe was never frontmost in the first report; no unexpected behavior reported |
| Restart association | Intentionally unconfirmed; this probe makes no persisted association claim |

An observed visible-panel success with hidden-anchor failure may still support retained desktop-bound controls during one session. It does not establish reliable empty-workspace detection or reboot recovery. Do not use a false/absent marker observation as permission to relocate apps or assign a native desktop number.

### First-session evidence

The maintainer confirmed that the markers remained on their desktops, including a marker on a second monitor. The local report contained 41 valid records and four manual checkpoints on macOS 15.7.7, with separate Spaces enabled. Display bounds were 2560 × 1440 and 1080 × 1920, with the portrait display to the left and vertically offset.

Markers 1 and 2 alternated their active-Space values on the first display. Marker 3 remained active on the second display during those switches. All visible-marker and hidden-anchor active-Space values agreed, including after marker 1 was ordered out. The probe PID was never the reported frontmost PID. No raw report, local display UUID, or personal file is committed as a fixture.

Decision: proceed with session-scoped desktop-bound controls and retained hidden anchors as a viable integration approach for this tested configuration. Keep desktop associations unconfirmed after process restart. The remaining matrix stays open, especially native full screen, Stage Manager, deletion/reordering, and reconnects; this run is not proof of those cases.

## Reports and interpretation

Reports go to `.local/desktop-probe/reports/desktop-probe-<run UUID>.jsonl`, one private report per launch, capped at 2 MiB. **Copy probe report path** copies the current path. `ST?!` means reporting failed or reached the cap; rerun rather than treating missing records as success.

Each event captures the timestamp, process ID, macOS version, separate-Spaces setting, frontmost process ID, display UUIDs/bounds, and each probe window's number, `isOnActiveSpace`, ordered-in visibility, occlusion visibility, and bounds. Reports contain local display identifiers but no external app titles/documents. Immediate transition snapshots are followed by an 800 ms debounced snapshot; manual checkpoints remain the reference for user-observed settled states. `isVisible` means ordered in, not necessarily on the currently active desktop.

Compare a marker's `onActiveSpace` across manually confirmed desktops. Compare its visible panel with its hidden anchor and confirm changes on one monitor do not invalidate the other. Different anchor values across desktops are evidence for this session only. No polling, AX discovery, private APIs, or window activation is used to infer the result.

Reference interfaces: Apple's [active Space change notification](https://developer.apple.com/documentation/appkit/nsworkspace/activespacedidchangenotification), [active-Space window property](https://developer.apple.com/documentation/appkit/nswindow/isonactivespace), and [window collection behavior](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.property). The probe tests their combination on the actual desktop rather than assuming that individual API documentation proves that combination.
