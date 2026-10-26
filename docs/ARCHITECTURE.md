# Architecture

SpaceTabs adds zones and tab bars to the macOS desktop. It does not own the windows it manages and does not replace macOS Spaces.

## Terms

| Term | Meaning |
| --- | --- |
| Zone | A rectangle containing a group of tabs, identified by A, B, or C. |
| Tab | A reference to a real external window. |
| Selected tab | The window chosen for a zone. Only one window across the desktop can have keyboard focus. |
| Profile | Saved layout preferences, window identities, selections, and app assignments. |
| Workspace restore | An explicit action to bring selected windows from all zones forward, ending in B. |
| macOS Space | A desktop or native full-screen environment controlled by macOS. It is not a zone or profile. |

## Modules and processes

`SpaceTabsCore` contains value models, geometry, policies, validation, and window-operation protocols. It does not import AppKit, SwiftUI, or ApplicationServices. It uses Foundation, CoreGraphics value types, and Darwin for private local-file storage.

`SpaceTabs` provides native integration and the UI. The same executable is packaged twice:

```text
SpaceTabs.app                         dev.spacetabs.mac
└── Contents/Helpers/SpaceTabs Settings.app
                                      dev.spacetabs.mac.settings
```

The main process owns window management, shortcuts, overlays, persistence, and login registration. The Settings process owns its window and Dock identity, mirrors manager state, and sends typed commands. It does not start a second catalog watcher or AX manager.

This split is deliberate: choosing SpaceTabs in Command-Tab restores the workspace; choosing SpaceTabs Settings opens the settings window.

## Source map

```text
Sources/
  SpaceTabs/
    Application/       Entry point, AppDelegate, permission settings
    Model/             AppModel state and extensions grouped by behavior
    WindowManagement/  AX coordinator, process sessions, serial executors
    Input/             Carbon shortcuts and both drag controllers
    Settings/          Helper lifecycle, messages, connection, transport
    Interface/
      Desktop/         Tab bars, resize handles, quick switcher
      Settings/        Settings shell and individual pages
    Applications/      App-directory change monitor
  SpaceTabsCore/
    Layout/            Templates, split tree, coordinates, navigation
    Windows/           Snapshots, backend protocols, placement/focus/recovery
    State/             Tabs, selection runner, visibility, gesture policies
    Discovery/         Catalog, refresh queue, retry policy, bounded work
    Persistence/       Saved data, limits, migration, validation, stores
    Diagnostics/       Bounded timing samples
    Localization/      Language preference, catalogs, and safe interpolation
```

## State ownership

`AppModel` is the main-actor coordinator. Its declaration contains observable state and runtime services. Extensions implement one area of behavior: selection, window actions, transactions, geometry, discovery, profiles, permissions, diagnostics, and settings forwarding.

`TabManager` owns membership, order, and per-zone selection as a value. It does not activate or resize windows. `LayoutEngine` calculates rectangles without querying a display or an app. Templates become a small split tree whose leaves are tab groups.

The `applied...` fields in `AppModel` record the last accepted layout preferences. They support recovery when an app rejects a new layout. `originals` keeps release/recovery states; `pendingTabs` keeps saved windows not yet matched safely.

`desktopRevision` invalidates work across desktop changes. `presentationRevision` invalidates older focus requests when the user acts again. They serve different lifetimes and should not be merged.

## AX and concurrency

`WindowManager` routes UUIDs to `WindowProcessSession` actors. Each session owns its AX elements, observer registrations, cache, and retry state. No AX handle is passed to a view, `AppModel`, or another process.

AX calls are synchronous IPC. Each session uses `AXQueueExecutor`, a serial GCD-backed actor executor, so a slow app does not block the main actor or Swift's cooperative executor. The pointer hit-test has its own executor. Discovery is limited to three sessions at once by `BoundedWorkPool`.

A running AX call cannot be cancelled instantly. Timeouts bound individual calls; discovery also checks a cooperative budget between windows. Commands for the same app may still wait for that app. Do not describe this as a hard real-time guarantee.

`WindowRefreshQueue` groups structural events by process. Title changes do not schedule discovery. File-system notifications and explicit refreshes update the installed-app catalog. A five-second environment check observes permissions and display bounds; it is not a full window scan.

Known tab selections and explicit drag assignments need not wait for unrelated discovery. A discovery result waits before applying structural changes during a transaction. The merge retains newly adopted managed windows that an older snapshot did not contain, unless the window was explicitly removed.

## Placement and recovery

`WindowOperations` works through `WindowAccess`. It snapshots live state, validates placement, performs bounded retries, and verifies the frame an app accepted. A geometry failure attempts rollback. Failed recovery states remain available so the user can release windows.

Normal reflow does not raise windows. Tab switching does not minimize other tabs. Switching focus and changing geometry are separate operations; a single click preserves manual geometry, while a double click fills that window's zone.

Fixed bars reserve a header. Auto-hidden bars float over full-height zone content. Coordinate conversion uses the primary display's top edge, not the chosen monitor's height. This matters for monitors with negative or offset coordinates.

## Focus and zoom

`TabSelectionRunner` serializes focus work and lets a newer choice cancel an older one. `WindowFocusOperations` requests activation, confirms it, raises the specific window, and confirms focus. It stops when the request is no longer current.

Workspace restore is a finite user action, not a focus-enforcement loop. It presents each zone's selected window and finishes with B, regardless of the template's physical order.

Zoom uses `FocusedZoomTarget` to resolve the actual focused managed window. An unknown or unmanaged focus does not fall back to A. A zoom stores the previous frame temporarily and is restored before another layout operation or tab selection. It does not create a native full-screen Space.

## Input and overlays

The native Command + Shift drag uses passive event monitors. It confirms a real window move before showing targets.

Control + right-drag uses a public CGEvent filter to reserve its mouse sequence. Its callback does no AX work and does not render panels. It uses Quartz event coordinates and accepts both `rightMouseDragged` and `mouseMoved` samples.

`RightDragState` controls movement and cancellation. `RightDragCaptureLease` controls asynchronous capture lifetime: mouse-up over a valid zone may wait for its own capture; releasing Control first or starting a new gesture invalidates that capture. A later user interaction also prevents a deferred assignment.

The ghost and zone panels appear only after identifying the source window, so they do not cover the AX hit-test point. Preview updates are coalesced. No external window is moved during the preview.

Desktop controls use nonactivating panels. The quick switcher must not activate the main app and accidentally trigger workspace restore.

## Settings IPC

`SettingsHost` starts the bundled helper and publishes a `SettingsState` snapshot when observed state changes. Equal snapshots are not sent again. `SettingsCommand` is a typed, validated enum executed by the main process.

The transport uses a local Unix socket with a random path and user-only permissions. Both ends verify the peer PID and exact expected code hash. Frames are bounded to 4 MiB; typed message data is limited to 2 MiB. I/O runs on a serial background queue with a write timeout. No TCP service or executable configuration is involved.

When adding a setting, follow this path:

1. Define its validated model and persistence defaults, if needed.
2. Add the manager operation and typed command.
3. Add a snapshot field and mirror it without emitting an update back to the manager.
4. Bind the helper view to that state.
5. Test migration and the command/snapshot round trip.

## Localization

`L10n` loads the shared English/Spanish catalogs once and protects the current resolved language with a mutex for AX-session callers. `AppLocalization` exposes language changes as a SwiftUI observation dependency. Views update without replacing their identity; app delegates rebuild native menus and titles. The manager owns the persisted preference and receives typed language commands from Settings. Both packaged apps include the resource bundle. See [Localization](LOCALIZATION.md) for translation rules and adding a language.

## Desktop transitions

A Space notification temporarily suspends management while the animation settles. It does not itself move windows, discover all apps, restore a session, or clear a manual pause.

A physical display change is different. A linked profile can apply after a debounce and after current work finishes. Otherwise SpaceTabs pauses and asks the user to choose the intended display. Overlapping Space and physical-display transitions share their suspension state.

Do not infer native Space membership from an omitted AX window. Public AX discovery is not a native Space identifier API.

## Changes that need special care

Keep bundle identities, saved enum values, shortcut action IDs, and decoder defaults stable. Their source of truth and tests are described in [Configuration](CONFIGURATION.md). Use [Testing](TESTING.md) for real-desktop checks and [Signing](../SIGNING.md) when changing packaging.
