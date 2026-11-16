#!/bin/zsh
set -eu
cd "${0:A:h:h}"
mkdir -p .build/module-cache .build/clang-cache .build/configuration .build/security .local/desktop-probe
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
swift_options=(--disable-sandbox --cache-path "$PWD/.build/cache" --config-path "$PWD/.build/configuration" --security-path "$PWD/.build/security")
swift build "${swift_options[@]}" --product DesktopProbe -c debug -Xswiftc -module-cache-path -Xswiftc "$PWD/.build/module-cache"
binary_dir="$(swift build "${swift_options[@]}" -c debug --show-bin-path)"
staging_path="$(mktemp -d "$PWD/.local/desktop-probe/package.XXXXXX")"
app_path="$staging_path/SpaceTabs Desktop Probe.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$binary_dir/DesktopProbe" "$app_path/Contents/MacOS/DesktopProbe"
cp -R "$binary_dir/SpaceTabs_SpaceTabsCore.bundle" "$app_path/Contents/Resources/"
python3 - "$app_path/Contents/Info.plist" "$PWD/.local/desktop-probe/reports" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "wb") as target:
    plistlib.dump({
        "CFBundleExecutable": "DesktopProbe",
        "CFBundleIdentifier": "dev.spacetabs.desktop-probe",
        "CFBundleName": "SpaceTabs Desktop Probe",
        "CFBundlePackageType": "APPL",
        "CFBundleVersion": "1",
        "LSUIElement": True,
        "LSMinimumSystemVersion": "15.0",
        "NSHighResolutionCapable": True,
        "ProbeReportDirectory": sys.argv[2],
    }, target)
PY
# Disposable diagnostic identity; production app signing and dist are untouched.
/usr/bin/codesign --force --sign - "$app_path"
/usr/bin/codesign --verify --strict "$app_path"
print "Desktop probe: $app_path"
print "Reports: $PWD/.local/desktop-probe/reports"
