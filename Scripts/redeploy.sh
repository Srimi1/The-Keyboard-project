#!/usr/bin/env bash
#
# Re-install the app + keyboard on a real iPhone.
#
# Why this exists: on a free personal team the provisioning profile expires 7 days after it
# is issued (C-23). When it lapses the app stops launching and the keyboard disappears
# mid-sentence, with no warning and nothing in the logs — this project's characteristic
# failure mode. The host app shows the countdown; this script is the fix.
#
# After one cable deploy and a device trust, Xcode can deploy over Wi-Fi (C-29), so this
# usually runs without plugging anything in.
#
#   ./Scripts/redeploy.sh                 # first connected device
#   ./Scripts/redeploy.sh "Srimi's iPhone"  # by name
#
set -euo pipefail

cd "$(dirname "$0")/.."

DEVICE="${1:-}"

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "xcodegen not found — brew install xcodegen" >&2
    exit 1
fi

echo "==> Regenerating the project from project.yml"
xcodegen generate --quiet

if [ -z "$DEVICE" ]; then
    echo "==> Looking for a connected device"
    DEVICE=$(xcrun xctrace list devices 2>/dev/null \
        | sed -n '/^== Devices ==/,/^== /p' \
        | grep -v "Simulator" \
        | grep -oE '^[^(]+\([0-9]+\.[0-9]+' \
        | head -1 \
        | sed 's/ *($//' \
        | xargs || true)

    if [ -z "$DEVICE" ]; then
        echo "No device found. Connect the iPhone (or pair it over Wi-Fi in Xcode →" >&2
        echo "Window → Devices and Simulators → Connect via network), then re-run." >&2
        echo "You can also pass the name: ./Scripts/redeploy.sh \"My iPhone\"" >&2
        exit 1
    fi
fi

echo "==> Building and installing on: $DEVICE"
# Signing is deliberately left to Xcode's automatic flow — that is what mints the fresh
# 7-day profile this script exists to renew.
xcodebuild build \
    -project KeyboardProject.xcodeproj \
    -scheme KeyboardProject \
    -configuration Debug \
    -destination "platform=iOS,name=$DEVICE" \
    -allowProvisioningUpdates

cat <<'DONE'

==> Done. The profile is good for another 7 days.

If the keyboard is missing from Settings afterwards, open the app once — iOS only
registers a newly installed extension after its containing app has launched.
DONE
