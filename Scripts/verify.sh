#!/bin/zsh
set -eu
cd "${0:A:h:h}"
Scripts/lint.sh
Scripts/check-docs.py
Scripts/check-localizations.py
Scripts/test.sh
Scripts/build-app.sh release
plutil -lint dist/SpaceTabs.app/Contents/Info.plist
plutil -lint 'dist/SpaceTabs.app/Contents/Helpers/SpaceTabs Settings.app/Contents/Info.plist'
codesign --verify --deep --strict --verbose=2 dist/SpaceTabs.app
dist/SpaceTabs.app/Contents/MacOS/SpaceTabs --diagnostics
