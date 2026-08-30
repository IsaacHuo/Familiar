#!/bin/sh
set -eu

REPOSITORY_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ISH_SOURCE="$REPOSITORY_ROOT/Vendor/ish-arm64"
MANIFEST="$REPOSITORY_ROOT/Vendor/ISHRuntime/manifest.json"
EXPECTED_COMMIT="54ca185b77f170e12fd353fcd7443232f6cb73fd"
EXPECTED_ALPINE_SHA256="4b8cd66a6688b2a87276c39843ed89c3a06d9534fc6a5823c586aff2696c1f2a"
RUNTIME="$REPOSITORY_ROOT/Vendor/ISHRuntime/FamiliarISHRuntime.xcframework"
ROOTFS="$REPOSITORY_ROOT/Familiar/Resources/alpine-3.24.0-aarch64-fakefs.tar.gz"
ROOTFS_DIGEST="$ROOTFS.sha256"

for file in \
  "$REPOSITORY_ROOT/LICENSE" \
  "$REPOSITORY_ROOT/Familiar/Resources/GPL-3.0.txt" \
  "$REPOSITORY_ROOT/Familiar/Resources/ISH_LICENSE_IOS.txt" \
  "$REPOSITORY_ROOT/Familiar/Resources/ISHSourceOffer.txt" \
  "$MANIFEST"; do
  if [ ! -s "$file" ]; then
    printf 'Missing compliance file: %s\n' "$file" >&2
    exit 1
  fi
done

if [ ! -s "$ROOTFS" ] || [ ! -s "$ROOTFS_DIGEST" ]; then
  printf 'The prepared Alpine fakefs archive or digest is missing.\n' >&2
  exit 1
fi

expected_rootfs_digest="$(awk 'NR == 1 { print $1 }' "$ROOTFS_DIGEST")"
actual_rootfs_digest="$(shasum -a 256 "$ROOTFS" | awk '{ print $1 }')"
if [ "$actual_rootfs_digest" != "$expected_rootfs_digest" ]; then
  printf 'The bundled Alpine fakefs archive failed SHA-256 verification.\n' >&2
  exit 1
fi

for library in \
  "$RUNTIME/ios-arm64/libFamiliarISHRuntime.a" \
  "$RUNTIME/ios-arm64-simulator/libFamiliarISHRuntime.a"; do
  if [ ! -s "$library" ]; then
    printf 'Missing iSH runtime slice: %s\n' "$library" >&2
    exit 1
  fi
  if ! lipo -info "$library" | grep -q 'arm64'; then
    printf 'The iSH runtime slice is not arm64: %s\n' "$library" >&2
    exit 1
  fi
done

if ! grep -q 'url = https://github.com/OpenMinis/ish-arm64.git' "$REPOSITORY_ROOT/.gitmodules"; then
  printf 'The iSH submodule URL is not pinned in .gitmodules.\n' >&2
  exit 1
fi

if ! grep -q "\"commit\": \"$EXPECTED_COMMIT\"" "$MANIFEST"; then
  printf 'The iSH manifest commit does not match the approved revision.\n' >&2
  exit 1
fi

if ! grep -q "\"sha256\": \"$EXPECTED_ALPINE_SHA256\"" "$MANIFEST"; then
  printf 'The Alpine manifest digest does not match the approved image.\n' >&2
  exit 1
fi

if [ -e "$ISH_SOURCE/.git" ]; then
  actual_commit="$(git -C "$ISH_SOURCE" rev-parse HEAD)"
  if [ "$actual_commit" != "$EXPECTED_COMMIT" ]; then
    printf 'Expected iSH %s, found %s\n' "$EXPECTED_COMMIT" "$actual_commit" >&2
    exit 1
  fi
else
  printf '%s\n' \
    "Supply-chain metadata is valid; the iSH worktree is not initialized." \
    "Run: git submodule update --init Vendor/ish-arm64"
fi

for script in \
  "$REPOSITORY_ROOT/Scripts/build-ish-xcframework.sh" \
  "$REPOSITORY_ROOT/Scripts/prepare-ish-rootfs.sh" \
  "$REPOSITORY_ROOT/Scripts/generate-ish-notices.sh"; do
  sh -n "$script"
done

printf '%s\n' "iSH supply-chain metadata and script syntax verified."
