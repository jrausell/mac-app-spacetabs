# Related projects and design research

This note records the design review from October 2026. It is not a benchmark or a promise that another project's current implementation is compatible with SpaceTabs.

| Project | Useful concept | Relevance |
| --- | --- | --- |
| [Display Maid](https://funk-isoft.com/display-maid.html) | Profiles and window restoration linked to display setups. | Automatic profile selection when displays reconnect. |
| [AeroSpace](https://github.com/nikitabobko/AeroSpace) | Split trees, directional navigation, accordion groups, and explicit workspace state. | A clear layout model and keyboard navigation. |
| [Amethyst](https://github.com/ianyh/Amethyst) | Layout choices, floating windows, and separate window/focus coordination. | Better handling of dialogs, transitions, and per-display work. |
| [rift](https://github.com/acsandmann/rift) | Another macOS tiling-window-manager design. | A reference for future comparisons of interaction and window-management tradeoffs. |
| [yabai](https://github.com/koekeishiya/yabai) | Binary-space-partitioning layouts on macOS. | A reference for layout behavior; review API and permission requirements before considering any implementation approach. |
| [XMonad](https://xmonad.org/) | Composable layouts and tabbed sublayouts. | Independent groups of tabs inside a larger layout. |

Tabbed groups have precedents. XMonad provides [Tabbed](https://hackage.haskell.org/package/xmonad-contrib/docs/XMonad-Layout-Tabbed.html) and [SubLayouts](https://hackage.haskell.org/package/xmonad-contrib/docs/XMonad-Layout-SubLayouts.html). SpaceTabs aims to make this kind of interaction accessible in a native, visually configured Mac app.

AeroSpace's documented workspace model differs from native Spaces: inactive windows are moved outside the visible area. Its README also declares use of a private window-ID API. Keeping SIP enabled does not by itself mean an implementation uses only public APIs. Do not adopt a different window manager's backend without reviewing these differences against SpaceTabs' requirements.

The [AeroSpace performance discussion](https://github.com/nikitabobko/AeroSpace/discussions/655) illustrates why synchronous AX calls and event bursts need careful scheduling. SpaceTabs now separates AX sessions by process, limits discovery concurrency, and records bounded timing samples. These are architecture changes, not measured proof that SpaceTabs is faster than another app.

Amethyst's [window manager](https://github.com/ianyh/Amethyst/blob/development/Amethyst/Managers/WindowManager.swift) and [screen manager](https://github.com/ianyh/Amethyst/blob/development/Amethyst/Managers/ScreenManager.swift) are useful references for state ownership and recovery. Audit platform dependencies before reusing code; API and license requirements are separate questions.

The review led to profiles by display setup, a quick switcher, temporary zoom, tab dragging, directional navigation, and a split-tree model. Their current behavior and limitations are documented in [Architecture](ARCHITECTURE.md), not in this historical note.
