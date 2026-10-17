#!/bin/sh
set -eu

REPOSITORY_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ISH_SOURCE="$REPOSITORY_ROOT/Vendor/ish-arm64"
BUILD_ROOT="${FAMILIAR_ISH_BUILD_ROOT:-$REPOSITORY_ROOT/.build/ish}"
PACKAGE_INVENTORY="$BUILD_ROOT/rootfs/alpine-3.24.0-packages.tsv"
PIP_PACKAGE_INVENTORY="$BUILD_ROOT/rootfs/alpine-3.24.0-pip-packages.txt"
FONT_LICENSE="$BUILD_ROOT/rootfs/noto-cjk-OFL.txt"
OUTPUT="$BUILD_ROOT/notices/ThirdPartyNotices-iSH.txt"
INSTALL_OUTPUT="$REPOSITORY_ROOT/Familiar/Resources/ThirdPartyNotices-iSH.txt"

if [ ! -f "$ISH_SOURCE/LICENSE.md" ] || [ ! -f "$ISH_SOURCE/LICENSE.IOS" ]; then
  printf '%s\n' \
    "The iSH submodule is not initialized." \
    "Run: git submodule update --init Vendor/ish-arm64" >&2
  exit 1
fi

if [ ! -f "$PACKAGE_INVENTORY" ]; then
  printf '%s\n' \
    "The Alpine package inventory is missing." \
    "Run Scripts/prepare-ish-rootfs.sh before generating release notices." >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT")"
{
  printf '%s\n\n' \
    "Familiar iSH and Alpine Runtime Notices" \
    "Generated from the pinned source and prepared rootfs. Do not edit by hand."
  printf '%s\n\n' "===== iSH LICENSE DECLARATION ====="
  sed -n '1,240p' "$ISH_SOURCE/LICENSE.md"
  printf '\n%s\n\n' "===== iSH iOS ADDITIONAL TERMS ====="
  sed -n '1,240p' "$ISH_SOURCE/LICENSE.IOS"
  printf '\n%s\n\n' "===== ALPINE INSTALLED PACKAGE INVENTORY ====="
  printf '%s\n' "Package and version<TAB>Declared license"
  sed -n '1,4000p' "$PACKAGE_INVENTORY"
  if [ -f "$PIP_PACKAGE_INVENTORY" ]; then
    printf '\n%s\n\n' "===== PYTHON PACKAGES INSTALLED IN THE GUEST ====="
    sed -n '1,4000p' "$PIP_PACKAGE_INVENTORY"
  fi
  if [ -f "$FONT_LICENSE" ]; then
    printf '\n%s\n\n' "===== NOTO SANS CJK (OFL-1.1) LICENSE AND COPYRIGHT ====="
    sed -n '1,400p' "$FONT_LICENSE"
  fi
} > "$OUTPUT"

if [ "${1:-}" = "--install" ]; then
  cp "$OUTPUT" "$INSTALL_OUTPUT"
fi

printf '%s\n' "$OUTPUT"
