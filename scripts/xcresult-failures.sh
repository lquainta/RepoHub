#!/usr/bin/env bash
# Prints failed tests and their failure messages from an .xcresult bundle.
# Usage: scripts/xcresult-failures.sh path/to/Result.xcresult
set -euo pipefail

bundle="${1:?usage: $0 path/to/Result.xcresult}"
xcrun xcresulttool get test-results tests --path "$bundle" | python3 -c '
import json, sys

def walk(node, path):
    name = node.get("name", "")
    kind = node.get("nodeType", "")
    if kind == "Failure Message":
        print(f"::error title={" > ".join(path)}::{name}")
    for child in node.get("children", []):
        walk(child, path + ([name] if kind in ("Test Suite", "Test Case") else []))

for node in json.load(sys.stdin).get("testNodes", []):
    walk(node, [])
'
