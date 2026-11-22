#!/usr/bin/env bash
set -euo pipefail

IPA="${1:-build/Orion-Subtitles.ipa}"
EXPECTED_BUNDLE_ID="${EXPECTED_BUNDLE_ID:-com.orion.subtitles}"
CHECK_DIR="$(mktemp -d)"
trap 'rm -rf "$CHECK_DIR"' EXIT

[ -f "$IPA" ] || { echo "FAIL: IPA not found: $IPA" >&2; exit 1; }
unzip -q "$IPA" -d "$CHECK_DIR"
APP_PLIST="$(find "$CHECK_DIR/Payload" -mindepth 2 -maxdepth 2 -path '*.app/Info.plist' -type f | head -1)"
[ -n "$APP_PLIST" ] || { echo "FAIL: app Info.plist not found inside IPA" >&2; exit 1; }

python3 - "$APP_PLIST" "$EXPECTED_BUNDLE_ID" <<'PY'
import plistlib
import re
import sys
from pathlib import Path

plist_path = Path(sys.argv[1])
expected = sys.argv[2]
data = plistlib.loads(plist_path.read_bytes())
family = data.get("UIDeviceFamily")
name = data.get("CFBundleDisplayName")
identifier = data.get("CFBundleIdentifier")

assert isinstance(family, list), f"UIDeviceFamily is missing or invalid: {family!r}"
assert 2 in family and 1 not in family, f"Expected iPad-only UIDeviceFamily containing 2 and not 1, got {family!r}"
assert name == "Orion Subtitles", f"Unexpected display name: {name!r}"
assert isinstance(identifier, str) and identifier, "CFBundleIdentifier is missing or empty"
assert len(identifier) <= 255, f"CFBundleIdentifier is too long: {len(identifier)} characters"
assert re.fullmatch(r"[A-Za-z0-9]+(?:[.-][A-Za-z0-9]+)+", identifier), f"Invalid Bundle ID syntax: {identifier!r}"
assert identifier == expected, f"Unexpected Bundle ID: {identifier!r}; expected {expected!r}"

print(f"PASS: iPad-only IPA: UIDeviceFamily={family}, name={name}, valid Bundle ID={identifier}")
PY
