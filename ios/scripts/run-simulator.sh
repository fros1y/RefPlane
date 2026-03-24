#!/usr/bin/env bash
# Run the RefPlane app on an iOS Simulator.
# Usage: ./ios/scripts/run-simulator.sh [SimulatorName]
# Default simulator: iPhone 16

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROJECT="$REPO_ROOT/ios/RefPlane.xcodeproj"
SCHEME="RefPlane"
BUNDLE_ID="com.refplane.app"
SIM_NAME="${1:-iPhone 16}"

# ── 1. Find a suitable simulator (prefer already-booted) ────────────────────
DEVICE_ID=$(xcrun simctl list devices | grep "$SIM_NAME" | grep -v "Plus\|Pro Max" | grep "(Booted)" | head -1 | grep -oE '[A-Z0-9]{8}-([A-Z0-9]{4}-){3}[A-Z0-9]{12}')

if [ -z "$DEVICE_ID" ]; then
    DEVICE_ID=$(xcrun simctl list devices | grep "$SIM_NAME" | grep -v "Plus\|Pro Max" | head -1 | grep -oE '[A-Z0-9]{8}-([A-Z0-9]{4}-){3}[A-Z0-9]{12}')
    if [ -z "$DEVICE_ID" ]; then
        echo "❌  No simulator matching '$SIM_NAME' found. Available devices:"
        xcrun simctl list devices | grep "iPhone"
        exit 1
    fi
    echo "▶  Booting simulator $SIM_NAME ($DEVICE_ID)…"
    xcrun simctl boot "$DEVICE_ID"
fi

echo "✅  Using simulator $SIM_NAME ($DEVICE_ID)"

# ── 2. Build for that specific device ───────────────────────────────────────
echo "🔨  Building…"
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -destination "platform=iOS Simulator,id=$DEVICE_ID" \
    build

# ── 3. Locate the built .app bundle ─────────────────────────────────────────
APP_DIR=$(xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -destination "platform=iOS Simulator,id=$DEVICE_ID" \
    -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/^\s*BUILT_PRODUCTS_DIR/{print $2}')

APP_PATH="$APP_DIR/$SCHEME.app"

if [ ! -d "$APP_PATH" ]; then
    echo "❌  Built app not found at: $APP_PATH"
    exit 1
fi

# ── 4. Install and launch ────────────────────────────────────────────────────
echo "📲  Installing $APP_PATH…"
xcrun simctl install "$DEVICE_ID" "$APP_PATH"

echo "🚀  Launching $BUNDLE_ID…"
xcrun simctl launch "$DEVICE_ID" "$BUNDLE_ID"

open -a Simulator
