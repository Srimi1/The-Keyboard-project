#!/usr/bin/env bash
# Build, verify, install, and launch Keyboard Project on one explicitly resolved iPhone.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_BUNDLE_ID="com.srijan.keyboardproject"
EXTENSION_BUNDLE_ID="com.srijan.keyboardproject.keyboard"
APP_GROUP_ID="group.com.srijan.keyboardproject"
CONFIGURATION="${CONFIGURATION:-Debug}"
ACTION="${KB_ACTION:-deploy}"
DEVICE_SELECTOR="${KB_DEVICE_ID:-${1:-}}"
DERIVED_DATA="${KB_DERIVED_DATA:-$PWD/.build/device}"
APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION-iphoneos/KeyboardProject.app"
EXTENSION_PATH="$APP_PATH/PlugIns/KeyboardExtension.appex"
APP_PROFILE="$APP_PATH/embedded.mobileprovision"
EXTENSION_PROFILE="$EXTENSION_PATH/embedded.mobileprovision"

case "$ACTION" in
    build|install|launch|deploy) ;;
    *) echo "KB_ACTION must be build, install, launch, or deploy." >&2; exit 2 ;;
esac

if [ "$ACTION" != "launch" ] && [ -z "${DEVELOPMENT_TEAM:-}" ]; then
    echo "Set DEVELOPMENT_TEAM to the Apple Team ID shown in Xcode → Settings → Accounts." >&2
    exit 2
fi
if [ "$ACTION" = "build" ] || [ "$ACTION" = "deploy" ]; then
    command -v xcodegen >/dev/null 2>&1 || {
        echo "xcodegen is required (tested with 2.45.4)." >&2
        exit 2
    }
fi
command -v python3 >/dev/null 2>&1 || {
    echo "python3 is required to parse devicectl's supported JSON output." >&2
    exit 2
}

TEMP_DIR="$(mktemp -d -t keyboard-deploy.XXXXXX)"
trap 'rm -rf "$TEMP_DIR"' EXIT
DEVICES_JSON="$TEMP_DIR/devices.json"

xcrun devicectl list devices --timeout 20 --json-output "$DEVICES_JSON" >/dev/null

SELECTION="$(python3 - "$DEVICES_JSON" "$DEVICE_SELECTOR" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    devices = json.load(handle).get("result", {}).get("devices", [])

selector = sys.argv[2]
physical = [d for d in devices if d.get("hardwareProperties", {}).get("reality") == "physical"]

def values(device):
    props = device.get("deviceProperties", {})
    hardware = device.get("hardwareProperties", {})
    return {
        "identifier": str(device.get("identifier", "")),
        "udid": str(hardware.get("udid", "")),
        "name": str(props.get("name", "")),
        "os": str(props.get("osVersionNumber", "unknown")),
        "available": bool(props.get("ddiServicesAvailable"))
            and device.get("connectionProperties", {}).get("tunnelState") != "unavailable",
    }

rows = [values(device) for device in physical]
if selector:
    matches = [row for row in rows if selector in (row["identifier"], row["udid"], row["name"])]
else:
    matches = [row for row in rows if row["available"]]

if not matches:
    known = next((row for row in rows if selector and selector in (row["identifier"], row["udid"], row["name"])), None)
    if known and not known["available"]:
        print(f"The selected iPhone ({known['name']}) is paired but unavailable. Unlock it and connect USB or the same Wi-Fi.", file=sys.stderr)
    else:
        print("No available physical iPhone found. Unlock and connect it, then retry.", file=sys.stderr)
    sys.exit(3)
if len(matches) != 1:
    print("More than one iPhone is available. Set KB_DEVICE_ID to its UDID or CoreDevice identifier.", file=sys.stderr)
    for row in matches:
        print(f"  {row['name']}: {row['udid']}", file=sys.stderr)
    sys.exit(4)

row = matches[0]
if not row["available"]:
    print(f"The selected iPhone ({row['name']}) is unavailable. Unlock and connect it.", file=sys.stderr)
    sys.exit(3)
print("|".join((row["identifier"], row["udid"], row["name"], row["os"])))
PY
)"

IFS='|' read -r CORE_DEVICE_ID DEVICE_UDID DEVICE_NAME DEVICE_OS <<< "$SELECTION"
echo "==> Target: $DEVICE_NAME (iOS $DEVICE_OS, $DEVICE_UDID)"

if [ "$ACTION" = "build" ] || [ "$ACTION" = "deploy" ]; then
    echo "==> Generating project"
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" xcodegen generate --quiet

    echo "==> Building $CONFIGURATION"
    xcodebuild build \
        -project KeyboardProject.xcodeproj \
        -scheme KeyboardProject \
        -configuration "$CONFIGURATION" \
        -destination "platform=iOS,id=$DEVICE_UDID" \
        -derivedDataPath "$DERIVED_DATA" \
        -allowProvisioningUpdates \
        DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM"
fi

if [ "$ACTION" != "launch" ]; then
    [ -d "$APP_PATH" ] || { echo "Built app not found at $APP_PATH" >&2; exit 5; }
    [ -d "$EXTENSION_PATH" ] || { echo "Embedded keyboard extension is missing." >&2; exit 5; }
    [ -f "$APP_PROFILE" ] || { echo "Host provisioning profile is missing." >&2; exit 5; }
    [ -f "$EXTENSION_PROFILE" ] || { echo "Keyboard provisioning profile is missing." >&2; exit 5; }

    ACTUAL_APP_BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw "$APP_PATH/Info.plist")"
    ACTUAL_EXTENSION_BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw "$EXTENSION_PATH/Info.plist")"
    [ "$ACTUAL_APP_BUNDLE_ID" = "$APP_BUNDLE_ID" ] || {
        echo "Built host bundle ID is $ACTUAL_APP_BUNDLE_ID, expected $APP_BUNDLE_ID." >&2; exit 6;
    }
    [ "$ACTUAL_EXTENSION_BUNDLE_ID" = "$EXTENSION_BUNDLE_ID" ] || {
        echo "Built extension bundle ID is $ACTUAL_EXTENSION_BUNDLE_ID, expected $EXTENSION_BUNDLE_ID." >&2; exit 6;
    }

    echo "==> Verifying signatures, profiles, and App Group entitlements"
    codesign --verify --deep --strict "$APP_PATH"
    codesign --verify --strict "$EXTENSION_PATH"
    codesign -d --entitlements "$TEMP_DIR/host-signature.plist" --xml "$APP_PATH" 2>/dev/null
    codesign -d --entitlements "$TEMP_DIR/extension-signature.plist" --xml "$EXTENSION_PATH" 2>/dev/null

    security cms -D -i "$APP_PROFILE" -o "$TEMP_DIR/host-profile.plist"
    security cms -D -i "$EXTENSION_PROFILE" -o "$TEMP_DIR/extension-profile.plist"
    python3 - \
        "$TEMP_DIR/host-profile.plist" "$APP_BUNDLE_ID" \
        "$TEMP_DIR/extension-profile.plist" "$EXTENSION_BUNDLE_ID" \
        "$TEMP_DIR/host-signature.plist" "$TEMP_DIR/extension-signature.plist" \
        "$APP_GROUP_ID" "$DEVELOPMENT_TEAM" <<'PY'
from datetime import datetime
import plistlib
import sys

(
    host_path, host_bundle, extension_path, extension_bundle,
    host_signature_path, extension_signature_path, group, expected_team,
) = sys.argv[1:]

def verify(path, bundle_id, label):
    with open(path, "rb") as handle:
        profile = plistlib.load(handle)
    entitlements = profile.get("Entitlements", {})
    teams = profile.get("TeamIdentifier", [])
    team = entitlements.get("com.apple.developer.team-identifier")
    app_identifier = entitlements.get("application-identifier", "")
    groups = entitlements.get("com.apple.security.application-groups", [])
    expiration = profile.get("ExpirationDate")

    if expected_team not in teams or team != expected_team:
        raise SystemExit(f"{label} profile does not belong to DEVELOPMENT_TEAM {expected_team}.")
    if app_identifier != f"{expected_team}.{bundle_id}":
        raise SystemExit(f"{label} profile is for {app_identifier!r}, not {bundle_id}.")
    if group not in groups:
        raise SystemExit(f"{label} profile is missing App Group {group}.")
    comparison_now = datetime.now(expiration.tzinfo) if isinstance(expiration, datetime) and expiration.tzinfo else datetime.utcnow()
    if not isinstance(expiration, datetime) or expiration <= comparison_now:
        raise SystemExit(f"{label} provisioning profile is expired or has no valid expiration date.")

    name = profile.get("Name", "unnamed profile")
    print(f"    {label}: {name} (expires {expiration.isoformat()}Z)")

verify(host_path, host_bundle, "host")
verify(extension_path, extension_bundle, "extension")

for path, label in (
    (host_signature_path, "host"),
    (extension_signature_path, "extension"),
):
    with open(path, "rb") as handle:
        signed = plistlib.load(handle)
    if group not in signed.get("com.apple.security.application-groups", []):
        raise SystemExit(f"{label} signature is missing App Group {group}.")
PY
fi

if [ "$ACTION" = "install" ] || [ "$ACTION" = "deploy" ]; then
    echo "==> Installing over the existing app (retention must be verified on device)"
    xcrun devicectl device install app \
        --device "$CORE_DEVICE_ID" \
        --timeout 60 \
        --json-output "$TEMP_DIR/install.json" \
        "$APP_PATH"

    xcrun devicectl device info apps \
        --device "$CORE_DEVICE_ID" \
        --bundle-id "$APP_BUNDLE_ID" \
        --timeout 30 \
        --json-output "$TEMP_DIR/apps.json" >/dev/null
    python3 - "$TEMP_DIR/apps.json" "$APP_BUNDLE_ID" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    payload = json.load(handle)

def contains_bundle(value, target):
    if isinstance(value, dict):
        return any((key in {"bundleIdentifier", "bundleID", "bundleId"} and item == target)
                   or contains_bundle(item, target) for key, item in value.items())
    if isinstance(value, list):
        return any(contains_bundle(item, target) for item in value)
    return False

if not contains_bundle(payload.get("result", {}), sys.argv[2]):
    print("Install command returned, but the host app was not found on the device.", file=sys.stderr)
    sys.exit(7)
PY
fi

if [ "$ACTION" = "launch" ] || [ "$ACTION" = "deploy" ]; then
    echo "==> Launching host app"
    xcrun devicectl device process launch \
        --device "$CORE_DEVICE_ID" \
        --terminate-existing \
        --timeout 30 \
        --json-output "$TEMP_DIR/launch.json" \
        "$APP_BUNDLE_ID"
fi

echo "==> $ACTION completed successfully."
if [ "$ACTION" = "deploy" ]; then
    echo "Add the keyboard in Settings → General → Keyboard → Keyboards."
    echo "If this build uses free Personal Team provisioning, its profile is short-lived; rerun this command before it expires."
fi
