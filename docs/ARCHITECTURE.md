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

The main process owns window management, shortcuts, overlays, persistence, and login registration. The Settings process owns its window, mirrors manager state, and sends typed commands. It runs as an accessory app, with no separate Dock or Command-Tab entry. It does not start a second catalog watcher or AX manager.

The process split keeps Settings responsive independently of window management. Choosing SpaceTabs in Command-Tab or the Dock restores the workspace and then presents Settings if its window is still open. An explicit Settings action can reopen its closed window.

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

`WorkspaceCoordinator` owns the workspace registry, selected workspace, desktop anchors, window ownership reservations, and per-workspace panel controllers. Each workspace has a separate `AppModel`; the discovery owner also serves as the shared process-service coordinator. `AppModel` is the main-actor workspace model. Its declaration contains observable state and runtime services. Extensions implement one area of behavior: selection, window actions, transactions, geometry, discovery, profiles, permissions, diagnostics, and settings forwarding.

`TabManager` owns membership, order, and per-zone selection as a value. It does not activate or resize windows. `LayoutEngine` calculates rectangles without querying a display or an app. Templates become a small split tree whose leaves are tab groups.

The `applied...` fields in `AppModel` record the last accepted layout preferences. They support recovery when an app rejects a new layout. `originals` keeps release/recovery states; `pendingTabs` keeps saved windows not yet matched safely.

`desktopRevision` invalidates work across desktop changes. `presentationRevision` invalidates older focus requests when the user acts again. They serve different lifetimes and should not be merged.

## AX and concurrency

`WindowManager` routes UUIDs to `WindowProcessSession` actors. Each session owns its AX elements, observer registrations, cache, and retry state. No AX handle is passed to a view, `AppModel`, or another process.

AX calls are synchronous IPC. Each session uses `AXQueueExecutor`, a serial GCD-backed actor executor, so a slow app does not block the main actor or Swift's cooperative executor. The pointer hit-test has its own executor. Discovery is limited to three sessions at once by `BoundedWorkPool`.

A running AX call cannot be cancelled instantly. Timeouts bound individual calls; discovery also checks a cooperative budget between windows. Commands for the same app may still wait for that app. Do not describe this as a hard real-time guarantee.

`WindowRefreshQueue` groups structural events by process. Title changes do not schedule discovery. File-system notifications and explicit refreshes update the installed-app catalog. A five-second environment check observes permissions and display bounds; it is not a full window scan.

Each discovery batch reads public Window Server metadata once on a dedicated GCD executor. Per-process sessions associate a window number only with a unique process/bounds match and retain it while the same AX window lives. Page titles and URLs can change without changing that number. Discovery and drag capture reuse the runtime UUID when a replacement AX wrapper uniquely matches the same PID and public window number. Discovery emits one entry per known native window number, preferring the focused AX wrapper when several wrappers share it, and renews notification registrations when replacing an AX handle. Unknown or ambiguous window numbers are not merged by title, URL, or geometry alone. Saved-session recovery uses it only with the original PID and process launch date; profiles do not carry process-local numbers. Drag assignment can read the metadata after capture, outside gesture callbacks.

Known tab selections and explicit drag assignments need not wait for unrelated discovery. A discovery result waits before applying structural changes during a transaction. The merge retains newly adopted managed windows that an older snapshot did not contain, unless the window was explicitly removed.

## Placement and recovery

`WindowOperations` works through `WindowAccess`. It snapshots live state, validates placement, performs bounded retries, and verifies the frame an app accepted. A geometry failure attempts rollback. Failed recovery states remain available so the user can release windows.

Startup and explicit pending-app recovery placements perform two additional frame checks after 300 ms and another 700 ms. Only affected windows are corrected if an app restores its old frame after accepting the initial AX placement. Fresh app sessions (within 30 seconds of launch) opt into the same finite settlement. The checks use the full zone content rectangle, including fixed tab-bar clearance. They share the original placement rollback state, do not raise/focus windows, and stop when desktop/layout/selection changes or user input counters change. Input counters are sampled only for this operation; no event monitor, idle discovery, or continuous geometry enforcement is added.

Normal reflow does not raise windows. Tab switching does not minimize other tabs. Switching focus and changing geometry are separate operations; a single click preserves manual geometry, while a double click fills that window's zone.

Fixed bars reserve a header. Auto-hidden bars float over full-height zone content. Coordinate conversion uses the primary display's top edge, not the chosen monitor's height. This matters for monitors with negative or offset coordinates.

Fixed bars optionally rest one window level below normal app windows. TabBarVisibility tracks a temporary Show Tabs reveal independently of permanent visibility: expiry lowers fixed bars instead of hiding them. PanelController changes only the bars' and resize handles' public NSWindow levels; it does not reorder, query, or resize external windows to enforce this setting. Layout updates do not renew the reveal timer.

Fixed bars rest behind app windows by default. The foreground checkbox inverts the existing stored background preference. Loading appears in all bars only until initial discovery completes. Session recovery then marks only the zones with matched windows being restored; profile application marks its target zones. Both clear that state on success, failure, or cancellation. Unmatched saved tabs, tab selection, generic busy state, and background refreshes do not themselves show loading. No loading timer, extra scans, or new persistence fields are needed.

The local AppKit mouse monitor identifies left clicks by the actual tab-bar window, covering native app-tab buttons and group backgrounds. The default click preference requests the existing all-bar reveal without consuming the event, querying AX, changing selection, or activating SpaceTabs. Resize panels and external app windows are excluded. The preference travels through the existing appearance command and snapshot.

The status menu hosts a SwiftUI dashboard in a native menu item. Its layout thumbnails and availability badges use a value snapshot refreshed when the menu opens. Buttons end menu tracking before invoking coordinator actions; rendering performs no AX discovery or window writes. Native Workspaces menus list independent instances and per-instance Show/Restore/Close actions. Profile opening is routed to `WorkspaceCoordinator`, which creates an empty model populated only by that profile's saved assignments, or reuses its latest workspace checkpoint. It closes an occupied destination before attaching the new workspace, preserving recovery errors rather than claiming windows twice. Each accepted pre-placement checkpoint reserves live window UUIDs; ownership checks also recognize PID/native-window-number aliases. Pending slots do not reserve live windows. New bindings require a known on-screen window number; window titles alone never prove desktop membership.

All workspace models share one `WindowManager` and `ApplicationCatalog`. One discovery owner coalesces AX/app requests and publishes snapshots to the other models after their in-flight operations finish. Desktop transitions request a single bounded discovery batch for processes owning on-screen windows; the five-second environment check reads only display/anchor metadata. Closed/inactive workspaces cannot place or automatically adopt windows. Shortcut actions resolve the focused managed workspace, then the workspace under the pointer; Show Tabs reveals all currently reachable workspaces. Drag controllers choose a workspace from pointer geometry at gesture start without AX or UI work in the callback.

Tab controls and retained ordered-out anchors use `[.managed, .fullScreenNone]`, never `moveToActiveSpace`. Controls are discarded on close and recreated on explicit reopen, so they inherit the destination desktop instead of reusing an old native window. Desktop membership is session-only. After restart, workspaces remain closed until explicitly opened here; public macOS APIs do not provide a stable persistent native desktop identity.

## Focus and zoom

`TabSelectionRunner` serializes focus work and lets a newer choice cancel an older one. `WindowFocusOperations` requests activation, confirms it, raises the specific window, and confirms focus. It stops when the request is no longer current.

Workspace restore is a finite user action, not a focus-enforcement loop. It presents each zone's selected window and finishes the external-window sequence with B, regardless of the template's physical order. For Dock/Command-Tab activation, a guarded completion then sends `presentIfOpen` over the authenticated Settings channel. The helper brings its window forward only if it has not been closed; hidden or minimized open windows are restored. This does not launch a helper. A cancelled or superseded restoration does not present Settings. With no manageable selected windows, activation can still present an open Settings window. The helper does not reopen Settings merely on application activation.

Zoom uses `FocusedZoomTarget` to resolve the actual focused managed window. An unknown or unmanaged focus does not fall back to A. A zoom stores the previous frame temporarily and is restored before another layout operation or tab selection. It does not create a native full-screen Space.

## Input and overlays

Ordinary key shortcuts use exclusive Carbon registration. Modifier-only shortcuts use passive local/global AppKit monitors and a pure `ModifierTapState` policy. A clean chord fires on full release; keys, mouse activity, scrolling, Fn, and unrelated modifiers cancel it. Carbon shortcut delivery also cancels a pending modifier tap because registered key presses may bypass passive observation. Monitors are removed and state discarded when bindings restart. Passive observation cannot detect other apps using the same modifier tap and requires Accessibility permission for global key events.

The native Command + Shift drag uses passive event monitors. It confirms a real window move before showing targets.

Control + right-drag uses a public CGEvent filter to reserve its mouse sequence. Its callback does no AX work and does not render panels. It uses Quartz event coordinates and accepts both `rightMouseDragged` and `mouseMoved` samples.

`RightDragState` controls movement and cancellation. `RightDragCaptureLease` controls asynchronous capture lifetime: mouse-up over a valid zone may wait for its own capture; releasing Control first or starting a new gesture invalidates that capture. A later user interaction also prevents a deferred assignment.

The ghost and zone panels appear only after identifying the source window, so they do not cover the AX hit-test point. Preview updates are coalesced. No external window is moved during the preview.

Desktop controls use nonactivating panels. The quick switcher must not activate the main app and accidentally trigger workspace restore.

## Settings IPC

`SettingsHost` starts the bundled helper and publishes a `SettingsState` snapshot when observed state changes. Equal snapshots are not sent again. `SettingsCommand` is a typed, validated enum executed by the main process.

The visual How To page uses code-drawn monitor/window sketches. A typed `openHowTo` request increments the mirrored `howToRequest` navigation counter; it does not select a different workspace or change its layout. The status dashboard uses the same navigation state when opening the guide.

Closing the Settings window keeps the helper and its view state ready for reuse. Show requests use the authenticated channel without another Launch Services request while the helper is connected. Explicit Quit, manager shutdown, and connection loss still terminate the helper. The first Settings window is constructed before authentication; its controls remain disabled until the first verified snapshot arrives. Signature inspection and socket setup run on a dedicated serial GCD queue, with cancelled startup resources disposed before they can outlive the manager.

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

Physical display changes and wake/session activation use a 900 ms debounce. The legacy standalone profile path can apply a linked profile after a real display change and current work; workspace instances preserve stored links but disable automatic global replacement; wake alone does not reapply a profile. A display event cancels and clears an older Space-transition task, while a later Space event may finish independently. This prevents an orphaned task handle from keeping management suspended. Coalesced wake events retain a pending physical display change’s profile intent.

Display unavailability is a transient state separate from `paused`. The runtime `DisplaySelectionTracker` remembers the selected physical display UUID and resolves a changed runtime display number after reconnect. A missing monitor does not silently select a different one. Controls and shortcuts recover automatically when the selected monitor remains available or returns; an explicit profile or display selection can also change the destination. Manual/error pauses are never cleared by this recovery. Availability is checked using display metadata only; no idle full-window scans are added.

Wake/session activation renews shortcuts and refreshes owned panels. A panel whose target visibility remains true is ordered in again if macOS has ordered it out, while existing hide animations retain their deduplication. Logs now distinguish display unavailability, display-transition completion, and actual pauses. The Settings snapshot mirrors transient display availability.

Do not infer native Space membership from an omitted AX window. Public AX discovery is not a native Space identifier API.

## Persistent diagnostics

`DiagnosticLog` writes bounded private JSON-lines history on a serial utility queue, with separate manager/helper files and rotation. Production logging starts in the executable entry point; constructing test models does not enable it. Model notices preserve replaced messages, and error handlers retain typed failures at their catch sites. AX sessions log numeric errors without exporting handles. Operation traces retain caller locations and mark slow transactions, tab selections, and app discovery, including work waiting on other tasks. They do not initiate extra discovery.

Each application delegate owns a `ResponsivenessMonitor`. Its independent utility timer keeps one outstanding main-queue heartbeat, reports a suspected three-second stall and later recovery, and resets samples after long scheduling gaps. It uses cached context and never queries AX. Local log-copy/reveal actions in Settings bypass manager IPC, so they remain available if only the manager stalls. Crash stack capture remains macOS's responsibility.

## Changes that need special care

Keep bundle identities, saved enum values, shortcut action IDs, and decoder defaults stable. Their source of truth and tests are described in [Configuration](CONFIGURATION.md). Use [Testing](TESTING.md) for real-desktop checks and [Signing](../SIGNING.md) when changing packaging.


## Workspace storage and Settings routing

`WorkspaceStore` keeps a validated version-1 `workspaces.json` document with at most 16 unique records and one instance per named profile. It uses the existing bounded private atomic file helper. The first migration copies the legacy session; it never deletes or overwrites `layout.json`. All workspace layouts and names commit through the coordinator into one authoritative manifest, so saving one instance cannot overwrite another. Global preferences remain in their existing store; zone names are restored from each workspace record. Named profile snapshots remain separate from evolving workspace checkpoints.

Settings displays only the selected workspace detail plus a bounded summary list. Commands from the helper carry the snapshot's workspace UUID. The host rejects delayed commands from a previously selected workspace and invalidates its old observation generation when switching models. Standalone test fixtures without a workspace retain the original command encoding.


## Desktop Finder extension

The sandboxed `SpaceTabsFinder` executable supplies only a Desktop-background Finder Sync submenu. It reads a bounded private `DesktopMenuSnapshot` with a dedicated read-only exception; it never performs AX or workspace operations. `DesktopMenuBridge` observes menu-relevant state, deduplicates/coalesces snapshots, and writes off the main actor. The manager handles narrowly typed capability-bearing URLs addressed to its exact bundle, rejects stale desktop epochs/replays, and resolves the display captured when Finder builds the menu. This separate capability channel is not Settings' signature-authenticated IPC. See [Desktop menu](DESKTOP_MENU.md) for the precise boundary and native acceptance steps.
