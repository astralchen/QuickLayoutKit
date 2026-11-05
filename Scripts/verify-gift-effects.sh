#!/bin/bash
set -euo pipefail

TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# 默认使用模拟器；可传入 xcodebuild 参数指定真机和开发团队。
common=(-project "$TASK_ROOT/Demo/Demo.xcodeproj"
        -derivedDataPath "${GIFT_EFFECTS_DERIVED_DATA:-/private/tmp/QuickLayoutGiftEffects}"
        -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile -parallel-testing-enabled NO
        -collect-test-diagnostics never)
if (( $# )); then
    common+=("$@")
else
    common+=(-destination 'platform=iOS Simulator,name=iPhone 18 Pro' CODE_SIGNING_ALLOWED=NO)
fi

# Swift Testing 使用命令行筛选，避免与 XCTest 的 scheme 标识解析混淆。
unit_tests=(-only-testing:DemoTests/TaskQueueTests
            -only-testing:DemoTests/SerialTaskQueueTests
            -only-testing:DemoTests/WithTaskTimeoutTests
            -only-testing:DemoTests/WithTaskRetryTests
            -only-testing:DemoTests/GiftPlaybackOperationTests
            -only-testing:DemoTests/GiftEffectPrefetcherTests
            -only-testing:DemoTests/VoiceRoomGiftMainEffectTests
            -only-testing:DemoTests/SeatStageTransitionTests
            '-only-testing:DemoTests/ApplicationTests/voiceRoomGiftFlowSelectsOccupiedRecipientAndCompletesFlight()'
            '-only-testing:DemoTests/ApplicationTests/voiceRoomGiftCategoriesStayVisibleAndCenterAfterRepeatedDirectionChanges()'
            '-only-testing:DemoTests/ApplicationTests/voiceRoomGiftQuantityMenuUpdatesCostBalanceAndLayout()'
            '-only-testing:DemoTests/ApplicationTests/voiceRoomGiftSheetMotionMovesFullyBelowContainer()'
            '-only-testing:DemoTests/ApplicationTests/voiceRoomGiftSheetFitsIPhoneSEAndCurrentFiveSeatState()'
            '-only-testing:DemoTests/ApplicationTests/voiceRoomGiftRecipientListScrollsWhenUsersExceedViewport()'
            '-only-testing:DemoTests/ApplicationTests/voiceRoomGiftSheetAcceptsExternalRecipientSelection()'
            '-only-testing:DemoTests/ApplicationTests/voiceRoomGiftGridExpandsColumnsInsideIPadContainer()'
            '-only-testing:DemoTests/ApplicationTests/voiceRoomGiftGridUsesFiveColumnsInsideMediumContainer()'
            '-only-testing:DemoTests/ApplicationTests/voiceRoomViewModelOwnsMessageGiftAndBalanceBusinessState()'
            '-only-testing:DemoTests/ApplicationTests/voiceRoomGiftSheetViewModelKeepsSelectionAndSendRules()'
            '-only-testing:DemoTests/ApplicationTests/voiceRoomGiftRecipientsUpdateByStableUserID()'
)
xcodebuild "${common[@]}" -scheme Demo "${unit_tests[@]}" test

# 这一步实际访问远程素材，并通过真实礼物面板产生截图附件。
xcodebuild "${common[@]}" -scheme VoiceRoomGiftEffects \
    -only-testing:DemoTests/VoiceRoomGiftRemotePlaybackTests \
    -only-testing:DemoTests/GiftEffectPrefetchIntegrationTests \
    -only-testing:DemoUITests/VoiceRoomGiftEffectsUITests test
