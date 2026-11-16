# Workspaces, profiles, and monitors

The current source has an experimental workspace coordinator. Each open workspace has its own tabs, pending assignments, layout, names, appearance, pause state, and controls. It shares the Accessibility service and app catalog with the other workspaces. Native desktop and multiple-monitor interaction still require the acceptance checks in [Testing](TESTING.md).

## Create a workspace on another monitor or desktop

1. Switch to the macOS desktop where you want to work.
2. Choose **SpaceTabs → Workspaces → New workspace on [display]…**. Choose the second monitor to create independent zones there. The same actions are available above the Settings pages.
3. Assign windows in Apps and choose a layout in Design. The Settings workspace picker selects whose assignments you are editing.
4. Save a named profile if desired. The workspace's accepted assignments and layout changes are checkpointed automatically, including unavailable app/window slots.

There is one open workspace per monitor on each visible native desktop. Creating or opening another workspace at an occupied destination closes and saves the previous workspace first, releasing its windows without quitting their apps. The old workspace remains in the Workspaces menu. Other monitors and other desktops keep their own workspaces.

A new workspace starts empty. Saving two legacy profiles of the same windows does not invent two independent copies of those windows. A real native window can belong to only one open workspace. Assign separate windows when using the same app in several workspaces. Broad app rules claim eligible unowned windows on their own monitor; individual assignments give more control with browsers.

## Profiles and saved workspace state

Profiles are reusable named snapshots. **Open profile here** creates or opens that profile's own workspace, with its own saved slots, rather than merging all the current tabs into another layout. Once a workspace exists for a profile, subsequent opens use its latest checkpointed state. Saving a new profile associates that workspace with the new name; the previous profile remains a snapshot.

Closing an external app/window preserves its slot. Use its Pending card to synchronize an existing window or reopen its app. Ambiguous choices, such as two unassigned Chrome windows, require selecting the intended window. Explicit removal forgets the saved assignment. Browser pages and unsaved documents are not recreated.

## Show, Restore, and Close

The Workspaces menu lists the display and whether each workspace is on the current desktop, another desktop, or closed.

- **Show** raises the selected tab in each zone, ending in B, without resizing windows.
- **Restore** reapplies the workspace's geometry and retries its pending apps. A pending app with several candidate windows presents a choice. App startup is bounded; failures remain available on Pending cards.
- **Close workspace** saves its slots and releases its windows. It leaves the external apps running.
- **Open here on [display]** binds a closed workspace to the selected monitor on the current native desktop. Explicit opening also attempts pending app recovery. The legacy profile checkbox still controls launching broad app assignments that have no saved window slot.

Show and Restore are available only on the workspace's current desktop. Opening a profile already open elsewhere selects its existing workspace; switch to that desktop to use it. SpaceTabs does not silently move another desktop's windows here.

## Restarting SpaceTabs

The first migration copies the legacy session into a Main workspace without deleting `layout.json` or named profiles. The authoritative workspace state is then `workspaces.json`.

After a later SpaceTabs restart, saved workspaces start closed and unconfirmed. Switch to each intended native desktop and choose **Workspaces → [name] → Open here on [display]**. macOS exposes no public stable desktop ID that SpaceTabs can persist between runs. During one app session, retained ordered-out anchor windows track desktop membership using public AppKit APIs, following the [desktop probe](DESKTOP_PROBE.md).

Tab bars use managed native windows and stay with their workspace's desktop. They do not follow the active desktop. There is no private Space enumeration, native-desktop creation, or automated Mission Control movement.

## Display changes and wake

A missing display temporarily suspends its workspace without clearing a manual pause or redirecting it onto another monitor. Display identity uses the physical display UUID; changing runtime display numbers does not select an unrelated screen. Wake renews shortcuts; display and desktop transitions debounce before controls resume. Neither event launches closed apps or automatically raises their windows.

macOS may relocate windows when a monitor disconnects. Reconnect, sleep, full-screen transitions, and changes to “Displays have separate Spaces” need real desktop validation. Legacy display-setup profile links remain stored but do not automatically replace workspace instances. Use explicit workspace opening while this behavior is validated. The display picker is fixed for a workspace; create or open it on the intended monitor instead.

Workspace storage is bounded to 16 records. The remaining product work, including portrait templates, is tracked in the [workspace plan](WORKSPACE_PROFILES_PLAN.md).
