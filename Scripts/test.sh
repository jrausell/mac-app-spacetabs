#!/bin/zsh
set -eu
cd "${0:A:h:h}"
mkdir -p .build/module-cache .build/clang-cache .build/configuration .build/security
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
# Transport identity checks need a signed test executable on Intel and Apple Silicon.
swift test --disable-sandbox --disable-xctest -Xlinker -adhoc_codesign \
    --cache-path "$PWD/.build/cache" --config-path "$PWD/.build/configuration" --security-path "$PWD/.build/security" \
    -Xswiftc -module-cache-path -Xswiftc "$PWD/.build/module-cache"
