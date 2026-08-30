#!/bin/sh
set -eu

REPOSITORY_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ISH_SOURCE="$REPOSITORY_ROOT/Vendor/ish-arm64"
BRIDGE_SOURCE="$REPOSITORY_ROOT/Vendor/ISHRuntime/Bridge"
NETWORK_PATCH="$REPOSITORY_ROOT/Vendor/ISHRuntime/Patches/network-policy.patch"
EXPECTED_COMMIT="54ca185b77f170e12fd353fcd7443232f6cb73fd"
BUILD_ROOT="${FAMILIAR_ISH_BUILD_ROOT:-$REPOSITORY_ROOT/.build/ish}"
XCFRAMEWORK_OUTPUT="$BUILD_ROOT/xcframeworks/FamiliarISHRuntime.xcframework"
INSTALL_OUTPUT="$REPOSITORY_ROOT/Vendor/ISHRuntime/FamiliarISHRuntime.xcframework"
IPHONEOS_BUILD="$BUILD_ROOT/iphoneos"
SIMULATOR_BUILD="$BUILD_ROOT/iphonesimulator"
PATCHED_SOURCE="$BUILD_ROOT/source/ish-arm64"
PUBLIC_HEADERS="$BUILD_ROOT/public-headers"
TARGETS="libish libish_emu libfakefs"

if [ -d /opt/homebrew/opt/llvm/bin ]; then
  PATH="/opt/homebrew/opt/llvm/bin:$PATH"
fi
if [ -d /opt/homebrew/opt/lld/bin ]; then
  PATH="/opt/homebrew/opt/lld/bin:$PATH"
fi
export PATH

print_config() {
  printf '%s\n' \
    "iSH source: $ISH_SOURCE" \
    "iSH commit: $EXPECTED_COMMIT" \
    "Targets: $TARGETS" \
    "Platforms: iphoneos/arm64 iphonesimulator/arm64" \
    "Output: $XCFRAMEWORK_OUTPUT" \
    "Link libraries: archive sqlite3 bz2 iconv resolv" \
    "Link frameworks: SystemConfiguration"
}

if [ "${1:-}" = "--print-config" ]; then
  print_config
  exit 0
fi

if [ ! -f "$ISH_SOURCE/iSH.xcodeproj/project.pbxproj" ]; then
  printf '%s\n' \
    "The iSH submodule is not initialized." \
    "Run: git submodule update --init Vendor/ish-arm64" >&2
  exit 1
fi

actual_commit="$(git -C "$ISH_SOURCE" rev-parse HEAD)"
if [ "$actual_commit" != "$EXPECTED_COMMIT" ]; then
  printf 'Expected iSH %s, found %s\n' "$EXPECTED_COMMIT" "$actual_commit" >&2
  exit 1
fi

rm -rf "$PATCHED_SOURCE"
mkdir -p "$PATCHED_SOURCE"
rsync -a --exclude '.git' --exclude 'build-*' "$ISH_SOURCE/" "$PATCHED_SOURCE/"
patch -d "$PATCHED_SOURCE" -p1 < "$NETWORK_PATCH"

for command_name in xcodebuild xcrun; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$command_name" >&2
    exit 1
  fi
done

build_platform() {
  sdk="$1"
  platform_build="$2"
  products="$platform_build/products"
  objects="$platform_build/objects"
  bridge_objects="$platform_build/bridge-objects"

  mkdir -p "$products" "$objects" "$bridge_objects"

  for target in $TARGETS; do
    xcodebuild \
      -project "$PATCHED_SOURCE/iSH.xcodeproj" \
      -target "$target" \
      -configuration Release \
      -sdk "$sdk" \
      -arch arm64 \
      SYMROOT="$platform_build/symroot" \
      OBJROOT="$objects" \
      CONFIGURATION_BUILD_DIR="$products" \
      ARCHS=arm64 \
      ONLY_ACTIVE_ARCH=YES \
      CODE_SIGNING_ALLOWED=NO \
      SKIP_INSTALL=NO \
      IPHONEOS_DEPLOYMENT_TARGET=18.0 \
      GUEST_ARCH=arm64 \
      MESON_GUEST_OPTION=-Dguest_arch=arm64 \
      GCC_PREPROCESSOR_DEFINITIONS='GUEST_ARM64=1' \
      HEADER_SEARCH_PATHS="$BRIDGE_SOURCE" \
      FAMILIAR_ISH_BRIDGE_HEADERS="$BRIDGE_SOURCE" \
      build
  done

  for library in libish.a libish_emu.a libfakefs.a; do
    if [ ! -f "$products/$library" ]; then
      printf 'Expected build product is missing: %s\n' "$products/$library" >&2
      exit 1
    fi
  done

  sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
  case "$sdk" in
    iphoneos) target="arm64-apple-ios18.0" ;;
    iphonesimulator) target="arm64-apple-ios18.0-simulator" ;;
    *) printf 'Unsupported SDK: %s\n' "$sdk" >&2; exit 1 ;;
  esac

  for source in "$BRIDGE_SOURCE/ISHKernel.m" "$BRIDGE_SOURCE/ISHShellExecutor.m" "$BRIDGE_SOURCE/FamiliarISHNetworkPolicy.m"; do
    object="$bridge_objects/$(basename "$source" .m).o"
    xcrun --sdk "$sdk" clang \
      -target "$target" \
      -isysroot "$sdk_path" \
      -fobjc-arc \
      -fblocks \
      -DGUEST_ARM64=1 \
      -DISH_INTERNAL=1 \
      -I "$PATCHED_SOURCE" \
      -I "$BRIDGE_SOURCE" \
      -c "$source" \
      -o "$object"
  done

  xcrun libtool -static \
    "$products/libish.a" \
    "$products/libish_emu.a" \
    "$products/libfakefs.a" \
    "$bridge_objects/ISHKernel.o" \
    "$bridge_objects/ISHShellExecutor.o" \
    "$bridge_objects/FamiliarISHNetworkPolicy.o" \
    -o "$platform_build/libFamiliarISHRuntime.a"
}

rm -rf "$IPHONEOS_BUILD" "$SIMULATOR_BUILD" "$XCFRAMEWORK_OUTPUT" "$PUBLIC_HEADERS"
mkdir -p "$(dirname "$XCFRAMEWORK_OUTPUT")"
mkdir -p "$PUBLIC_HEADERS"
cp "$BRIDGE_SOURCE/FamiliarISHRuntime.h" "$PUBLIC_HEADERS/"
cp "$BRIDGE_SOURCE/FamiliarISHNetworkPolicy.h" "$PUBLIC_HEADERS/"
cp "$BRIDGE_SOURCE/ISHKernel.h" "$PUBLIC_HEADERS/"
cp "$BRIDGE_SOURCE/ISHShellExecutor.h" "$PUBLIC_HEADERS/"

build_platform iphoneos "$IPHONEOS_BUILD"
build_platform iphonesimulator "$SIMULATOR_BUILD"

xcodebuild -create-xcframework \
  -library "$IPHONEOS_BUILD/libFamiliarISHRuntime.a" \
  -headers "$PUBLIC_HEADERS" \
  -library "$SIMULATOR_BUILD/libFamiliarISHRuntime.a" \
  -headers "$PUBLIC_HEADERS" \
  -output "$XCFRAMEWORK_OUTPUT"

if [ "${1:-}" = "--install" ]; then
  rm -rf "$INSTALL_OUTPUT"
  cp -R "$XCFRAMEWORK_OUTPUT" "$INSTALL_OUTPUT"
fi

print_config
printf '%s\n' "The XCFramework contains the pinned iSH runtime and Familiar's headless Objective-C bridge."
