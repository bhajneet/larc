#!/bin/bash
# Builds larc/Resources/Larc.icns from a single square PNG.
#
#   ./make-icon.sh                        rebuild the icon from the defaults below
#   ./make-icon.sh art.png --scale 0.8    override source or geometry
#   ./make-icon.sh --preview              render candidates to tools/icons/ instead
#   ./make-icon.sh --preview --shadow off flags apply to previews too
#
# Run this only when the source artwork changes; the .icns it produces is
# committed, so a normal build never needs it. build.sh copies everything in
# larc/Resources into the bundle, and Info.plist names the icon "Larc".
#
# All the work is in icon/ShapeIcon.swift — see there for why this uses neither
# sips (cannot round corners; stages through a temp dir and exits 0 when that
# fails) nor iconutil (same temp-dir problem, reporting only "Failed to generate
# ICNS" with no cause).
set -euo pipefail
cd "$(dirname "$0")"

# Defaults. --bg fills the rounded body and fits the artwork inside it, which is
# what artwork with alpha wants; without it the source is cropped to fill.
SRC="larc/Resources/larc-logo-transparent.png"
BG="F8F5E9"
SCALE="1.00"
SHADOW="off"
OUT="larc/Resources/Larc.icns"
BIN="build/shape-icon"
PREVIEW=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --preview) PREVIEW=1; shift ;;
        --bg)      BG="$2"; shift 2 ;;
        --scale)   SCALE="$2"; shift 2 ;;
        --shadow)  SHADOW="$2"; shift 2 ;;
        -*)        echo "unknown flag $1" >&2; exit 2 ;;
        *)         SRC="$1"; shift ;;
    esac
done

[[ -f "$SRC" ]] || { echo "No source artwork at $SRC" >&2; exit 1; }

mkdir -p build/module-cache
swiftc -O -module-cache-path build/module-cache -o "$BIN" icon/ShapeIcon.swift

if [[ -n "$PREVIEW" ]]; then
    # tools/ is gitignored, so previews never reach the repo. One directory per
    # scale, each holding every size at true pixel dimensions plus a magnified
    # copy of the small ones.
    for s in 1.00 0.85 0.70 0.60; do
        DIR="tools/icons/scale-${s/./}"
        rm -rf "$DIR"
        "$BIN" "$SRC" ignored.icns --bg "$BG" --scale "$s" --shadow "$SHADOW" --preview "$DIR" >/dev/null
        echo "  $DIR"
    done
    echo
    echo "Open tools/icons in Finder. The plain files are true size; the"
    echo "-magnified ones show the real pixel grid at 16 and 32."
    exit 0
fi

"$BIN" "$SRC" "$OUT" --bg "$BG" --scale "$SCALE" --shadow "$SHADOW"
