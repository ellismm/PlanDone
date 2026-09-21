#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PROFILE="${1:-firebase}"
BUILD_MODE="${2:-release}"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
DEFINE_FILE="$ROOT_DIR/config/runtime/$PROFILE.json"
FIREBASE_CONFIG="$ROOT_DIR/android/app/google-services.json"
REQUIRE_RELEASE_SIGNING="${PLANDONE_REQUIRE_RELEASE_SIGNING:-false}"

case "$PROFILE" in
  local|firebase) ;;
  *)
    echo "Unknown runtime profile: $PROFILE"
    echo "Use: scripts/build_android_profile.sh <local|firebase> <debug|release>"
    exit 2
    ;;
esac

case "$BUILD_MODE" in
  debug|release) ;;
  *)
    echo "Unknown Android build mode: $BUILD_MODE"
    echo "Use: scripts/build_android_profile.sh <local|firebase> <debug|release>"
    exit 2
    ;;
esac

if [[ ! -f "$DEFINE_FILE" ]]; then
  echo "Runtime profile file not found: $DEFINE_FILE"
  exit 2
fi

if [[ "$PROFILE" == "firebase" && ! -f "$FIREBASE_CONFIG" ]]; then
  echo "Firebase profile requires: $FIREBASE_CONFIG"
  echo "Download google-services.json for the matching Android application id."
  exit 2
fi

if [[ "$BUILD_MODE" == "release" ]]; then
  has_signing_file=false
  has_signing_environment=false
  if [[ -f "$ROOT_DIR/android/key.properties" ]]; then
    has_signing_file=true
  fi
  if [[ -n "${PLANDONE_RELEASE_STORE_FILE:-}" &&
        -n "${PLANDONE_RELEASE_STORE_PASSWORD:-}" &&
        -n "${PLANDONE_RELEASE_KEY_ALIAS:-}" &&
        -n "${PLANDONE_RELEASE_KEY_PASSWORD:-}" ]]; then
    has_signing_environment=true
  fi
  if [[ "$has_signing_file" != true && "$has_signing_environment" != true ]]; then
    if [[ "$REQUIRE_RELEASE_SIGNING" == "true" ]]; then
      echo "Release signing is required but no complete signing configuration was found."
      exit 2
    fi
    echo "Warning: building a validation APK with debug signing."
    echo "Set PLANDONE_REQUIRE_RELEASE_SIGNING=true for distributable builds."
  fi
fi

BUILD_COMMAND=(
  "$FLUTTER_BIN"
  build
  apk
  "--$BUILD_MODE"
  "--dart-define-from-file=$DEFINE_FILE"
)

echo "Runtime profile: $PROFILE"
echo "Build mode: $BUILD_MODE"
echo "Define file: $DEFINE_FILE"

if [[ "${PLANDONE_DRY_RUN:-false}" == "true" ]]; then
  printf 'Command:'
  printf ' %q' "${BUILD_COMMAND[@]}"
  printf '\n'
  exit 0
fi

"${BUILD_COMMAND[@]}"
