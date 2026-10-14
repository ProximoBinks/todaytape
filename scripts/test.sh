#!/bin/bash
# Runs Todaytape's self-checking tests: the app's model code compiled with the
# test file as its entry point. No Xcode or XCTest needed, only Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${TMPDIR:-/tmp}/todaytape-tests"
mkdir -p "$OUT"

swiftc -O -swift-version 5 \
  -module-name TodaytapeTests \
  -o "$OUT/run" \
  Sources/Todaytape/CalendarColor.swift \
  Sources/Todaytape/Color+Hex.swift \
  Sources/Todaytape/Config.swift \
  Sources/Todaytape/Models.swift \
  Sources/Todaytape/GoogleAuth.swift \
  Tests/TodaytapeTests/CalendarColorTests.swift

"$OUT/run"
