#!/bin/sh
set -eu

TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

xcodebuild \
  -workspace "$TASK_ROOT/QuickLayoutKit.xcworkspace" \
  -scheme Demo \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/QuickLayoutKitDemoDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
