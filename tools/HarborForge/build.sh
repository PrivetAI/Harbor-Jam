#!/bin/bash
# Compile HarborForge against the REAL, unmodified app sources. No Xcode project,
# no test target. The whole point is that the harness measures the simulation the
# app actually ships — a separate copy of the rules would measure nothing.
set -euo pipefail

TOOL_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$(cd "$TOOL_DIR/../../Quaylock" && pwd)"
OUT="$TOOL_DIR/harborforge"

# These three files import Foundation only, which is what makes this possible.
# Adding a SwiftUI or UIKit import to any of them breaks the harness.
APP_SOURCES=(
  "$APP_DIR/QLSimModel.swift"
  "$APP_DIR/QLSim.swift"
  "$APP_DIR/QLShiftCatalog.swift"
)

TOOL_SOURCES=()
for f in "$TOOL_DIR"/*.swift; do TOOL_SOURCES+=("$f"); done

swiftc -O -swift-version 5 \
  -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
  -o "$OUT" "${APP_SOURCES[@]}" "${TOOL_SOURCES[@]}"

echo "built: $OUT"
