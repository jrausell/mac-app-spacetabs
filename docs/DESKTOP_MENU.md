# Desktop right-click menu

The packaged app now includes **SpaceTabs Desktop Menu**, a sandboxed Finder Sync extension. Its integrated native desktop behavior is experimental until the checks below pass on the maintainer's Mac.

## Confirmed iCloud limitation

On the maintainer's macOS 15.7.7 setup, Desktop metadata reports `isUbiquitousItem = true` and the public File Provider lookup returns an item and domain. An automated AX test opened the real Desktop context menu and confirmed that SpaceTabs was absent; the enabled extension received no menu callback. Restarting Finder and widening registration to the enclosing home folder did not resolve this. The widened registration was removed.

This matches the [Finder Sync limitation documented by GitFinder's developer](https://gitfinder.com/support) for locations managed by file providers. The contextual menu is **not working on this iCloud Desktop**. Do not present extension enablement, signature verification, or successful startup as proof that it works there. A local-folder comparison was inconclusive because another window obscured the test window; it does not establish local Desktop acceptance.

Settings now reports an iCloud-managed Desktop, when the public metadata is available, and points to **SpaceTabs → Workspaces** for Open here, Show, and Restore. An unknown metadata result is retained as unknown. No cloud sync setting, account, file-provider domain, or Desktop content is changed. Enabling/disabling the extension remains under the user's control. Desktop sync status is checked off the main actor at startup and when Settings opens; it is mirrored over Settings IPC and is not persisted.

## Enable and use

1. Quit the previous SpaceTabs process and open the newly packaged `dist/SpaceTabs.app`.
2. Choose **SpaceTabs → Manage Desktop Menu…**, or the matching button in Settings → General.
3. Enable **SpaceTabs Desktop Menu** in the macOS Finder extensions interface.
4. Right-click an empty area of your desktop and choose **SpaceTabs**.

The submenu offers:

- **Open here…**: a new workspace, saved workspaces, and profiles that do not already have a workspace instance.
- **Show**: bring forward this monitor's current workspace selections.
- **Restore**: repair the current workspace on this monitor.
- **Show Tabs**: reveal its tab bars.
- **Windows and Settings…**: open SpaceTabs Settings, including when the manager is not running.

The monitor is captured when the contextual menu is built, so moving through a submenu on another monitor does not change the destination. Workspace actions require SpaceTabs to be running and the desktop transition to have settled. Entries for a workspace on another desktop are unavailable; native desktop movement remains manual. The extension only supplies the desktop's background menu, not file menus, nested folder backgrounds, or menus belonging to other apps.

macOS owns extension registration and user approval. If a development build is not listed, install the containing app in Applications, open it, and revisit Finder extensions. After rebuilding an enabled extension, disable/re-enable it to reload its executable. No Finder restart, TCC reset, or signing identity change is performed by SpaceTabs.

## Boundaries and transport

`Sources/SpaceTabsFinder` is a separate executable using the standard `NSExtensionMain` entry point and `FIFinderSync` principal class. Packaging embeds it in `Contents/PlugIns/SpaceTabs Desktop Menu.appex`, carries its localization bundle, signs it before the containing app, and preserves the previous app if any signature step fails.

The extension watches only the Desktop URL for menu presentation. It does not enumerate, modify, or synchronize Desktop contents. All AX operations and workspace changes remain in the manager. Its sandbox has one read-only home-relative exception, `/Library/Application Support/SpaceTabs/Finder/`, containing `menu.json`; it has no write exception, Accessibility integration, or network entitlement. The manager's existing sandbox/signing behavior is unchanged.

The manager publishes a validated snapshot of profile/workspace names, display bindings, availability, language, manager PID/launch date, and a private random per-run capability/context. It contains no window titles, document URLs, app paths, or executable configuration. Publication is deduplicated, debounced by 80 ms, and serialized on a utility queue. The file is private and atomically replaced using `LocalConfigurationFile`, with a 64 KiB snapshot bound and bounded record counts. The sandboxed extension obtains the actual home with public `getpwuid_r`, rather than confusing its container home with the user's home.

Actions go to the exact containing app through a registered `spacetabs` URL scheme using a narrow typed request. The manager validates the URL structure, capability, desktop/display context, connected physical display, a 30-second freshness window, and one-use request nonces. Space/display changes rotate the context; old menu commands cannot act on the newly active desktop. Invalid commands never dispatch workspace work. A bounded replay cache rejects further requests instead of evicting unexpired nonces. URLs/capabilities are never written to diagnostic logs. The Settings-only URL opens UI and cannot execute workspace commands.

This capability channel protects against arbitrary web links; it is not the exact-signature peer authentication used by Settings IPC. Another process running as the same user and able to read the private snapshot can obtain its capability. Never expand this route into a general configuration or execution API.

## Verification

Automated tests cover synchronous callbacks arriving both on main and worker threads, canonical Desktop matching across URL directory hints/symlinks, request parsing/bounds, forged/expired/replayed requests, context rotation, replay-cache saturation, unique current-display resolution, snapshot storage/validation, paused/unready dispatch, stable plist identities and versions, URL scheme registration, and the read-only sandbox entitlement. Compilation and signature verification do not demonstrate that Finder presents or delivers the menu correctly.

Desktop acceptance:

1. Enable the extension and right-click blank Desktop background. Confirm the SpaceTabs submenu appears, including with Desktop icons hidden if you use that setting.
2. Check that file right-clicks and ordinary Finder folders do not receive the submenu.
3. Right-click on each monitor, choose New workspace, and confirm the chosen monitor receives it. Move the cursor onto another monitor while navigating the submenu and repeat.
4. Open a menu, switch native desktop before choosing an action, and verify the old action performs no workspace work. Reopen the menu on the new desktop.
5. Use Open here, Show, and Restore; check that only the intended current monitor/workspace changes and Show ends in B.
6. Quit SpaceTabs; the menu should retain only Windows and Settings. Relaunch, then reopen the desktop menu before choosing a workspace action.
7. Verify English/Spanish, iCloud Desktop if enabled, wake/reconnect, and permission-denied behavior. Record any missing extension registration or menu delivery separately from AX placement failures.

## Apple references

The integration uses [Finder Sync](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Finder.html), its [extension management interface](https://developer.apple.com/documentation/findersync/fifindersynccontroller/showextensionmanagementinterface()), and the documented [read-only home-relative sandbox exception](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/AppSandboxTemporaryExceptionEntitlements.html). Finder Sync is designed for file synchronization UI; this Community extension's desktop-menu use needs explicit native testing and does not establish App Store suitability.


## Finder worker callback recovery (build 37)

The first activated build trapped because Finder invoked a callback on its XPC worker while the extension assumed the main actor. A native log recorded a libdispatch main-queue assertion after Desktop registration. Finder callbacks now capture request-local target/selection data on their incoming thread and synchronously bridge AppKit work through `MainThreadCallback`, with a fast path for calls already on main. Observation and menu action entry points use the same bridge. Menu transport carries standard integer tags; Swift request values remain in a bounded map inside the extension. Canonical path-component comparison avoids rejecting Desktop URLs with different trailing directory hints. Diagnostic notices record only callback kinds, counts, and booleans, never capability URLs or filenames.

Native follow-up on macOS 15: build 37 was registered and Finder launched the extension successfully. Its notice log confirmed `Finder began observing a directory; desktop=true` without the earlier main-queue assertion. This establishes successful loading and the background observation callback; the later real right-click test above confirmed that the menu is suppressed on this iCloud Desktop.
