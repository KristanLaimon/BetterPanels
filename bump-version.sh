#!/usr/bin/env bash
# Update the release version used by KOReader and the ZenPM repository manifest.
set -euo pipefail

usage() {
    echo "Usage: $0 <version>" >&2
    echo "Example: $0 1.4.1" >&2
    echo "An optional leading v is accepted." >&2
    exit 2
}

if [[ $# -ne 1 ]]; then
    usage
fi

VERSION="${1#v}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z][0-9A-Za-z.-]*)?$ ]]; then
    echo "Error: version must look like 1.4.1 or 1.4.1-rc.1." >&2
    exit 2
fi

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

python3 - "$VERSION" "$SCRIPT_DIR/_meta.lua" "$SCRIPT_DIR/manifest.json" <<'PY'
import json
import re
import sys
from pathlib import Path

version, metadata_path, manifest_path = map(Path, sys.argv[1:])
version = str(version)

metadata = metadata_path.read_text(encoding="utf-8")
updated_metadata, metadata_count = re.subn(
    r'(\n\s*version\s*=\s*")[^"]+("\s*,)',
    rf'\g<1>{version}\g<2>',
    metadata,
    count=1,
)
if metadata_count != 1:
    raise SystemExit(f"Could not find exactly one plugin version in {metadata_path}.")

manifest = manifest_path.read_text(encoding="utf-8")
json.loads(manifest)
updated_manifest, manifest_count = re.subn(
    r'("id"\s*:\s*"panels-plus",\s*"name"\s*:\s*"Panels\+",\s*"version"\s*:\s*")[^"]+("\s*,)',
    rf'\g<1>{version}\g<2>',
    manifest,
    count=1,
)
if manifest_count != 1:
    raise SystemExit(f"Could not find the Panels+ package version in {manifest_path}.")

parsed_manifest = json.loads(updated_manifest)
package = next((item for item in parsed_manifest["packages"] if item["id"] == "panels-plus"), None)
if package is None or package["version"] != version:
    raise SystemExit("Manifest validation failed after updating the version.")

metadata_path.write_text(updated_metadata, encoding="utf-8")
manifest_path.write_text(updated_manifest, encoding="utf-8")
print(f"Updated Panels+ release version to {version}.")
PY
