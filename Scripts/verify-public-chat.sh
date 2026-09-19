#!/bin/bash
set -euo pipefail

TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DESTINATION="${1:?Usage: verify-public-chat.sh 'platform=iOS Simulator,id=SIMULATOR_ID'}"
COMMON=(-workspace "$TASK_ROOT/QuickLayoutKit.xcworkspace" -destination "$DESTINATION"
    -disableAutomaticPackageResolution -enableCodeCoverage NO -parallel-testing-enabled NO
    CODE_SIGNING_ALLOWED=NO)
if [[ -n "${QUICKLAYOUT_DERIVED_DATA:-}" ]]; then
    COMMON+=(-derivedDataPath "$QUICKLAYOUT_DERIVED_DATA")
fi

# Xcode 的旧式 scheme 白名单在部分版本下不执行 Swift Testing。
# 使用 Demo scheme 和带参数括号的完整函数签名显式筛选，保留原房间回归范围。
SELECTORS=()
while IFS= read -r identifier; do
    SELECTORS+=("-only-testing:DemoTests/$identifier")
done < <(python3 - "$TASK_ROOT" <<'PY'
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
scheme = Path(sys.argv[1]) / 'Demo/Demo.xcodeproj/xcshareddata/xcschemes/RoomPK.xcscheme'
for target in ET.parse(scheme).findall('./TestAction/Testables/TestableReference'):
    if target.find('BuildableReference').get('BlueprintName') == 'DemoTests':
        for test in target.findall('./SelectedTests/Test'):
            print(test.get('Identifier'))
PY
)
[[ ${#SELECTORS[@]} -gt 0 ]]
SELECTORS+=(
    '-only-testing:DemoTests/DemoTests/followButtonKeepsSizeAcrossStates(locale:)'
    '-only-testing:DemoTests/DemoTests/followButtonInterruptionsAndReducedMotionSettleCorrectly()'
    '-only-testing:DemoTests/DemoTests/followButtonRestoresConfirmedStateAfterFailure(initiallyFollowing:)'
    '-only-testing:DemoTests/DemoTests/publicChatCommitsTextAndGiftsOnlyAfterValidation()'
    '-only-testing:DemoTests/DemoTests/publicChatPresentationLocalizesWithoutChangingMessageIdentity()'
    '-only-testing:DemoTests/DemoTests/publicChatPreservesReadingPositionAndCountsOnlyNewIDs()'
    '-only-testing:DemoTests/DemoTests/publicChatEmptyShortAndLongMessagesFitAvailableWidth()'
    '-only-testing:DemoTests/DemoTests/publicChatAdaptsToNarrowLargeTypeAndRTL(locale:)'
)
RESULT_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/QuickLayoutPublicChat.XXXXXX")"
verify_nonempty_result() {
    xcrun xcresulttool get test-results summary --path "$1" | python3 -c '
import json, sys
report = json.load(sys.stdin)
count = report.get("passedTests", 0) + report.get("failedTests", 0)
if count == 0:
    raise SystemExit("No tests executed; check Swift Testing identifiers and scheme selection.")
print(f"Verified {count} executed tests.")
'
}
xcodebuild "${COMMON[@]}" -scheme Demo "${SELECTORS[@]}" \
    -resultBundlePath "$RESULT_ROOT/Unit.xcresult" test
verify_nonempty_result "$RESULT_ROOT/Unit.xcresult"
xcodebuild "${COMMON[@]}" -scheme RoomPK \
    -only-testing:DemoUITests/RoomPublicChatUITests \
    -only-testing:DemoUITests/RoomPKUITests/testPKKeyboardKeepsSeatsAndInputVisible \
    -resultBundlePath "$RESULT_ROOT/UI.xcresult" test
verify_nonempty_result "$RESULT_ROOT/UI.xcresult"
printf 'Public chat verification results: %s\n' "$RESULT_ROOT"
