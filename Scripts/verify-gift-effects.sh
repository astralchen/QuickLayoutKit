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
            '-only-testing:DemoTests/DemoTests/voiceRoomGiftFlowSelectsOccupiedRecipientAndCompletesFlight()'
            '-only-testing:DemoTests/DemoTests/voiceRoomGiftCategoriesStayVisibleAndCenterAfterRepeatedDirectionChanges()'
            '-only-testing:DemoTests/DemoTests/voiceRoomGiftQuantityMenuUpdatesCostBalanceAndLayout()'
            '-only-testing:DemoTests/DemoTests/voiceRoomGiftSheetMotionMovesFullyBelowContainer()'
            '-only-testing:DemoTests/DemoTests/voiceRoomGiftSheetFitsIPhoneSEAndCurrentFiveSeatState()'
            '-only-testing:DemoTests/DemoTests/voiceRoomGiftRecipientListScrollsWhenUsersExceedViewport()'
            '-only-testing:DemoTests/DemoTests/voiceRoomGiftSheetAcceptsExternalRecipientSelection()'
            '-only-testing:DemoTests/DemoTests/voiceRoomGiftGridExpandsColumnsInsideIPadContainer()'
            '-only-testing:DemoTests/DemoTests/voiceRoomGiftGridUsesFiveColumnsInsideMediumContainer()'
            '-only-testing:DemoTests/DemoTests/voiceRoomViewModelOwnsMessageGiftAndBalanceBusinessState()'
            '-only-testing:DemoTests/DemoTests/voiceRoomGiftSheetViewModelKeepsSelectionAndSendRules()'
            '-only-testing:DemoTests/DemoTests/voiceRoomGiftRecipientsUpdateByStableUserID()'
)
xcodebuild "${common[@]}" -scheme Demo "${unit_tests[@]}" test

# 这一步实际访问远程素材，并通过真实礼物面板产生截图附件。
xcodebuild "${common[@]}" -scheme VoiceRoomGiftEffects \
    -only-testing:DemoTests/VoiceRoomGiftRemotePlaybackTests \
    -only-testing:DemoTests/GiftEffectPrefetchIntegrationTests \
    -only-testing:DemoUITests/VoiceRoomGiftEffectsUITests test
