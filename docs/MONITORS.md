# Profiles and monitors

SpaceTabs currently manages zones on **one selected display at a time**. You can save different profiles for different screens or display setups, but you cannot run an independent active profile on each monitor simultaneously.

## Put your zones on a second monitor

1. Connect the monitor and open **SpaceTabs Settings → Design → Templates and Sizes**.
2. Select the external screen in **Display**, choose a template, and adjust the proportions.
3. Assign apps and windows to the zones.
4. Open **Profiles**, enter a name such as `External display`, and select **Save Profile**.
5. Open that profile's `…` menu and choose **Use automatically with these displays**.

A profile stores the selected display, layout, proportions, appearance, zone names, tab selections, and app assignments. Saving a profile does not create a second active workspace alongside the first.

## Prepare a layout for working without it

1. Disconnect the external display, or turn it off if macOS then removes it from the display setup.
2. If SpaceTabs pauses, select your remaining display in Design and choose **Resume**.
3. Adjust the layout and assignments for that screen.
4. Save another profile, such as `Single display`.
5. Choose **Use automatically with these displays** for that profile while only the remaining screen is connected.

There is one automatic profile link per display setup. Linking a different profile while the same setup is connected replaces its previous link. Applying a profile manually does not change its saved automatic link.

## What happens when a screen disappears?

SpaceTabs waits briefly for a display change to settle. If the new display setup has a linked profile and management is active with Accessibility access, it applies that profile once pending work finishes. The display-change debounce is about 0.9 seconds; this is not a guarantee that window placement finishes within that time.

If there is no linked profile, SpaceTabs pauses and asks you to check the selected screen and resume. macOS may move windows from a disconnected display onto another screen; SpaceTabs does not control that system behavior. Saved profiles remain on disk.

Turning a monitor off is not always a disconnect. Some monitors, docks, and adapters continue reporting the screen to macOS. If macOS still sees the same display setup, SpaceTabs does not switch profiles just because the panel went dark.

## What happens when it comes back?

When macOS reports the same display setup again, the linked profile can apply automatically. This also applies at startup. The saved windows must still be open and uniquely identifiable. Closed apps are not launched; app assignment rules can take effect when you open them later.

A paused app stays paused. If the earlier disconnect had no linked profile and left SpaceTabs paused, reconnecting a monitor will not automatically clear that pause. Resume management on the intended screen; you can then apply the saved profile manually.

The display-setup key includes screen identity, resolution, and arrangement. Changing scaling, screen positions, or connected screens may require linking a profile to that new setup. Each profile remembers one destination display; if it is unavailable when a profile is applied, placement falls back to the main display.

For reliable switching, save and link a profile for both the connected and disconnected setups, and keep management active. See [Testing](TESTING.md) for the desktop checks and [Configuration](CONFIGURATION.md) for stored data.
