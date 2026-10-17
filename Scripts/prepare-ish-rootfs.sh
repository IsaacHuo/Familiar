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
ALPINE_MIRROR="${FAMILIAR_ALPINE_MIRROR:-https://dl-cdn.alpinelinux.org}"
# The guest only follows 127.0.0.1 by default, which breaks behind a fake-IP
# proxy. Set FAMILIAR_GUEST_DNS to public resolvers for the build; the original
# resolv.conf is restored before packaging.
GUEST_DNS="${FAMILIAR_GUEST_DNS:-}"
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
APK_PACKAGES="ca-certificates coreutils findutils gawk git grep jq py3-pip python3 sed unzip zip py3-lxml py3-pillow"
PIP_PACKAGES="python-docx openpyxl python-pptx fpdf2 pypdf markdown et-xmlfile XlsxWriter typing-extensions defusedxml fonttools"
PIP_INDEX_URL="${FAMILIAR_PIP_INDEX_URL:-https://pypi.org/simple}"
PIP_FREEZE="$ROOTFS_ROOT/alpine-3.24.0-pip-packages.txt"
NOTO_APK_URL="${FAMILIAR_NOTO_APK_URL:-https://dl-cdn.alpinelinux.org/alpine/v3.24/community/aarch64/font-noto-cjk-0_git20220127-r1.apk}"
NOTO_APK_SHA256="734d8e63fabc307b05ca13ada9a379d0cd72d249f9b53dba5a967d6f32362886"
NOTO_APK="$DOWNLOAD_ROOT/font-noto-cjk.apk"
NOTO_EXTRACT="$ROOTFS_ROOT/font-noto-cjk-apk"
NOTO_OFL_TEMPLATE="$ROOTFS_ROOT/ofl-1.1-template.txt"
NOTO_LICENSE="$ROOTFS_ROOT/noto-cjk-OFL.txt"
FONT_CHARS="$ROOTFS_ROOT/familiar-cjk-chars.txt"
FONT_REGULAR="$ROOTFS_ROOT/NotoSansSC-Regular.otf"
FONT_BOLD="$ROOTFS_ROOT/NotoSansSC-Bold.otf"

print_config() {
  printf '%s\n' \
    "Alpine source: $ALPINE_URL" \
    "Alpine SHA-256: $ALPINE_SHA256" \
    "Alpine signer: $ALPINE_KEY_FINGERPRINT" \
    "Alpine mirror: $ALPINE_MIRROR" \
    "Packages: $APK_PACKAGES" \
    "Python packages: $PIP_PACKAGES ($PIP_INDEX_URL)" \
    "CJK font: $NOTO_APK_URL" \
    "Guest DNS for this build: ${GUEST_DNS:-unchanged}" \
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

if ! python3 -c 'import fontTools' >/dev/null 2>&1; then
  printf '%s\n' "fontTools is required to build the CJK font subset (pip install fonttools)." >&2
  exit 1
fi

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

GUEST_RESOLV="$STAGING_DIRECTORY/etc/resolv.conf"
RESOLV_BACKUP="$ROOTFS_ROOT/resolv.conf.original"
if [ -n "$GUEST_DNS" ]; then
  if [ -f "$GUEST_RESOLV" ]; then cp -f "$GUEST_RESOLV" "$RESOLV_BACKUP"; else : > "$RESOLV_BACKUP"; fi
  : > "$GUEST_RESOLV"
  for server in $GUEST_DNS; do printf 'nameserver %s\n' "$server" >> "$GUEST_RESOLV"; done
fi

# The iSH command-line builder does not propagate guest exit codes, so every
# network step is verified through an explicit marker in the captured output.
apk_output="$("$ISH_BUILDER" -r "$STAGING_DIRECTORY" /bin/sh -lc \
  "printf '%s\\n' '$ALPINE_MIRROR/alpine/v3.24/main' '$ALPINE_MIRROR/alpine/v3.24/community' > /etc/apk/repositories && apk update && apk add --no-cache $APK_PACKAGES && update-ca-certificates && echo FAMILIAR_APK_READY")"
case "$apk_output" in
  *FAMILIAR_APK_READY*) ;;
  *) printf 'The Alpine package installation did not finish.\n' >&2; exit 1 ;;
esac
printf '%s\n' "$apk_output" | tail -3

printf '%s\n' "Installing Python document libraries into the staging rootfs..."
pip_output="$("$ISH_BUILDER" -r "$STAGING_DIRECTORY" /bin/sh -lc \
  "python3 -m pip install --no-cache-dir --root-user-action=ignore --break-system-packages --index-url $PIP_INDEX_URL --no-deps $PIP_PACKAGES && python3 -c 'import docx, openpyxl, pptx, fpdf, pypdf, markdown' && echo FAMILIAR_PIP_READY")"
case "$pip_output" in
  *FAMILIAR_PIP_READY*) ;;
  *) printf 'The Python document libraries did not install in the guest.\n' >&2; printf '%s\n' "$pip_output" | tail -10 >&2; exit 1 ;;
esac
printf '%s\n' "$pip_output" | tail -2

"$ISH_BUILDER" -r "$STAGING_DIRECTORY" /bin/sh -lc \
  "python3 -m pip freeze > /.familiar-pip-freeze.txt"
mv "$STAGING_DIRECTORY/.familiar-pip-freeze.txt" "$PIP_FREEZE"

printf '%s\n' "Preparing the CJK font subset..."
curl --fail --location --retry 4 --retry-all-errors "$NOTO_APK_URL" -o "$NOTO_APK"
actual_font_sha256="$(shasum -a 256 "$NOTO_APK" | awk '{print $1}')"
if [ "$actual_font_sha256" != "$NOTO_APK_SHA256" ]; then
  printf 'Noto CJK package SHA-256 mismatch: expected %s, found %s\n' "$NOTO_APK_SHA256" "$actual_font_sha256" >&2
  exit 1
fi
rm -rf "$NOTO_EXTRACT" "$FONT_REGULAR" "$FONT_BOLD"
mkdir -p "$NOTO_EXTRACT"
tar -xzf "$NOTO_APK" -C "$NOTO_EXTRACT"
python3 - "$FONT_CHARS" <<'PYCHARS'
import sys
chars = set()
for codepoint in range(0x4E00, 0xA000):
    character = chr(codepoint)
    try:
        character.encode("gb2312")
        chars.add(character)
    except UnicodeEncodeError:
        pass
chars.update(chr(c) for c in range(0x20, 0x7F))
chars.update(chr(c) for c in range(0xA0, 0x100))
for start, end in ((0x2000, 0x206F), (0x3000, 0x303F), (0xFF00, 0xFFEF)):
    chars.update(chr(c) for c in range(start, end))
chars.update("①②③④⑤⑥⑦⑧⑨⑩℃㎡№→←↑↓⇒⇔★☆■□●○◆◇▲△※§¶†‡")
open(sys.argv[1], "w", encoding="utf-8").write("".join(sorted(chars)))
PYCHARS
python3 -m fontTools.subset "$NOTO_EXTRACT/usr/share/fonts/noto/NotoSansCJK-Regular.ttc" \
  --font-number=2 --text-file="$FONT_CHARS" --output-file="$FONT_REGULAR" --no-hinting --desubroutinize
python3 -m fontTools.subset "$NOTO_EXTRACT/usr/share/fonts/noto/NotoSansCJK-Bold.ttc" \
  --font-number=2 --text-file="$FONT_CHARS" --output-file="$FONT_BOLD" --no-hinting --desubroutinize
curl --fail --location --retry 4 --retry-all-errors "https://openfontlicense.org/documents/OFL.txt" -o "$NOTO_OFL_TEMPLATE"
python3 - "$NOTO_EXTRACT/usr/share/fonts/noto/NotoSansCJK-Regular.ttc" "$NOTO_OFL_TEMPLATE" "$NOTO_LICENSE" <<'PYLICENSE'
import sys
from fontTools.ttLib import TTFont
ttc, template, output = sys.argv[1:4]
face = TTFont(ttc, fontNumber=2)
copyright_line = (face["name"].getDebugName(0) or "").strip()
text = open(template, encoding="utf-8").read()
start = text.index("This Font Software is licensed")
open(output, "w", encoding="utf-8").write(copyright_line + "\n\n" + text[start:])
PYLICENSE
mkdir -p "$STAGING_DIRECTORY/usr/share/fonts/noto" "$STAGING_DIRECTORY/usr/share/licenses/noto-cjk"
cp "$FONT_REGULAR" "$FONT_BOLD" "$STAGING_DIRECTORY/usr/share/fonts/noto/"
cp "$NOTO_LICENSE" "$STAGING_DIRECTORY/usr/share/licenses/noto-cjk/OFL.txt"
rm -rf "$NOTO_EXTRACT"

"$ISH_BUILDER" -r "$STAGING_DIRECTORY" /bin/sh -lc \
  'awk '\''BEGIN { RS=""; FS="\n" } { name=""; version=""; license=""; for (i=1; i<=NF; i++) { if ($i ~ /^P:/) name=substr($i,3); else if ($i ~ /^V:/) version=substr($i,3); else if ($i ~ /^L:/) license=substr($i,3) } if (name != "") printf "%s\t%s\t%s\n", name, version, license }'\'' /lib/apk/db/installed | sort' \
  > "$PACKAGE_INVENTORY"

if [ -n "$GUEST_DNS" ]; then
  if [ -s "$RESOLV_BACKUP" ]; then cp -f "$RESOLV_BACKUP" "$GUEST_RESOLV"; else rm -f "$GUEST_RESOLV"; fi
fi

COPYFILE_DISABLE=1 tar --format ustar -czf "$STAGING_ARCHIVE" -C "$STAGING_DIRECTORY" .
LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 "$FAKEFSIFY" "$STAGING_ARCHIVE" "$FAKEFS_DIRECTORY"
COPYFILE_DISABLE=1 tar -czf "$OUTPUT_ARCHIVE" -C "$FAKEFS_DIRECTORY" .
shasum -a 256 "$OUTPUT_ARCHIVE" > "$OUTPUT_ARCHIVE.sha256"

if [ "${1:-}" = "--install" ]; then
  cp "$OUTPUT_ARCHIVE" "$INSTALL_ARCHIVE"
  cp "$OUTPUT_ARCHIVE.sha256" "$INSTALL_ARCHIVE.sha256"
fi

print_config
