#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
APK_PATH="$ROOT_DIR/build/app/outputs/flutter-apk/app-debug.apk"
PACKAGE_NAME="${PACKAGE_NAME:-${PLANDONE_APPLICATION_ID:-com.example.plandone}}"
DEVICE_ID="${1:-}"
PROFILE="${2:-${PLANDONE_RUNTIME_PROFILE:-firebase}}"

if [[ -z "$DEVICE_ID" ]]; then
  DEVICE_ID="$(adb devices | awk 'NR>1 && $2=="device" && $1 !~ /^emulator-/ {print $1; exit}')"
fi

if [[ -z "$DEVICE_ID" ]]; then
  echo "No physical Android device found. Pass device id explicitly:"
  echo "  scripts/deploy_android_latest.sh <device-id> [local|firebase]"
  exit 1
fi

echo "Using device: $DEVICE_ID"
echo "Flutter: $FLUTTER_BIN"
echo "Runtime profile: $PROFILE"

echo "Building latest debug APK..."
FLUTTER_BIN="$FLUTTER_BIN" \
  "$ROOT_DIR/scripts/build_android_profile.sh" "$PROFILE" debug

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
