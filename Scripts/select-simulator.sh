#!/usr/bin/env bash

# Print one stable iPhone simulator UDID for local `make test` use. Prefer an already booted
# device so the test command and visual-preview workflow share one simulator owner.

set -euo pipefail

xcrun simctl list devices available -j | python3 -c '
import json
import re
import sys

document = json.load(sys.stdin)

def runtime_version(runtime):
    match = re.search(r"iOS-([0-9-]+)$", runtime)
    if not match:
        return ()
    return tuple(int(component) for component in match.group(1).split("-"))

candidates = []
for runtime in sorted(document.get("devices", {}), key=runtime_version, reverse=True):
    for device in document["devices"][runtime]:
        if device.get("isAvailable") and "iPhone" in device.get("name", ""):
            candidates.append(device)

if not candidates:
    print("No available iPhone simulator", file=sys.stderr)
    raise SystemExit(1)

selected = next((device for device in candidates if device.get("state") == "Booted"), candidates[0])
print(selected["udid"])
'
