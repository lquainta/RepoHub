#!/usr/bin/env bash
# Fails if any localizable string in the app has no Spanish translation (#57).
# New UI text (Text("..."), String(localized:), and so on) is extracted by
# Xcode, so adding text without translating it fails CI.
# Usage: scripts/check-localizations.sh   (after `make generate`)
set -euo pipefail
cd "$(dirname "$0")/.."

out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
xcodebuild -exportLocalizations -project App/RepoHub.xcodeproj -localizationPath "$out" \
    -exportLanguage es -skipPackagePluginValidation >"$out/export.log" 2>&1 \
    || { cat "$out/export.log"; exit 1; }

python3 - "$out/es.xcloc/Localized Contents/es.xliff" <<'PY'
import sys, xml.etree.ElementTree as ET
ns = "{urn:oasis:names:tc:xliff:document:1.2}"
missing = []
total = 0
for unit in ET.parse(sys.argv[1]).getroot().iter(ns + "trans-unit"):
    total += 1
    target = unit.find(ns + "target")
    if target is None or not (target.text or "").strip() or target.get("state") in ("new", "needs-translation"):
        missing.append(unit.get("id"))
for key in missing:
    print(f"::error file=App/Sources/RepoHub/Localizable.xcstrings::No Spanish translation for \"{key}\"")
if missing:
    sys.exit(f"{len(missing)} of {total} strings need a Spanish translation. Add them in Localizable.xcstrings.")
print(f"All {total} strings are translated into Spanish.")
PY
