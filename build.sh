#!/bin/bash
# Builds Larc.app without Xcode's build system: compiles all Swift sources with
# swiftc for arm64 + x86_64, lipos them together, assembles the .app bundle,
# and ad-hoc codesigns it. Output: build/Larc.app
#
# Prefer `xcodebuild -project larc.xcodeproj -scheme larc -configuration
# Release -derivedDataPath build build` when available; this script exists for
# environments where xcodebuild's log/arena directories are not writable.
# (Note: the Xcode project/scheme are still named "larc" lowercase — only the
# built app itself is branded "Larc".)
set -euo pipefail
cd "$(dirname "$0")"

OUT=build
APP="$OUT/Larc.app"
CACHE="$OUT/module-cache"
DEPLOY=14.0
# Recursive: backends live under larc/Plugins/<Family>/, so a flat glob
# would silently compile only the shared sources and fail on missing types.
SOURCES=($(find larc -name '*.swift' | sort))

mkdir -p "$OUT" "$CACHE"
rm -rf "$APP" "$OUT/larc-arm64" "$OUT/larc-x86_64"

# `./build.sh --dev` compiles the Dev screen in: a gallery of every component
# and icon, for judging the design in one place rather than screen by screen.
# It is a compile flag rather than a runtime setting so a release build cannot
# ship it by accident — no flag, no code.
DEV_FLAGS=()
FAST=0
for arg in "$@"; do
    if [ "$arg" = "--dev" ]; then
        DEV_FLAGS=(-D LARC_DEV)
        echo "Building with the Dev screen (-D LARC_DEV)"
    fi
    if [ "$arg" = "--fast" ]; then
        FAST=1
    fi
done

# `--fast` drops the two things a release needs and a look at the UI doesn't:
# whole-module optimization, and the Intel slice. Measured end to end on an
# M-series host, 23 files / ~7.9k lines:
#
#     ./build.sh            ~25s     -O, arm64 + x86_64
#     ./build.sh --fast      ~6s     -Onone, arm64
#
# Roughly half the saving is the second architecture and half is the optimizer.
#
# `-enable-batch-mode` would compile files in parallel across cores and takes
# the compile itself to ~1s, but it writes per-file objects into a temporary
# directory and the link then can't find them — reproducible here, with no
# compile error to explain it. Not shipped for that reason. If it's ever worth
# chasing, the symptom is "no such file or directory: …/PopoverView-1.o".
#
# **Still signed with `larc-dev`**, so TCC grants survive exactly as for a full
# build; this changes what is compiled, never how it's signed.
#
# Not for anything you intend to keep: no Intel slice, and unoptimized code.
# Use a plain `./build.sh` before judging animation smoothness or handing the
# app to anyone.
OPT=(-O)
ARCHES=(arm64 x86_64)
if [ "$FAST" = "1" ]; then
    OPT=(-Onone)
    ARCHES=(arm64)
    echo "Fast build: arm64 only, unoptimized — for looking at, not for keeping."
fi

# `${arr[@]+"${arr[@]}"}` rather than `"${arr[@]}"`: macOS ships bash 3.2, where
# expanding an *empty* array under `set -u` is an unbound-variable error. So a
# plain `./build.sh` — the common case — failed outright.
common=("${OPT[@]}" -module-cache-path "$CACHE" -module-name larc -parse-as-library
        -warnings-as-errors ${DEV_FLAGS[@]+"${DEV_FLAGS[@]}"}
        -framework AppKit -framework SwiftUI -framework ServiceManagement -framework Carbon)

SLICES=()
for arch in "${ARCHES[@]}"; do
    # Braces required: bash 3.2 reads the multi-byte ellipsis straight after
    # `$arch` as part of the variable's name, and fails as unbound. The literal
    # "Compiling arm64…" this replaced had no variable, so it never showed.
    echo "Compiling ${arch}…"
    swiftc "${common[@]}" -target "$arch-apple-macos$DEPLOY" \
        -o "$OUT/larc-$arch" "${SOURCES[@]}"
    SLICES+=("$OUT/larc-$arch")
done

# `lipo -create` with one input is a copy, so a single-arch build needs no
# special case here.
echo "Assembling binary…"
mkdir -p "$APP/Contents/MacOS"
lipo -create "${SLICES[@]}" -output "$APP/Contents/MacOS/Larc"
rm "${SLICES[@]}"

# This is the SHIP bundle ID and must not change again — macOS keys UserDefaults
# and every TCC grant to it, so changing it silently resets each user's settings
# and permissions. Earlier IDs carried a `.devN` suffix precisely so they could
# be burned: ~15 ad-hoc builds under one ID (each a different cdhash) can leave
# local-network state that accepting the prompt no longer fixes. If that happens
# during development, build under a throwaway `com.studioaiyo.larc.devN` locally
# rather than moving the ship ID. See CLAUDE.md.
echo "Assembling bundle…"
sed -e 's/$(EXECUTABLE_NAME)/Larc/g' \
    -e 's/$(PRODUCT_BUNDLE_IDENTIFIER)/com.studioaiyo.larc/g' \
    -e "s/\$(MACOSX_DEPLOYMENT_TARGET)/$DEPLOY/g" \
    larc/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Bundled files. Only the fallback artwork so far, and this is the first thing
# the bundle has ever carried besides the binary -- so the directory is allowed
# not to exist rather than failing the build.
if [[ -d larc/Resources ]]; then
    mkdir -p "$APP/Contents/Resources"
    cp -R larc/Resources/. "$APP/Contents/Resources/"
fi

# Ad-hoc signatures change every build (cdhash-based), which silently
# invalidates the TCC Accessibility grant on each rebuild. A self-signed
# code-signing certificate named "larc-dev" (create once in Keychain Access →
# Certificate Assistant) gives a stable identity so the grant survives rebuilds.
IDENTITY=""
if [[ "${FORCE_ADHOC:-}" != "1" ]]; then
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/larc-dev/ {print $2; exit}')"
fi
if [[ -n "${IDENTITY:-}" ]]; then
    echo "Codesigning (identity: $IDENTITY)…"
    codesign --force --deep --sign "$IDENTITY" "$APP" || {
        echo "Identity signing failed; falling back to ad-hoc."
        codesign --force --deep --sign - "$APP"
    }
else
    echo "Codesigning (ad-hoc — create a 'larc-dev' cert to keep the Accessibility grant across rebuilds)…"
    codesign --force --deep --sign - "$APP"
fi

echo "Done: $APP"
lipo -info "$APP/Contents/MacOS/Larc"
