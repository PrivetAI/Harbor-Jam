#!/bin/bash
# Compile HarborForge against the REAL, unmodified app sources. No Xcode project, no test target.
set -euo pipefail

TOOL_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$(cd "$TOOL_DIR/../../Harbor Jam" && pwd)"
OUT="$TOOL_DIR/harborforge"

# HJGenerator.swift is dropped from this list when on-device generation is deleted.
APP_SOURCES=(
  "$APP_DIR/HJModels.swift"
  "$APP_DIR/HJEngine.swift"
  "$APP_DIR/HJGenerator.swift"
)

TOOL_SOURCES=()
for f in "$TOOL_DIR"/*.swift; do TOOL_SOURCES+=("$f"); done

# -swift-version 5: HJGenerator.swift:47 holds a mutable static cache, which Swift 6 rejects.
swiftc -O -swift-version 5 \
  -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
  -o "$OUT" "${APP_SOURCES[@]}" "${TOOL_SOURCES[@]}"

echo "built: $OUT"
