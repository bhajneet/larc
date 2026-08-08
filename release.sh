#!/bin/bash
# Builds Larc.app and packages it as a DMG for a GitHub Release.
#
# Must be run from a real Terminal, not an agent sandbox: build.sh falls back to
# ad-hoc signing wherever `security find-identity` can't reach the keychain, and
# a release should carry the same signature every user sees. hdiutil also needs
# to attach a disk image, which sandboxes deny.
#
# Produces build/Larc-<version>.dmg: the app beside a symlink to /Applications,
# in a plain Finder window.
#
# **Deliberately unstyled.** Custom window size, icon size and positions live in
# the volume's .DS_Store, which only Finder writes, which means mounting a
# read-write image, driving Finder over AppleScript, then converting — and it
# only works on HFS+. That was built and abandoned: it needs Automation
# permission, fails differently depending on what is already mounted, and buys a
# nicer window. Not worth the moving parts. If it ever is, the honest route is
# generating .DS_Store directly rather than scripting Finder.
set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(awk '/CFBundleShortVersionString/ {getline; gsub(/.*<string>|<\/string>.*/, ""); print; exit}' larc/Info.plist)
APP="build/Larc.app"
ROOT="build/dmg-root"
DMG="build/Larc-$VERSION.dmg"

# A release built with --dev would ship the component gallery and the fault
# injection. Checked before building, so the mistake costs no time.
if [[ "$*" == *--dev* ]]; then
    echo "Refusing to package a --dev build." >&2
    exit 1
fi

./build.sh "$@"
[[ -d "$APP" ]] || { echo "No app at $APP" >&2; exit 1; }

echo "Verifying signature…"
codesign --verify --deep --strict "$APP" || { echo "Signature verification failed." >&2; exit 1; }

# Captured then matched, NOT piped. Under `set -o pipefail` an awk that exits
# early closes the pipe, the producer takes SIGPIPE, and the assignment fails —
# `set -e` then kills the script with no message. Two v's because `-dv` alone
# does not print Authority lines.
SIGNING=$(codesign -dvv "$APP" 2>&1 || true)
AUTHORITY=$(awk -F= '/^Authority=/ {print $2; exit}' <<<"$SIGNING")
echo "Signed by: ${AUTHORITY:-(ad-hoc — users will see a Gatekeeper warning)}"

# ditto rather than cp: Apple's documented tool for copying bundles, and it
# preserves the symlinks and extended attributes the signature depends on.
echo "Staging…"
rm -rf "$ROOT" "$DMG"
mkdir -p "$ROOT"
ditto "$APP" "$ROOT/Larc.app"
ln -s /Applications "$ROOT/Applications"

# UDZO is compressed and read-only, which is what a distributed image should be.
# No -fs, so hdiutil uses its default of APFS — fine on everything a macOS 14 app
# can reach. (Adding -partitionType or -layout later would mean adding -fs back;
# with either set and no -fs, hdiutil creates no filesystem at all.)
echo "Building image…"
hdiutil create \
    -volname "Larc" \
    -srcfolder "$ROOT" \
    -format UDZO \
    -ov \
    -quiet \
    "$DMG"

rm -rf "$ROOT"

echo "Verifying image…"
hdiutil verify -quiet "$DMG" || { echo "Image verification failed." >&2; exit 1; }

echo
echo "Wrote $DMG ($(du -h "$DMG" | cut -f1))"
echo "SHA-256: $(shasum -a 256 "$DMG" | cut -d' ' -f1)"
echo
echo "Next:"
echo "  gh release create v$VERSION $DMG --title \"Larc $VERSION\" --notes \"…\""
