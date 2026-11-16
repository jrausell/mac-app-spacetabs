# Persistent profiles across monitors and desktops

Status: Community work in progress, requested on 2026-11-03. The contracts below describe the intended result; the progress note distinguishes implemented work from remaining requirements.

Implementation progress (2026-11-05): the two-monitor desktop anchor probe passed. Unavailable assignments and manual pending-app recovery are implemented. The source now adds a workspace registry, separate models and controls, shared AX/catalog services, ownership reservations, workspace-scoped Settings commands, and explicit opening per monitor/current native desktop. The legacy session is copied into a versioned `workspaces.json` manifest. Later restarts require explicit desktop rebinding. Automated isolation/migration/ownership tests pass; concurrent-monitor and real native-desktop acceptance of the integrated app remain pending. Portrait layouts, zone closure, document-specific recreation, and automatic persistent desktop association remain unfinished.

The historical evidence below describes the baseline that motivated this work. See [Architecture](ARCHITECTURE.md) and [Workspaces and monitors](MONITORS.md) for current behavior.

## Intended experience

Keep a separate workspace open on each connected monitor, and keep different workspaces on different macOS desktops. Each workspace remembers its layout, assigned apps/windows, tab order, and selections even when an app, zone, or whole workspace closes. Opening a workspace prepares its saved assignments and launches missing apps. Restore repairs the workspace on request. Show brings its selected windows forward.

Example: a landscape monitor runs Development, a portrait monitor runs Reference, and another macOS desktop holds Personal. Closing Terminal must not remove Terminal from Development. Restoring Reference must not resize Development's windows.

## Baseline evidence before workspace isolation

- `AppModel` owns one `TabManager`, selected screen, layout, assignments, pending tabs, and restore state. Concurrent workspaces require separating this state by workspace; adding more screen IDs alone is insufficient.
- `WorkspaceProfile` stores a `PersistedLayout`, zone names, and an optional launch preference. Profile application replaces the global layout and can retain unlisted managed windows; it is not an isolated workspace activation.
- `AppModel+DisplayProfiles` links an entire display configuration to one profile. The key includes resolution and arrangement. It does not bind independent workspaces to individual monitors.
- Session checkpoints and named profiles are separate. Named profiles are saved explicitly; a durable assignment model must not depend on the latest live discovery snapshot.
- `openAssignedApps` currently opens only closed app assignments on explicit application, defaults off, and does not recreate a closed window in a running app.
- `LayoutEngine` already uses a split tree, but `LayoutTemplate`, header handles, adaptation, and settings assume the three existing column layouts.
- `PanelController` uses `moveToActiveSpace`. Independent desktop workspaces require changing the lifetime and desktop behavior of these controls.
- `activeSpaceChanged()` deliberately suspends work during the transition without treating the event as a restore command or a native Space identity.

## Behavior contracts

### Persistent assignments

Separate what the user wants in a workspace from which windows currently fulfill it.

| Event | Saved assignment | Runtime effect |
| --- | --- | --- |
| Assign or move a tab | Save its destination and order | Bind the chosen window to that workspace |
| Close an external window or quit its app | Keep it | Mark the assignment unavailable |
| Close a zone or workspace | Keep it, including selections | Remove its controls and stop managing its live windows |
| Remove from profile | Delete only the chosen assignment | Release its bound window |
| Resize an external window manually | Keep the zone's target geometry | Allow the manual size until Restore or explicit layout action |
| Change template or drag a layout divider | Save the accepted layout | Reflow only this workspace |

Use explicit labels for Close, Release, Remove from profile, and Delete profile. A tab close must never silently mean permanent removal. Closing a workspace leaves its external apps running; it does not quit a shared process or close unsaved documents. Closing a zone retains its definition and assignments, marks it inactive, and releases its windows; reopening it restores them. Template changes that remove a zone use an explicit mapping rule, independently of temporary closure.

Active profiles save accepted membership, order, selection, names, appearance, and layout edits automatically. Closing a window, a failed discovery, a desktop transition, or a failed restore must never overwrite the saved intent with an empty list. Save durable assignment changes before reporting success. Batch high-frequency selection changes and flush pending writes on close/quit. Provide Duplicate to create a separate profile from an existing one.

### Open, Show, Restore, Close

| Action | Launch missing apps | Repair size and position | Bring selected tabs forward |
| --- | --- | --- | --- |
| Open profile here | Yes | Yes, when windows become available | Yes, after preparation |
| Show | No | No | Yes |
| Restore | Yes | Yes | Yes, after repair |
| Close workspace | No | Release with original-state recovery | No |

Show presents one selected window per open zone, retaining other selections, and ends in B when B is available. Raising every tab would hide the selected tabs again. Missing selections stay pending; Show reports that Restore is available. Unhiding an app can also expose its other windows because hiding is app-wide; it must not change their assignments or frames.

Restore matches existing windows first, launches each missing app once, waits through bounded app events, fills missing assignments where supported, applies the target layout to every bound tab in the workspace, and finally presents the selected tabs. Repeating Restore must not create duplicate windows. Per-assignment failures remain visible and retryable; one unavailable app must not block all other restoration work. Preserve rollback and release states for partial failures.

Distinguish app assignment from exact document/window assignment. Launching an app is not a guarantee that it creates a window, reopens a document, or restores browser tabs, Terminal commands, or unsaved content. Reopen saved document URLs with public workspace APIs where applicable; validate app identity and use supported app-specific recovery only where necessary. A running app with no suitable window needs a supported reopen/create path or a clear manual step. Never substitute an unrelated browser window solely because the app matches.

Explicit Open and Restore launch missing apps by default for the new model. Migration preserves the old launch preference for legacy Apply actions until the user adopts the new workspace flow. Display reconnect, desktop notification, and background startup do not implicitly launch apps or steal focus. At startup, recover bindings to running windows; show missing assignments and offer Restore. A future restore-on-login setting must be explicit.

### Monitors and ownership

- One independent open workspace per monitor and native desktop context. Different monitors may run different profiles concurrently.
- One profile has one open instance initially; opening it again offers Show or Move here. Duplicate makes an independently editable profile for a second destination.
- Each real external window has exactly one workspace owner. An explicit move transfers ownership transactionally. Broad app rules cannot take windows from another workspace.
- The same app may serve multiple workspaces with distinct windows. Ambiguous new windows stay unassigned until a unique saved document match or explicit choice resolves ownership. A launch request alone is insufficient proof of ownership.
- Route keyboard actions to the workspace owning the focused managed window; otherwise use the pointer's monitor and a confirmed active desktop context. Never fall back to a workspace on another desktop when the destination is unknown.
- Drop targets include workspace and zone identity. Cross-monitor moves change only the source/destination workspaces and retain the existing gesture cancellation contract.
- Bind a monitor using its public display UUID; keep resolution, arrangement, orientation, and usable bounds as geometry. Changing scaling must not create a different profile identity. Mirrored screens count as one logical workspace surface.
- Disconnect suspends only the affected workspace and retains its assignments. macOS may relocate its windows; do not adopt them into another workspace. Reconnect restores controls and offers Restore without clearing a manual pause or pulling windows from an unconfirmed desktop. If the display UUID changes through a dock/adapter, offer explicit reassociation.

## Native macOS desktops: first feasibility gate

Multiple desktop compatibility is a requirement, with a prototype before committing to automatic desktop binding or restoration after reboot.

Apple documents that [activeSpaceDidChangeNotification](https://developer.apple.com/documentation/appkit/nsworkspace/activespacedidchangenotification) carries no `userInfo` dictionary. It announces a change without providing a native desktop identifier. [isOnActiveSpace](https://developer.apple.com/documentation/appkit/nswindow/isonactivespace) and [collectionBehavior](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.property) operate on `NSWindow` objects belonging to our app; they are not an external-window desktop assignment API. [optionOnScreenOnly](https://developer.apple.com/documentation/coregraphics/cgwindowlistoption/optiononscreenonly) filters onscreen windows, which is not a persistent desktop identity either.

Engineering conclusion from these interfaces: they do not establish a supported way to enumerate stable native Space IDs or send arbitrary external windows to a chosen desktop. Do not encode a guessed desktop number or assume an absent AX window was closed. This constraint is separate from sandbox distribution.

Prototype a user-created workspace bound to the current desktop through SpaceTabs-owned panels or a nonactivating anchor window. Explore `isOnActiveSpace` on those retained windows to recognize already visited contexts during the same session. This is an experiment, not a proven persistence mechanism. Do not use the current `moveToActiveSpace` behavior for workspace-bound bars. A hidden anchor's behavior, per-monitor independence, and reopening after restart all need verification.

The prototype must prove:

1. Bars and resize controls remain on their own desktop without activating SpaceTabs or following the user.
2. Switching desktops does not move, resize, raise, relaunch, or forget another desktop's windows.
3. The same monitor can host Development on one desktop and Personal on another, including when one workspace has no live apps left.
4. Separate Spaces per display works with one monitor changing desktops while the other stays unchanged. Test the shared-Spaces setting too.
5. Windows assigned to all desktops do not belong to two workspaces. Native full-screen, Stage Manager, desktop deletion/reordering, app relaunch, and display reconnection do not cause accidental adoption.
6. Restart either restores a verifiably correct association or marks it unconfirmed and asks the user to bind/open it on the intended desktop. Saved assignments survive either outcome.

If these tests cannot be satisfied using public APIs, document the exact failing scenario and retain explicit Open here on the desktop the user selects. Do not present manual binding as completion of automatic multi-desktop support. Full automatic support remains unresolved until demonstrated. Keep public APIs and SIP enabled; no private SkyLight calls, injection, hidden offscreen workspaces, or synthetic Mission Control automation in this plan.

Launching an app already assigned by macOS to another desktop can open there or switch desktops. Opening an existing app does not duplicate its process per workspace. Stop and report an unexpected desktop transition rather than continuing to position windows in the wrong context. The user may need to move a window with Mission Control and rebind it before Restore can finish.

## Menu and Settings

List open workspaces separately from saved profiles, with display name and state. Use a user-defined desktop label unless native identity is verified; do not fabricate Desktop 1/2 numbering.

```text
Open workspaces
  Development — Main display
    Show
    Restore
    Close workspace
  Reference — Portrait display
    Show
    Restore
    Close workspace
  Personal — Main display · Other desktop
    Switch to its desktop to show or restore
Saved profiles
  Open profile here…
  Manage profiles…
```

Enable Show/Restore for confirmed reachable contexts only; a background desktop entry explains how to reach it rather than silently redirecting to the current desktop. Disconnected profiles retain an unavailable-monitor status. Show progress and per-assignment failures. Paused management stays paused until explicit Resume.

Settings gets a workspace selector and per-workspace Apps, Design, and Profiles state. The manager owns all operations; the helper sends typed workspace-scoped commands and receives a workspace list plus selected detail. Bound snapshot sizes to the existing IPC limit rather than broadcasting every app/window detail for every workspace. Add English keys and complete Spanish translations when implementing UI.

## Portrait layouts

These are geometry templates, separate from visual color themes. Defaults divide usable workspace area after menu/Dock margins and divider gaps; fixed tab bars then reserve their own header space.

| Template | Arrangement | Default split |
| --- | --- | --- |
| Two Rows | A above B | 50% / 50% height |
| Split Top Row | A and C side by side above full-width B | Rows 50% / 50%; A/C 50% / 50% width |
| Split Bottom Row | Full-width B above side-by-side A and C | Rows 50% / 50%; A/C 50% / 50% width |

The two split variants provide the requested full row plus divided row without forcing a preferred orientation. B remains the main zone and the final restore focus. Recommend Two Rows for a newly configured portrait display; do not silently rotate or change an existing saved layout.

Extend the split tree with template-aware root and secondary axes. Replace column-specific handle assumptions with axis-aware divider geometry, hit testing, previews, and percentage labels. Adapt navigation using actual zone rectangles. Generalize two-zone adaptation so both Two Columns and Two Rows fold C into A with stable selection/order. Preserve existing enum values, ratios, template defaults, and window recovery behavior. Validate minimum app sizes on narrow portrait halves; report a rejected layout rather than overlapping zones.

## Proposed ownership and persistence

Names below are design suggestions, not existing types.

| Owner/model | Responsibility |
| --- | --- |
| `WorkspaceCoordinator` | Workspace registry, window ownership, focused workspace, shared display/desktop lifecycle |
| `WorkspaceRuntime` | Per-instance tabs, pending slots, geometry, selections, zoom, pause state, revisions, and operation cancellation |
| `ProfileDefinition` | Durable profile ID/name, layout, zone state, ordered assignments, selected slot IDs, and visual preferences |
| `AssignmentSlot` | Stable ID, zone/order, app bundle identity, app/window/document matching policy, and supported reopen intent |
| `WorkspaceBinding` | Profile ID, display UUID, user desktop label, and association confirmation status |
| Shared process services | Existing AX sessions/executors, bounded discovery, app catalog, launch deduplication, IPC, diagnostics |

Keep AX handles in existing per-process sessions. Scope model requests by workspace ID and revision without creating a second AX manager per workspace. A slow process may still delay its own windows on different monitors; preserve bounded discovery and avoid periodic full scans.

Use the existing validated atomic storage helpers. Add a versioned workspace session document and migrate the current layout to one workspace while preserving named profiles. Store durable definitions separately from ephemeral window bindings and recovery states. Preserve ambiguous legacy window assignments as unresolved slots instead of turning them into broad app rules. Reconcile multiple-file writes through an explicit generation/commit protocol or a single authoritative manifest; do not claim several atomic renames form one atomic transaction. Preserve backups and never overwrite unsupported newer schemas.

Save changes only after successful model/layout acceptance. Launch external apps only after the requested workspace is saved and its context is confirmed. An OS launch already dispatched may finish after cancellation; reject late adoption if its workspace generation no longer matches. Maintain original frames for safe Release after partial failures.

## Implementation order and acceptance

| Phase | Deliverable | Acceptance gate |
| --- | --- | --- |
| 0 | Native desktop feasibility prototype | Report every desktop test above, including unsupported cases; no automatic-binding claim before evidence |
| 1 | Durable assignment slots and migration | Close app/window/zone/workspace, restart SpaceTabs, and verify assignments/order/selections remain; explicit removal alone deletes them |
| 2 | Workspace-scoped state and concurrent monitors | Two independent monitors; shared-app window ownership; no cross-workspace focus/geometry changes |
| 3 | Open, Show, Restore and native menus | Missing app launch once; supported missing-window recovery; idempotent Restore; Show preserves geometry; failure/cancellation isolation |
| 4 | Portrait templates and axis-aware controls | 50/50 defaults, both split-row variants, resizing/navigation/migration and minimum-size failures |
| 5 | Validated multi-desktop integration | Per-desktop controls and safe transitions; explicit unconfirmed state after any unresolvable association; requirement remains open for failed cases |

The desktop feasibility result informs the state model early; full integration follows workspace isolation. Portrait geometry can be developed after the data model stabilizes without depending on automatic desktop discovery.

Automated tests should cover intent surviving missing windows, matching ambiguity, ownership conflicts, duplicate launch suppression, stale completion rejection, per-workspace cancellation, corruption/migration, transaction rollback, menu routing, Settings command/snapshot identity, and portrait geometry. Run the repository checks for implementation changes.

Desktop validation must include two physical monitors (one portrait), two desktops, the same app in multiple workspaces, a running app with no windows, unsaved documents, manually hidden/minimized/resized windows, disconnect/reconnect, rotation/scaling, sleep/wake, restart, manual pause, and a failing AX app. Measure responsiveness; passing fake-backend tests does not prove real focus or desktop behavior.

## Completion criteria

The feature is complete only when assignments persist independently of live windows, each workspace can be shown/restored independently, multiple monitors work concurrently, portrait templates behave correctly, and the tested native desktop support and limitations are stated precisely in the README and guides. Community remains GPLv3. No App Store distribution changes are part of this work.

Chrome regression follow-up: rendering every legacy saved window as a separate pending tab exposed historical page/document titles in the desktop bars. Pending presentation now groups by app and zone and suppresses groups already represented by a managed live window. Raw recovery records remain unchanged. Per-process discovery and drag capture also reuse a uniquely identified native window number when its AX wrapper changes; a page/title change must not allocate another workspace tab. Real browser behavior is not proven by the value-policy tests.

Existing-app synchronization follow-up: the pending app action now refreshes and synchronizes a single open unassigned window before considering app launch. Multiple visible native windows require an explicit choice. Public onscreen window identities restrict the selection to the current visible desktop context; other workspace ownership is preserved. The selected window replaces only the clicked legacy saved slot, using its own release frame. Scoped discovery includes saved accessory apps, runtime bundle metadata supplements the app catalog, and per-tab popovers expose choices and errors. Godot/Mail and two-window Chrome behavior still require the maintainer’s desktop check.

Startup geometry follow-up: pending-app recovery and newly launched app placement now include two bounded final frame checks. A late app-owned restore to full-monitor height is corrected to the zone content rectangle, including fixed header clearance. Desktop/layout/selection changes and new mouse/keyboard/scroll input stop further corrections. Original rollback/release frames are retained. Firefox’s native startup behavior remains a desktop validation item.
