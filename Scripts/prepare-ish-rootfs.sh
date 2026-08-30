#!/bin/sh
set -eu

REPOSITORY_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ISH_SOURCE="$REPOSITORY_ROOT/Vendor/ish-arm64"
BUILD_ROOT="${FAMILIAR_ISH_BUILD_ROOT:-$REPOSITORY_ROOT/.build/ish}"
DOWNLOAD_ROOT="$BUILD_ROOT/downloads"
ROOTFS_ROOT="$BUILD_ROOT/rootfs"
ALPINE_VERSION="3.24.0"
ALPINE_ARCH="aarch64"
ALPINE_FILE="alpine-minirootfs-$ALPINE_VERSION-$ALPINE_ARCH.tar.gz"
ALPINE_URL="https://dl-cdn.alpinelinux.org/alpine/v3.24/releases/aarch64/$ALPINE_FILE"
ALPINE_SIGNATURE_URL="$ALPINE_URL.asc"
ALPINE_KEY_URL="https://alpinelinux.org/keys/ncopa.asc"
ALPINE_KEY_FINGERPRINT="0482D84022F52DF1C4E7CD43293ACD0907D9495A"
ALPINE_SHA256="4b8cd66a6688b2a87276c39843ed89c3a06d9534fc6a5823c586aff2696c1f2a"
BASE_ARCHIVE="$DOWNLOAD_ROOT/$ALPINE_FILE"
BASE_SIGNATURE="$BASE_ARCHIVE.asc"
FAKEFS_DIRECTORY="$ROOTFS_ROOT/alpine-$ALPINE_VERSION-$ALPINE_ARCH-fakefs"
STAGING_DIRECTORY="$ROOTFS_ROOT/alpine-$ALPINE_VERSION-$ALPINE_ARCH-staging"
STAGING_ARCHIVE="$ROOTFS_ROOT/alpine-$ALPINE_VERSION-$ALPINE_ARCH-staging.tar.gz"
OUTPUT_ARCHIVE="$ROOTFS_ROOT/alpine-$ALPINE_VERSION-$ALPINE_ARCH-fakefs.tar.gz"
INSTALL_ARCHIVE="$REPOSITORY_ROOT/Familiar/Resources/alpine-$ALPINE_VERSION-$ALPINE_ARCH-fakefs.tar.gz"
PACKAGE_INVENTORY="$ROOTFS_ROOT/alpine-$ALPINE_VERSION-packages.tsv"
ISH_BUILDER="${FAMILIAR_ISH_ROOTFS_BUILDER:-$ISH_SOURCE/build-arm64-release/ish}"
FAKEFSIFY="${FAMILIAR_ISH_FAKEFSIFY:-$ISH_SOURCE/build-arm64-release/tools/fakefsify}"
PACKAGES="ca-certificates coreutils findutils gawk git grep jq py3-pip python3 sed unzip zip"

print_config() {
  printf '%s\n' \
    "Alpine source: $ALPINE_URL" \
    "Alpine SHA-256: $ALPINE_SHA256" \
    "Alpine signer: $ALPINE_KEY_FINGERPRINT" \
    "Packages: $PACKAGES" \
    "iSH builder: $ISH_BUILDER" \
    "fakefsify: $FAKEFSIFY" \
    "Output: $OUTPUT_ARCHIVE" \
    "Package inventory: $PACKAGE_INVENTORY"
}

if [ "${1:-}" = "--print-config" ]; then
  print_config
  exit 0
fi

for command_name in curl gpg shasum tar; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$command_name" >&2
    exit 1
  fi
done

if [ ! -x "$ISH_BUILDER" ] || [ ! -x "$FAKEFSIFY" ]; then
  printf '%s\n' \
    "The ARM64 iSH command-line builder is required to install aarch64 packages." \
    "Build it first with:" \
    "  meson setup Vendor/ish-arm64/build-arm64-release Vendor/ish-arm64 -Dguest_arch=arm64 --buildtype=release" \
    "  ninja -C Vendor/ish-arm64/build-arm64-release" >&2
  exit 1
fi

mkdir -p "$DOWNLOAD_ROOT" "$ROOTFS_ROOT"

curl --fail --location --retry 4 --retry-all-errors "$ALPINE_URL" -o "$BASE_ARCHIVE"
curl --fail --location --retry 4 --retry-all-errors "$ALPINE_SIGNATURE_URL" -o "$BASE_SIGNATURE"

actual_sha256="$(shasum -a 256 "$BASE_ARCHIVE" | awk '{print $1}')"
if [ "$actual_sha256" != "$ALPINE_SHA256" ]; then
  printf 'Alpine SHA-256 mismatch: expected %s, found %s\n' "$ALPINE_SHA256" "$actual_sha256" >&2
  exit 1
fi

gnupg_home="$(mktemp -d "${TMPDIR:-/tmp}/familiar-alpine-gpg.XXXXXX")"
cleanup_gnupg() {
  rm -rf "$gnupg_home"
}
trap cleanup_gnupg EXIT HUP INT TERM

curl --fail --location --retry 4 --retry-all-errors "$ALPINE_KEY_URL" | \
  gpg --homedir "$gnupg_home" --batch --import >/dev/null 2>&1
if ! gpg --homedir "$gnupg_home" --batch --with-colons --fingerprint | \
  grep -q "^fpr:::::::::$ALPINE_KEY_FINGERPRINT:"; then
  printf 'Unexpected Alpine signing-key fingerprint.\n' >&2
  exit 1
fi
gpg --homedir "$gnupg_home" --batch --verify "$BASE_SIGNATURE" "$BASE_ARCHIVE"

rm -rf "$FAKEFS_DIRECTORY" "$STAGING_DIRECTORY" "$STAGING_ARCHIVE" "$OUTPUT_ARCHIVE" "$PACKAGE_INVENTORY"
mkdir -p "$STAGING_DIRECTORY"
tar -xzf "$BASE_ARCHIVE" -C "$STAGING_DIRECTORY"

"$ISH_BUILDER" -r "$STAGING_DIRECTORY" /bin/sh -lc \
  "printf '%s\\n' 'https://dl-cdn.alpinelinux.org/alpine/v3.24/main' 'https://dl-cdn.alpinelinux.org/alpine/v3.24/community' > /etc/apk/repositories && apk update && apk add --no-cache $PACKAGES && update-ca-certificates"

"$ISH_BUILDER" -r "$STAGING_DIRECTORY" /bin/sh -lc \
  'awk '\''BEGIN { RS=""; FS="\n" } { name=""; version=""; license=""; for (i=1; i<=NF; i++) { if ($i ~ /^P:/) name=substr($i,3); else if ($i ~ /^V:/) version=substr($i,3); else if ($i ~ /^L:/) license=substr($i,3) } if (name != "") printf "%s\t%s\t%s\n", name, version, license }'\'' /lib/apk/db/installed | sort' \
  > "$PACKAGE_INVENTORY"

COPYFILE_DISABLE=1 tar --format ustar -czf "$STAGING_ARCHIVE" -C "$STAGING_DIRECTORY" .
LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 "$FAKEFSIFY" "$STAGING_ARCHIVE" "$FAKEFS_DIRECTORY"
COPYFILE_DISABLE=1 tar -czf "$OUTPUT_ARCHIVE" -C "$FAKEFS_DIRECTORY" .
shasum -a 256 "$OUTPUT_ARCHIVE" > "$OUTPUT_ARCHIVE.sha256"

if [ "${1:-}" = "--install" ]; then
  cp "$OUTPUT_ARCHIVE" "$INSTALL_ARCHIVE"
  cp "$OUTPUT_ARCHIVE.sha256" "$INSTALL_ARCHIVE.sha256"
fi

print_config
