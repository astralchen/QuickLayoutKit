#!/bin/sh
set -eu

GRID_TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GRID_TEST_DESTINATION="${GRID_TEST_DESTINATION:-platform=iOS Simulator,name=iPhone 18 Pro}"
GRID_DERIVED_DATA_PATH="${GRID_DERIVED_DATA_PATH:-/private/tmp/QuickLayoutKitDemoDerivedData}"

# Swift Testing 使用命令行套件筛选；当前 Xcode 的 scheme 白名单可能只运行 XCTest。
xcodebuild test \
  -workspace "$GRID_TASK_ROOT/QuickLayoutKit.xcworkspace" \
  -scheme Demo \
  -destination "$GRID_TEST_DESTINATION" \
  -derivedDataPath "$GRID_DERIVED_DATA_PATH" \
  -only-testing:DemoTests/DirectionalGridTests \
  -only-testing:DemoTests/AlignmentGuideTests \
  -only-testing:DemoTests/RTLAlignmentGuideTests \
  -only-testing:DemoTests/StackAdapterTests \
  -only-testing:DemoTests/AlignmentGuidePropagationTests \
  -only-testing:DemoTests/SingleChildStackGuideTests \
  -only-testing:DemoTests/MultiChildStackGuideTests \
  -only-testing:DemoTests/ViewThatFitsGuideTests \
  -only-testing:DemoTests/DirectionalGridPageTests \
  CODE_SIGNING_ALLOWED=NO

xcodebuild test \
  -workspace "$GRID_TASK_ROOT/QuickLayoutKit.xcworkspace" \
  -scheme GridRegression \
  -destination "$GRID_TEST_DESTINATION" \
  -derivedDataPath "$GRID_DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO
