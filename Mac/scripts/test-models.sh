#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

swiftc \
    "$ROOT/Mac/Sources/MoveMouseMac/Models.swift" \
    "$ROOT/Mac/Tests/MoveMouseMacTests/ModelTests.swift" \
    -o "$TEMP_DIR/model-tests"
"$TEMP_DIR/model-tests"
