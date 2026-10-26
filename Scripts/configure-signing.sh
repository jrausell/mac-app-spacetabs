#!/bin/zsh
set -eu
cd "${0:A:h:h}"
if [[ $# -ne 1 ]]; then
    print -u2 'Usage: Scripts/configure-signing.sh 40_CHARACTER_SHA1_FINGERPRINT'
    print -u2 'List identities: security find-identity -v -p codesigning'
    exit 2
fi
identity_hash="${1:u}"
if [[ ${#identity_hash} -ne 40 || "$identity_hash" == *[^0-9A-F]* ]]; then
    print -u2 'The identity must be a 40-character hexadecimal SHA-1 fingerprint.'
    exit 2
fi
if ! available_identities="$(/usr/bin/security find-identity -v -p codesigning)"; then
    print -u2 'Could not read keychain identities. Run this command in your Terminal.'
    exit 1
fi
if [[ "$available_identities" != *"$identity_hash"* ]]; then
    print -u2 'That code-signing identity is unavailable. See SIGNING.md.'
    exit 1
fi
umask 077
mkdir -p .local
print -r -- "$identity_hash" > .local/signing-identity
print 'Identity saved in .local/signing-identity. Future builds will use the same certificate.'
print 'Build with Scripts/build-app.sh release, then grant Accessibility access to that copy.'
