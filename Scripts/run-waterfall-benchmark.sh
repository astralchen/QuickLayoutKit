#!/bin/bash
# Usage: bash Scripts/run-waterfall-benchmark.sh SIMULATOR_UDID [OUTPUT_DIRECTORY]
# Optional: DEVELOPER_DIR, WATERFALL_PACKAGE_CACHE (existing SourcePackages directory),
# WATERFALL_PREBUILT_PRODUCTS (matching simulator products; enables an isolated test host).
# WATERFALL_BASELINE_REV (historical layout revision; requires isolated host).
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TASK_DEVICE="${1:?Pass an available iOS simulator UDID}"
TASK_OUTPUT="${2:-/private/tmp/waterfall-benchmark}"
mkdir -p "$TASK_OUTPUT"
TASK_OUTPUT="$(cd "$TASK_OUTPUT" && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
if [[ -n "${WATERFALL_BASELINE_REV:-}" && -z "${WATERFALL_PREBUILT_PRODUCTS:-}" ]]; then
    echo 'WATERFALL_BASELINE_REV requires WATERFALL_PREBUILT_PRODUCTS' >&2
    exit 1
fi
TASK_PACKAGE_ARGS=()
TASK_PROJECT="$TASK_ROOT/Demo/Demo.xcodeproj"
TASK_BUNDLE_ID=com.sondra.Demo
TASK_BUILD_DESCRIPTION='Release, ENABLE_TESTABILITY=YES'
if [[ -n "${WATERFALL_PACKAGE_CACHE:-}" ]]; then
    TASK_PACKAGE_ARGS=(-clonedSourcePackagesDirPath "$WATERFALL_PACKAGE_CACHE" -disableAutomaticPackageResolution -skipPackageUpdates)
fi
if [[ -n "${WATERFALL_PREBUILT_PRODUCTS:-}" ]]; then
    TASK_PROJECT="$(python3 "$TASK_ROOT/Scripts/make-waterfall-benchmark-project.py" "$TASK_ROOT" "$TASK_OUTPUT/Host" "$WATERFALL_PREBUILT_PRODUCTS")"
    TASK_PACKAGE_ARGS=()
    TASK_BUNDLE_ID=com.sondra.WaterfallBenchmark
    TASK_BUILD_DESCRIPTION='Release (-O) original layout and tests; isolated UIKit host; prebuilt QuickLayout dependencies'
fi
xcrun simctl bootstatus "$TASK_DEVICE" -b
xcodebuild build-for-testing -project "$TASK_PROJECT" -scheme Demo \
    -configuration Release -destination "platform=iOS Simulator,id=$TASK_DEVICE" \
    -derivedDataPath "$TASK_OUTPUT/DerivedData" ${TASK_PACKAGE_ARGS[@]+"${TASK_PACKAGE_ARGS[@]}"} \
    -only-testing:DemoTests/WaterfallLayoutPerformanceTests -only-testing:DemoTests/WaterfallLayoutEngineTests \
    ENABLE_TESTABILITY=YES CODE_SIGNING_ALLOWED=NO > "$TASK_OUTPUT/build.log" 2>&1
# Keep the generated file in Products: __TESTROOT__ paths are relative to its location.
TASK_RUN_ID="$(date +%Y%m%d-%H%M%S)-$$"
TASK_RUN="$(python3 - "$TASK_OUTPUT/DerivedData/Build/Products" "$TASK_RUN_ID" <<'PY'
import pathlib, plistlib, sys
paths = list(pathlib.Path(sys.argv[1]).glob('*.xctestrun'))
assert len(paths) == 1, paths
path = paths[0]
data = plistlib.loads(path.read_bytes())
targets = [v for k, v in data.items() if isinstance(v, dict) and not k.startswith('__')]
for configuration in data.get('TestConfigurations', []):
    targets.extend(configuration.get('TestTargets', []))
for target in targets:
    target.setdefault('EnvironmentVariables', {})['WATERFALL_BENCHMARK'] = '1'
    target['EnvironmentVariables']['WATERFALL_BENCHMARK_RUN_ID'] = sys.argv[2]
path.write_bytes(plistlib.dumps(data))
print(path)
PY
)"
TASK_RESULT="$TASK_OUTPUT/Run-$(date +%Y%m%d-%H%M%S).xcresult"
xcodebuild test-without-building -xctestrun "$TASK_RUN" \
    -destination "platform=iOS Simulator,id=$TASK_DEVICE" \
    -only-testing:DemoTests/WaterfallLayoutPerformanceTests -only-testing:DemoTests/WaterfallLayoutEngineTests \
    -parallel-testing-enabled NO -resultBundlePath "$TASK_RESULT" > "$TASK_OUTPUT/test.log" 2>&1
TASK_CONTAINER="$(xcrun simctl get_app_container "$TASK_DEVICE" "$TASK_BUNDLE_ID" data)"
cp "$TASK_CONTAINER/Documents/waterfall-benchmark.json" "$TASK_OUTPUT/results.json"
cp "$TASK_CONTAINER/Documents/waterfall-head.json" "$TASK_OUTPUT/head.json"
if [[ -z "${WATERFALL_BASELINE_REV:-}" ]]; then
    cp "$TASK_CONTAINER/Documents/waterfall-scalability.json" "$TASK_OUTPUT/scalability.json"
fi
python3 - "$TASK_OUTPUT/results.json" "$TASK_RUN_ID" "$TASK_ROOT" "$TASK_BUILD_DESCRIPTION" <<'PY'
import datetime, hashlib, json, os, pathlib, subprocess, sys
path, run_id, root = pathlib.Path(sys.argv[1]), sys.argv[2], pathlib.Path(sys.argv[3])
data = json.loads(path.read_text())
assert data['run_id'] == run_id, 'Results are stale or the opt-in test did not execute'
source_path = 'Sources/QuickLayoutKit/QuickLayoutKitUIKit/UICollectionViewWaterfallLayout.swift'
revision = os.environ.get('WATERFALL_BASELINE_REV')
source = subprocess.check_output(['git', '-C', str(root), 'show', revision + ':Demo/Demo/Features/ContentConfiguration/ContentConfigurationWaterfallLayout.swift']) if revision else (root / source_path).read_bytes()
data['layout_sha256'] = hashlib.sha256(source).hexdigest()
data['baseline_revision'] = revision
data['git_head'] = subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip()
data['captured_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
data['configuration'] = sys.argv[4]
path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + '\n')
for name in (['head.json'] if revision else ['head.json', 'scalability.json']):
    artifact_path = path.with_name(name)
    artifact = json.loads(artifact_path.read_text())
    assert artifact['run_id'] == run_id, 'Results are stale: ' + name
    for key in ['layout_sha256', 'git_head', 'captured_utc', 'configuration', 'baseline_revision']:
        artifact[key] = data[key]
    artifact_path.write_text(json.dumps(artifact, indent=2, ensure_ascii=False) + '\n')
PY
echo "Benchmark JSON: $TASK_OUTPUT/results.json"
echo "XCTest result: $TASK_RESULT"
