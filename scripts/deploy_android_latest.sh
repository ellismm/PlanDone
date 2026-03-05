#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FLUTTER_BIN="${FLUTTER_BIN:-/home/messay/snap/flutter/common/flutter/bin/flutter}"
APK_PATH="$ROOT_DIR/build/app/outputs/flutter-apk/app-debug.apk"
PACKAGE_NAME="${PACKAGE_NAME:-com.example.plandone}"
DEVICE_ID="${1:-}"

if [[ -z "$DEVICE_ID" ]]; then
  DEVICE_ID="$(adb devices | awk 'NR>1 && $2=="device" && $1 !~ /^emulator-/ {print $1; exit}')"
fi

if [[ -z "$DEVICE_ID" ]]; then
  echo "No physical Android device found. Pass device id explicitly:"
  echo "  scripts/deploy_android_latest.sh <device-id>"
  exit 1
fi

echo "Using device: $DEVICE_ID"
echo "Flutter: $FLUTTER_BIN"

echo "Building latest debug APK..."
"$FLUTTER_BIN" build apk --debug

if [[ ! -f "$APK_PATH" ]]; then
  echo "Expected APK not found: $APK_PATH"
  exit 1
fi

echo "Built APK:"
stat -c "%y %n" "$APK_PATH"

echo "Installing APK..."
adb -s "$DEVICE_ID" install -r "$APK_PATH"

echo "Launching app..."
adb -s "$DEVICE_ID" shell monkey -p "$PACKAGE_NAME" -c android.intent.category.LAUNCHER 1 >/dev/null

echo "Done."
