# Roadmap and public-release preparation

This is a direction, not a release promise. Implemented behavior belongs in the README and architecture guide; proposed work belongs here.

## Before a public release

- Confirm rights to the supplied icons and add any required asset attribution.
- Choose a repository URL and a private channel for security reports.
- Run the prepared CI workflow on the hosted repository.
- Complete the desktop checks on supported macOS versions and representative apps.
- Validate Accessibility access across two builds signed with the same identity.
- Decide how signed/notarized releases and updates will be distributed.
- Add screenshots or a short demo from the tested release.

The source code is licensed under [GNU GPLv3](../LICENSE). Public binary releases still depend on the remaining asset, signing, distribution, and desktop checks. A security contact and release download links still need to be selected.

## Engineering priorities

1. Verify gesture delivery, focus, sleep/wake, display changes, and recovery with real apps.
2. Measure AX wait time and click-to-focus latency before making performance claims.
3. Keep discovery limited and event-driven while isolating slow apps.
4. Improve real-world compatibility, including native tabs, dialogs, and stale AX elements, without private APIs.
5. Extend multi-monitor behavior only after the single-selected-display model is stable.

## Possible later features

- Independent zones on multiple displays at the same time.
- Small window-rule exceptions for floating or auxiliary windows.
- More layouts built from the existing internal split tree.
- Better visual destination feedback for complex tab moves.
- Import/export of validated profiles without scripts or executable callbacks.

Keep the main idea simple: understandable zones with visible tabs. Replacing macOS Spaces, moving inactive windows off screen, and continuous focus enforcement are not current goals.
