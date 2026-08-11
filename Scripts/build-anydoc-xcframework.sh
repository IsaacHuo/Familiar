#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BRIDGE="$ROOT/Vendor/AnyDocBridgeRust"
OUTPUT="$ROOT/Vendor/AnyDocBridge.xcframework"

rustup target add aarch64-apple-ios aarch64-apple-ios-sim
cargo build --manifest-path "$BRIDGE/Cargo.toml" --release --locked --target aarch64-apple-ios
cargo build --manifest-path "$BRIDGE/Cargo.toml" --release --locked --target aarch64-apple-ios-sim

rm -rf "$OUTPUT"
xcodebuild -create-xcframework \
  -library "$BRIDGE/target/aarch64-apple-ios/release/libfamiliar_anydoc_bridge.a" \
  -headers "$BRIDGE/include" \
  -library "$BRIDGE/target/aarch64-apple-ios-sim/release/libfamiliar_anydoc_bridge.a" \
  -headers "$BRIDGE/include" \
  -output "$OUTPUT"
