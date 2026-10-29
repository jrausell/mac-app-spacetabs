# Troubleshooting

## Accessibility looks enabled but windows are missing

Check the version, PID, bundle path, and Accessibility result in **Settings → Diagnostics**. macOS authorizes a running code identity, not just an app name. Another copy or an ad hoc rebuild may explain a stale entry in System Settings.

Use **Check Access** and **Show This App** to identify the intended bundle. If macOS requires a restart, quit both SpaceTabs processes and reopen the same package. Do not delete session files as a permission fix. See [Signing](../SIGNING.md) for stable development signatures.

## The build succeeds but the app does not change

`Scripts/build.sh` only compiles. `Scripts/build-app.sh` also packages and signs.

If packaging reports a signing failure, `dist/SpaceTabs.app` still contains the previous version. Run packaging from a normal Terminal that can access your configured keychain identity. The script does not silently fall back to ad hoc signing after a configured identity fails.

## Settings is missing or does not connect

Build the full app package and close both old processes before opening it. Settings is a bundled helper with its own code identity. A bare `swift run` executable does not contain that helper.

The main process verifies the expected helper signature and the helper verifies the manager. Mixing binaries from different builds can fail that check. Do not weaken peer verification to hide a packaging problem.

## Control + right-drag does nothing

Check that it is enabled in **General**, Accessibility is granted, and SpaceTabs is not paused or in demo mode. Use it over a standard external window, not a menu, dialog, or SpaceTabs control.

Read **Diagnostics → Control + Right-Drag Gesture**:

- No right-button events: the filter may be unavailable, disabled by macOS, or not receiving the input expected from the device.
- Right-button events without Control matches: inspect the last modifier flags and any input remapping.
- Motion but no capture: read the AX capture error. Try the window's title bar to compare.
- A cancelled capture or drop: read the recorded reason, such as releasing Control or acting on another app.

A valid drop may wait for its own AX capture. The outline is a preview; the real window is placed only after assignment. The older Command + Shift title-bar drag remains available. Normal right-click is separate from the optional Control chord.

## Zoom changes the wrong window or does nothing

Zoom should resolve the actual focused managed window, including B or C when A was selected earlier. It should not fall back to A when the focused window is unmanaged or unknown.

Record which window was focused, whether it was a native tab inside another app, the selected zone, and the last shortcut event. Include the app version and reproduction steps.

## A tab cannot resize or receive focus

Some apps impose a minimum size, use nonstandard AX windows, or have a modal dialog above the window. Try another zone size, close the dialog, and use **Refresh** for an explicit retry.

Columns allow 20–80%. If the preview reaches 20% but returns to its old position after release, check the Settings message for the app that rejected resizing. On a 2560-point desktop, 20% is 512 points; a window whose minimum width is larger cannot fit. Release that window from its zone or choose a wider split. SpaceTabs preserves the previous layout settings instead of accepting a window that spills into another zone. The drag guide shows live left/right or top/bottom percentages while actual windows stay still until release.

AX notification warnings do not by themselves mean global Accessibility access was lost. A temporarily unresponsive app is retried with limits while known windows stay cached. Failed recovery can pause management so original frames remain available for release.

## SpaceTabs is paused

A manual pause is retained. A native Space transition should only cause temporary suspension. A physical display change without a linked profile can require checking the selected display and choosing **Resume**.

Read the current message before resuming. **Release All** is available when you want to stop managing the windows. Do not repeatedly force reflow while a real app is failing recovery.

## What to include in a report

Give the version, build source, macOS version, affected apps, template, display arrangement, steps, and expected result. Use **Copy Full Diagnostics**, then remove private paths and document/window names before sharing it. A screenshot can help explain visual layout, but diagnostics are more useful for event and focus failures.

## Persistent problem history

SpaceTabs records local diagnostic history automatically while the manager and Settings run. In **Settings → Diagnostics → Problem History**, use **Copy Log History** to share recent history or **Show Logs in Finder** to attach the files. These actions read local files directly, so they do not wait for the manager. **Copy Full Diagnostics** also includes that history, but its live AX counters still require a responsive manager and AX sessions.

Files are in `~/Library/Logs/SpaceTabs/`: `manager.jsonl`, `manager-previous.jsonl`, `settings.jsonl`, and `settings-previous.jsonl`. Each is capped at 1 MiB, with two generations per process. Logs survive restarts, rotating the oldest history. No log is uploaded automatically. Messages can include app names, window titles, and local paths; review them before sharing.

Records include UTC timestamps, PID, severity, event ID, source file/function/line, and available context. Handled manager errors include the error type/domain/code/reason. AX failures include the target PID, AX attribute and code. Profile/layout transactions, tab selection, and per-app discovery record operation IDs and durations; unfinished operations emit one warning after ten seconds. Notices, permissions/configuration errors, Settings commands, and transport failures are also retained. Normal cancellation is not an error.

A utility-queue heartbeat reports a **suspected UI stall** when the main queue has not acknowledged a heartbeat for three seconds. It logs once while blocked and reports recovery duration if the UI responds again. Long monitor gaps reset the sample to avoid treating sleep or delayed background scheduling as a UI failure. This monitor does not poll AX, scan windows, sample stacks, or restore focus. A slow async AX request can leave the UI responsive; its operation history is separate from the heartbeat.

A new session reports a previous missing clean-shutdown marker as an interrupted session. That can mean a crash, Force Quit, or another interruption; it is not proof of a crash. A hard crash cannot reliably write its final error. For crashes also attach the relevant macOS report from `~/Library/Logs/DiagnosticReports/`. For a persistent freeze, a process sample from Activity Monitor can help identify the blocked stack. Include the time of the problem and reproduction steps with the logs. Logging improves diagnosis; it does not establish every root cause or repair existing freezes by itself.
