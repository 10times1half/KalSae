#!/usr/bin/env bash
# Cross-compile KalsaePlatformAndroid and emit a Gradle APK locally.
#
# Mirrors `.github/workflows/phase-android-e2e.yml`. Use this on a Linux or
# macOS host to reproduce CI Android builds. Windows hosts must use WSL —
# `swift-android-sdk` is not officially supported on native Windows toolchains.
#
# Prerequisites:
#   - Swift 6.2 RELEASE on PATH (https://swift.org/install)
#   - Java 17 (Temurin recommended) on PATH
#   - Android cmdline-tools with `platforms;android-35` + `build-tools;35.0.0`
#   - $ANDROID_NDK_HOME pointing at NDK r27d (or compatible)
#
# Usage:
#   ./Scripts/cross-compile-android.sh          # full pipeline → dist/android-e2e/
#   ./Scripts/cross-compile-android.sh --no-apk # stop after cross-compile + emit
#
# RFC-007 Phase 6.3 (Android cross-compile E2E).

set -euo pipefail

SWIFT_ANDROID_SDK_URL="https://github.com/swift-android-sdk/swift-android-sdk/releases/download/6.2/swift-6.2-RELEASE-android-0.1.artifactbundle.tar.gz"
SWIFT_ANDROID_SDK_CHECKSUM="ca7e09f09a591b6a661a39134aaf53b1b59d5e3a193b271ab1f20effdfc6e88e"
SWIFT_ANDROID_SDK_TRIPLE="aarch64-unknown-linux-android28"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

SKIP_APK=0
if [ "${1:-}" = "--no-apk" ]; then
  SKIP_APK=1
fi

case "$(uname -s)" in
  Linux|Darwin) ;;
  *)
    echo "ERROR: cross-compile-android.sh requires Linux or macOS." >&2
    echo "       Windows users: run this from WSL." >&2
    exit 1
    ;;
esac

echo "==> 1/5 Verify Swift Android SDK is installed"
if ! swift sdk list 2>/dev/null | grep -q 'swift-6.2'; then
  echo "Installing Swift Android SDK 6.2..."
  swift sdk install "$SWIFT_ANDROID_SDK_URL" --checksum "$SWIFT_ANDROID_SDK_CHECKSUM"
else
  echo "Already installed."
fi

echo "==> 2/5 Cross-compile KalsaePlatformAndroid"
swift build \
  --swift-sdk "$SWIFT_ANDROID_SDK_TRIPLE" \
  --product KalsaePlatformAndroid \
  -c release

SO_PATH=$(find .build -name 'libKalsaePlatformAndroid.so' -path '*release*' | head -n1)
if [ -z "$SO_PATH" ]; then
  echo "ERROR: libKalsaePlatformAndroid.so not produced." >&2
  exit 1
fi
echo "    → $SO_PATH"

echo "==> 3/5 Build kalsae CLI (host toolchain)"
swift build --product kalsae -c release

echo "==> 4/5 Emit Android Gradle project"
OUTPUT_DIR="$REPO_ROOT/dist/android-e2e"
rm -rf "$OUTPUT_DIR"
.build/release/kalsae build \
  --android \
  --android-native-lib "$SO_PATH" \
  --android-min-sdk 28 \
  --android-target-sdk 35 \
  --config Sources/KalsaeDemo/Resources/kalsae.json \
  --dist Sources/KalsaeDemo/Resources \
  --output "$OUTPUT_DIR"
echo "    → $OUTPUT_DIR"

if [ "$SKIP_APK" -eq 1 ]; then
  echo "==> 5/5 (skipped — --no-apk)"
  exit 0
fi

echo "==> 5/5 Assemble debug APK via Gradle"
cd "$OUTPUT_DIR"
if [ ! -f gradlew ]; then
  gradle wrapper --gradle-version 8.10 --distribution-type bin
fi
./gradlew --no-daemon assembleDebug

APK=$(find . -name 'app-debug.apk' -path '*outputs*' | head -n1)
echo
echo "✓ Build complete."
echo "  APK: $OUTPUT_DIR/${APK#./}"
