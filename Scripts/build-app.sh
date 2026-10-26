#!/bin/zsh
set -eu
cd "${0:A:h:h}"
configuration="${1:-debug}"
if [[ "$configuration" != debug && "$configuration" != release ]]; then
    print -u2 'Usage: Scripts/build-app.sh [debug|release]'
    exit 2
fi
signing_identity="${SPACETABS_SIGN_IDENTITY:-}"
if [[ -z "$signing_identity" && -f .local/signing-identity ]]; then
    IFS= read -r signing_identity < .local/signing-identity
fi
signing_identity="${signing_identity:--}"
if [[ "$signing_identity" == - ]]; then
    print -u2 'Ad hoc signing: each new build may need Accessibility access again. See SIGNING.md.'
    if [[ "${SPACETABS_REQUIRE_STABLE_SIGNING:-0}" == 1 ]]; then
        print -u2 'A stable signing identity is required. Set one with Scripts/configure-signing.sh.'
        exit 1
    fi
fi
mkdir -p .build/module-cache .build/clang-cache .build/configuration .build/security
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
swift_options=(--disable-sandbox --cache-path "$PWD/.build/cache" --config-path "$PWD/.build/configuration" --security-path "$PWD/.build/security")
swift build "${swift_options[@]}" -c "$configuration" -Xswiftc -module-cache-path -Xswiftc "$PWD/.build/module-cache"
binary_dir="$(swift build "${swift_options[@]}" -c "$configuration" --show-bin-path)"
app_path="$PWD/dist/SpaceTabs.app"
mkdir -p "$PWD/dist"
staging_path="$(mktemp -d "$PWD/.build/app-package.XXXXXX")"
staged_app="$staging_path/SpaceTabs.app"
mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources"
cp "$binary_dir/SpaceTabs" "$staged_app/Contents/MacOS/SpaceTabs"
# Each process must carry the shared SwiftPM localization bundle. The generated
# Bundle.module accessor otherwise falls back to a developer's build path.
resource_bundle="$binary_dir/SpaceTabs_SpaceTabsCore.bundle"
if [[ ! -d "$resource_bundle" ]]; then
    print -u2 'Missing localization resources. The previous app was not replaced.'
    exit 1
fi
cp -R "$resource_bundle" "$staged_app/Contents/Resources/"
cp Resources/Info.plist "$staged_app/Contents/Info.plist"
Scripts/build-icon.sh
cp .build/icons/SpaceTabs.icns "$staged_app/Contents/Resources/SpaceTabs.icns"
signing_mode=identity
if [[ "$signing_identity" == - ]]; then signing_mode=ad-hoc; fi
/usr/libexec/PlistBuddy -c "Add :SpaceTabsSigningMode string $signing_mode" "$staged_app/Contents/Info.plist"
helper_name="$(/usr/libexec/PlistBuddy -c 'Print CFBundleName' Resources/Settings-Info.plist)"
helper_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' Resources/Settings-Info.plist)"
main_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' Resources/Info.plist)"
helper_app="$staged_app/Contents/Helpers/$helper_name.app"
mkdir -p "$helper_app/Contents/MacOS" "$helper_app/Contents/Resources"
cp "$binary_dir/SpaceTabs" "$helper_app/Contents/MacOS/SpaceTabs"
cp -R "$resource_bundle" "$helper_app/Contents/Resources/"
cp Resources/Settings-Info.plist "$helper_app/Contents/Info.plist"
cp .build/icons/SpaceTabsSettings.icns "$helper_app/Contents/Resources/SpaceTabsSettings.icns"
if ! /usr/bin/codesign --force --sign "$signing_identity" --identifier "$helper_bundle_id" "$helper_app"; then
    print -u2 'Could not sign SpaceTabs Settings. Run Scripts/build-app.sh release in your Terminal.'
    print -u2 'dist/SpaceTabs.app still contains the previous version.'
    exit 1
fi
/usr/bin/codesign --verify --strict "$helper_app"
if ! /usr/bin/codesign --force --sign "$signing_identity" --identifier "$main_bundle_id" "$staged_app"; then
    print -u2 'The build finished, but signing with the configured identity failed.'
    print -u2 'Run Scripts/build-app.sh release in your Terminal to access the keychain.'
    print -u2 'dist/SpaceTabs.app still contains the previous version, without these changes.'
    exit 1
fi
/usr/bin/codesign --verify --strict "$staged_app"
# Do not truncate an executable that the user may still have running.
# Keep its old inode/package in .build until the process has exited.
if [[ -e "$app_path" ]]; then mv "$app_path" "$staging_path/previous.app"; fi
if ! mv "$staged_app" "$app_path"; then
    if [[ -e "$staging_path/previous.app" ]]; then mv "$staging_path/previous.app" "$app_path"; fi
    exit 1
fi
/usr/bin/codesign --verify --strict "$app_path"
app_version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app_path/Contents/Info.plist")"
print "SpaceTabs $app_version · App: $app_path"
