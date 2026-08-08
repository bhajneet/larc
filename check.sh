#!/bin/bash
# Type-checks every source file WITHOUT producing or re-signing build/Larc.app.
#
# Use this, not ./build.sh, for routine verification during development.
#
# Why: ./build.sh run from inside the Claude sandbox always falls back to ad-hoc
# signing, because `security find-identity` cannot see the keychain from there
# (0 identities). Ad-hoc signatures get a fresh cdhash every build, and macOS
# ties TCC grants — Local Network and Accessibility both — to the cdhash. So
# every rebuild silently revokes permissions the maintainer has already granted, and
# re-granting only lasts until the next build. Repeated rebuilding is what
# broke Local Network on 2026-07-26.
#
# ./build.sh is the maintainer's command, run from a real Terminal where the
# `larc-dev` identity is visible and the signature — and therefore the grants —
# stay stable across rebuilds.
set -euo pipefail
cd "$(dirname "$0")"

DEPLOY=14.0
mkdir -p build/module-cache

# **Both configurations, not just one.** Code that only compiles in one is code
# that breaks in the other without anyone noticing -- and the dev-only surface
# is no longer one screen: the artwork tuning window, its persistence and its
# source writer are all LARC_DEV, so a release build omits more than it keeps
# of that file.
SOURCES=$(find larc -name '*.swift' | sort)

for FLAGS in "-D LARC_DEV" ""; do
    swiftc -typecheck -parse-as-library -warnings-as-errors $FLAGS \
        -module-cache-path build/module-cache \
        -target "arm64-apple-macos$DEPLOY" \
        $SOURCES
done

echo "Type-check passed, dev and release (no bundle written, no signature touched)."
