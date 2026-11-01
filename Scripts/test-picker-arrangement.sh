#!/bin/bash
set -eu
cd "$(dirname "$0")/.."
swift build --package-path Packages/PasteupCore >/dev/null
mkdir -p .tmp
swiftc -parse-as-library -swift-version 6 -default-isolation MainActor \
  -I Packages/PasteupCore/.build/debug/Modules \
  Packages/PasteupCore/.build/debug/PasteupCore.build/*.swift.o \
  Pasteup/UI/PickerArrangement.swift Tests/PickerArrangementChecks.swift \
  -o .tmp/picker-arrangement-checks
.tmp/picker-arrangement-checks
