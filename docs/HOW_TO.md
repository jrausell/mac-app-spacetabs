# Workspaces and profiles, visually

Open **Settings → How To**, or the question-mark button in the menu bar, for illustrated examples. The menu bar shows each workspace's layout thumbnail, monitor, and availability, with Show and Restore buttons. The menus below the cards open/create workspaces, open saved profiles, and expose additional actions. Menu previews use current in-memory state; they do not discover or manipulate external windows.

A **workspace** is a working arrangement opened on one physical monitor and one macOS desktop. Its accepted layout and window assignments save automatically. A **profile** is an explicitly saved snapshot of layout, appearance, and assigned windows, used as a starting recipe. Neither contains the other. Saving a profile is optional; a workspace can start empty.

```text
Monitor + macOS desktop
    └── one open workspace
          ├── zone A → window tabs
          ├── zone B → window tabs
          └── zone C → window tabs (split layouts)

Saved profile ── Open here ──> workspace
```

Several workspaces can be saved for the same destination. Only one can be open there at once. Opening another saves/closes the occupant first; its apps remain running. Workspaces on other monitors/desktops stay independent. A particular native app window belongs to only one open workspace.

## One monitor for work

Choose **A/C on the Left**, then assign Notes to A, Terminal to C, and browser/VS Code windows to B. B has two window tabs, with one selected; switching B preserves A and C selections. Each app retains its own window chrome; SpaceTabs' tab strip is a separate control above the real window.

```text
Main monitor · Desktop 1 · Work workspace
┌──────────────────┬────────────────────────┐
│ A: Notes         │ B: Browser | VS Code    │
├──────────────────┤                        │
│ C: Terminal      │ Selected B window       │
└──────────────────┴────────────────────────┘
```

Optionally save this as a profile called Work. Subsequent workspace changes do not overwrite that named snapshot unless explicitly saved/replaced.

## Two monitors

Create a second workspace on the BenQ using **Workspaces → New workspace on …**. It can have a separate saved profile, such as Music & browsing. The Work profile currently does not combine multiple monitors or select a conditional portrait BenQ variant. Use a second Chrome window for the second workspace.

The in-app portrait illustration shows the requested Spotify-above-Chrome arrangement and labels it **planned**. Two-row templates are not yet implemented; the available templates still use columns. See the [implementation plan](WORKSPACE_PROFILES_PLAN.md).

## One monitor, two macOS desktops

Create the desktops in Mission Control. Open Work on Desktop 1, switch to Desktop 2, then create another workspace or open Personal there. Their bars remain on their respective desktops while SpaceTabs runs.

```text
Same physical monitor
Desktop 1 → Work workspace      Desktop 2 → Personal workspace
```

After restarting SpaceTabs, use **Open here** on each intended native desktop. SpaceTabs does not persist native desktop bindings across app restarts or create macOS desktops.

## Rename a setup

In Settings, use the pencil beside the workspace selector to rename that workspace. In Profiles, open a profile’s **… → Rename…** menu. Names are independent, limited to 60 characters, and saved without replacing layouts, assignments, or IDs. A workspace can be renamed while closed or on another desktop; no window activation is needed.

## Quick actions

| Action | Result |
| --- | --- |
| Show | Raise each zone's selected window without resizing it. |
| Restore | Repair assigned window positions/sizes and retry missing assigned apps. |
| Show Tabs | Temporarily reveal the SpaceTabs controls. |
| Open here | Open a saved workspace on the chosen monitor of the current desktop. |
| Close workspace | Save it and release its windows, keeping apps running. |

Show and Restore are available for workspaces on the current desktop. Switch to the appropriate macOS desktop to work with another open workspace. See [Monitors](MONITORS.md) and [Configuration](CONFIGURATION.md) for identity and persistence limits.
