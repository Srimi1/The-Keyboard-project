#!/usr/bin/env bash
# Fast launch-policy checks that do not require a simulator or signing identity.
set -euo pipefail

cd "$(dirname "$0")/.."

for plist in \
    Sources/HostApp/Info.plist \
    Sources/HostApp/HostApp.entitlements \
    Sources/HostApp/PrivacyInfo.xcprivacy \
    Sources/Keyboard/Info.plist \
    Sources/Keyboard/Keyboard.entitlements \
    Sources/Keyboard/PrivacyInfo.xcprivacy; do
    plutil -lint "$plist" >/dev/null
done

python3 - "$PWD" <<'PY'
from pathlib import Path
import plistlib
import sys

root = Path(sys.argv[1])
group = "group.com.srijan.keyboardproject"

def load(path):
    with (root / path).open("rb") as handle:
        return plistlib.load(handle)

host_info = load("Sources/HostApp/Info.plist")
keyboard_info = load("Sources/Keyboard/Info.plist")
host_entitlements = load("Sources/HostApp/HostApp.entitlements")
keyboard_entitlements = load("Sources/Keyboard/Keyboard.entitlements")

assert "CFBundleURLTypes" not in host_info, "Custom URL schemes are forbidden for this launch scope"
attributes = keyboard_info["NSExtension"]["NSExtensionAttributes"]
assert attributes.get("IsASCIICapable") is True, "English keyboard must declare IsASCIICapable"
assert attributes.get("RequestsOpenAccess") is True, "Clipboard sharing capability is missing"
assert host_entitlements.get("com.apple.security.application-groups") == [group]
assert keyboard_entitlements.get("com.apple.security.application-groups") == [group]

required_reasons = {"1C8F.1", "CA92.1"}
for path in (
    "Sources/HostApp/PrivacyInfo.xcprivacy",
    "Sources/Keyboard/PrivacyInfo.xcprivacy",
):
    manifest = load(path)
    assert manifest.get("NSPrivacyTracking") is False, f"{path}: tracking must be false"
    reasons = set()
    for entry in manifest.get("NSPrivacyAccessedAPITypes", []):
        if entry.get("NSPrivacyAccessedAPIType") == "NSPrivacyAccessedAPICategoryUserDefaults":
            reasons.update(entry.get("NSPrivacyAccessedAPITypeReasons", []))
    assert required_reasons <= reasons, f"{path}: missing UserDefaults required reasons"

production_swift = [
    path for path in (root / "Sources").rglob("*.swift")
    if path.name != "DiagnosticsRunner.swift"
]
network_tokens = (
    "URLSession", "NWConnection", "import Network", "CFNetwork",
    "URLSessionWebSocketTask", "Alamofire",
)
for path in production_swift:
    source = path.read_text(encoding="utf-8")
    assert "UIPasteboard.general" not in source, (
        f"{path.relative_to(root)}: lifecycle/direct pasteboard access is forbidden; use PasteButton"
    )
    for token in network_tokens:
        assert token not in source, f"{path.relative_to(root)}: app-owned networking token {token!r} found"

for path in (root / "Sources/Keyboard").glob("Clipboard*.swift"):
    source = path.read_text(encoding="utf-8")
    for token in ("print(", "Logger(", "os_log(", "NSLog("):
        assert token not in source, f"{path.relative_to(root)}: clipboard text must never be logged"

keyboard_source = "\n".join(
    path.read_text(encoding="utf-8")
    for path in (root / "Sources/Keyboard").glob("*.swift")
)
assert "UIApplication.shared.open" not in keyboard_source
assert "openURL(" not in keyboard_source
PY

for script in Scripts/*.sh; do
    bash -n "$script"
done

echo "Static privacy, entitlement, plist, and shell checks passed."
