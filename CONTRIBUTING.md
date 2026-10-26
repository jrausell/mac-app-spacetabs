# Contributing

SpaceTabs is being prepared for public release. The code, documentation, and translation keys use plain English; the app includes English and Spanish. See [Localization](docs/LOCALIZATION.md) before changing app text. A license has not yet been selected; release preparation does not itself grant an open-source license.

## Discuss before opening a pull request

SpaceTabs is maintainer-led. **Every pull request needs explicit maintainer agreement on the problem and scope before implementation.** This includes bug fixes, documentation, and AI-assisted changes. Opening an issue, receiving an automated reply, or finding an unassigned issue does not count as approval. There are no reserved tasks until the maintainer agrees.

1. Search existing issues and read the relevant documentation.
2. For a bug, provide a reproducible report. For a proposed change, explain the user problem, the smallest useful solution, and how you would verify it.
3. Wait for explicit maintainer agreement before starting an upstream contribution.
4. Keep the resulting PR within that scope and link to the agreement.

Unsolicited PRs may be closed without review. Cosmetic-only edits, typo sweeps, speculative cleanup, dependency churn without a concrete need, and bulk generated fixes are not accepted by default. Do not split trivial changes across multiple PRs or submit work mainly to collect a contribution credit.

Useful comments add evidence, reproduction details, or relevant tradeoffs. Use reactions to express support; avoid repeated requests, duplicate reports, promotional comments, or messages that only ask for credit. Disruptive or off-topic comments may be hidden or removed. No review timeline or merge is promised.

The maintainer decides project direction and upstream inclusion. An accepted contribution does not grant collaborator access or a maintainer role. Licensing and the right to fork are separate from this contribution process; follow the repository's license once one is selected.

## Set up

Use macOS 15 or later and Xcode with Swift 6. See [Development](docs/DEVELOPMENT.md) for the reference toolchain and commands. No third-party Swift packages are needed.

Read [AGENTS.md](AGENTS.md) and the [architecture guide](docs/ARCHITECTURE.md) before editing. These instructions also work for Codex, Claude, and other coding agents that can read repository files.

## Make a focused change

Describe a concrete problem and the behavior you want. Keep unrelated formatting, feature work, and window-management changes separate where practical.

Put platform-independent policies and data models in `SpaceTabsCore`. Keep AppKit, SwiftUI, AX handles, and operating-system integration in `SpaceTabs`. Avoid abstractions that have no current caller or test need.

Keep configuration compatibility and both app processes in mind. Updating a Settings view alone is often not enough; a setting may need a command, manager validation, persistence, and a mirrored state field.

## Validate

```sh
Scripts/format.sh
Scripts/lint.sh
Scripts/check-docs.py
Scripts/check-localizations.py
Scripts/test.sh
Scripts/build.sh release
```

Use `SPACETABS_TEST_LOCAL_LISTENER=1 Scripts/test.sh` in a normal environment to include the local-listener test. See [Testing](docs/TESTING.md) for desktop checks. Do not add Accessibility permission changes or login-item registration to automated tests.

For app testing, build the package with `Scripts/build-app.sh release`. Use your own signing identity as described in [Signing](SIGNING.md). Do not commit local certificates or fingerprints.

## Explain the result

A pull request should explain the problem, resulting behavior, and relevant validation. For window behavior, include the macOS version, apps, display setup, and steps used. Report skipped or unavailable checks directly.

AI-assisted changes have the same requirements. Review generated code, inspect the diff, and verify claims about APIs or test results. Do not submit unreviewed generated changes or an agent's internal transcript as documentation.

## Report a bug

Include a small set of reproduction steps, the expected result, the observed result, and the relevant environment. Use Settings → Diagnostics → Copy Full Diagnostics when useful. Remove personal paths, window titles, and document names before posting.

Do not publish a live socket path, certificate material, credentials, or the contents of your user configuration without reviewing them. No dedicated security contact has been set up yet.
