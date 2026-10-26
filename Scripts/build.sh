#!/bin/zsh
set -eu
cd "${0:A:h:h}"
configuration="${1:-debug}"
if [[ "$configuration" != debug && "$configuration" != release ]]; then
    print -u2 'Usage: Scripts/build.sh [debug|release]'
    exit 2
fi
mkdir -p .build/module-cache .build/clang-cache .build/configuration .build/security
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
swift build --disable-sandbox -c "$configuration" \
    --cache-path "$PWD/.build/cache" --config-path "$PWD/.build/configuration" --security-path "$PWD/.build/security" \
    -Xswiftc -module-cache-path -Xswiftc "$PWD/.build/module-cache"
