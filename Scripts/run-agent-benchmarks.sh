#!/bin/bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
SIMULATOR_ID=${FAMILIAR_SIMULATOR_ID:-}

if [[ -z "$SIMULATOR_ID" ]]; then
  SIMULATOR_ID=$(python3 - <<'PY'
import json
import subprocess

devices = json.loads(
    subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"])
)["devices"]
candidates = [
    (runtime, device)
    for runtime, values in devices.items()
    if "iOS" in runtime
    for device in values
    if device["name"].startswith("iPhone")
]
if not candidates:
    raise SystemExit("No available iPhone Simulator")
print(sorted(candidates, key=lambda item: item[0], reverse=True)[0][1]["udid"])
PY
  )
fi

if [[ $(xcrun simctl list devices -j | python3 -c 'import json,sys; data=json.load(sys.stdin); target=sys.argv[1]; print(next((device["state"] for values in data["devices"].values() for device in values if device["udid"] == target), "Missing"))' "$SIMULATOR_ID") != "Booted" ]]; then
  xcrun simctl boot "$SIMULATOR_ID"
fi
xcrun simctl bootstatus "$SIMULATOR_ID" -b

xcodebuild \
  -project "$ROOT_DIR/familiar.xcodeproj" \
  -scheme Familiar \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:FamiliarTests/FamiliarBenchmarkTests \
  test
