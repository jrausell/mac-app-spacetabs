#!/bin/zsh
set -eu
cd "${0:A:h:h}"
mkdir -p .build/icons .build/module-cache
icon_workspace="$(mktemp -d "$PWD/.build/icons/generate.XXXXXX")"
trap 'rm -rf "$icon_workspace"' EXIT
swift -module-cache-path "$PWD/.build/module-cache" Scripts/build-icons.swift "$icon_workspace"
for icon_name in SpaceTabs SpaceTabsSettings; do
    cp "$icon_workspace/$icon_name.icns" "$PWD/.build/icons/$icon_name.icns"
done
