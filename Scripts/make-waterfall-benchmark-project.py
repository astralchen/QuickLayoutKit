"""Generate an isolated UIKit test host, linking previously built QuickLayout objects.

The original layout and benchmark source files are referenced directly, without rewriting.
Usage: python3 make-waterfall-benchmark-project.py REPO_ROOT OUTPUT_DIR PREBUILT_PRODUCTS
"""
import json
import os
import subprocess
import pathlib
import sys

root, output, products = (pathlib.Path(p).resolve() for p in sys.argv[1:])
output.mkdir(parents=True, exist_ok=True)
objects = [products / f"{name}.o" for name in ("QuickLayout", "QuickLayoutCore", "QuickLayoutBridge", "FastResultBuilder")]
assert all(p.exists() for p in objects), "Build the Demo once for this simulator architecture to populate QuickLayout objects"
app = output / "App.swift"
app.write_text('''import UIKit
@main final class BenchmarkApp: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}
''')
project = output / "Benchmark.xcodeproj"
project.mkdir(exist_ok=True)
q = lambda value: json.dumps(str(value))
identifier = lambda n: f"{n:024X}"
entries = {}
def add(n, body):
    entries[identifier(n)] = "{ " + body + " };"
def ref(n):
    return identifier(n)
def settings(values):
    return "{ " + " ".join(f"{k} = {v};" for k, v in values.items()) + " }"

layout_path = root / "Sources/QuickLayoutKit/QuickLayoutKitUIKit/UICollectionViewWaterfallLayout.swift"
performance_path = root / "Demo/DemoTests/WaterfallLayoutPerformanceTests.swift"
engine_path = root / "Demo/DemoTests/WaterfallLayoutEngineTests.swift"
if revision := os.environ.get("WATERFALL_BASELINE_REV"):
    original = subprocess.check_output(["git", "-C", str(root), "show", revision + ":Demo/Demo/Features/ContentConfiguration/ContentConfigurationWaterfallLayout.swift"])
    layout_path = output / "BaselineLayout.swift"
    layout_path.write_bytes(original)
    performance = performance_path.read_text().replace("UICollectionViewWaterfallLayout", "ContentConfigurationWaterfallLayout").replace("section.lanes = Array(repeating: .flexible(), count: 2)", "section.laneCount = 2")
    performance_path = output / "BaselineTests.swift"
    performance_path.write_text(performance)
    engine_path = output / "EngineTests.swift"
    engine_path.write_text("// New engine APIs are unavailable in the historical baseline.\n")
for n, path in [(10, app), (11, layout_path), (12, performance_path), (15, engine_path), (16, root / "Sources/QuickLayoutKit/QuickLayoutKitUIKit/QuickLayoutDiagnostics.swift")]:
    add(n, f"isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {q(path)}; sourceTree = \"<absolute>\";")
    add(n + 10, f"isa = PBXBuildFile; fileRef = {ref(n)};")
add(13, 'isa = PBXFileReference; explicitFileType = wrapper.application; path = Demo.app; sourceTree = BUILT_PRODUCTS_DIR;')
add(14, 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = DemoTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
add(2, f'isa = PBXGroup; children = ({ref(10)}, {ref(11)}, {ref(12)}, {ref(15)}, {ref(16)}, {ref(3)}); sourceTree = "<group>";')
add(3, f'isa = PBXGroup; name = Products; children = ({ref(13)}, {ref(14)}); sourceTree = "<group>";')
add(30, f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({ref(20)}, {ref(21)}, {ref(26)}); runOnlyForDeploymentPostprocessing = 0;')
add(31, f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({ref(22)}, {ref(25)}); runOnlyForDeploymentPostprocessing = 0;')
for n in (32, 33):
    add(n, 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
add(42, f'isa = PBXContainerItemProxy; containerPortal = {ref(1)}; proxyType = 1; remoteGlobalIDString = {ref(40)}; remoteInfo = Demo;')
add(43, f'isa = PBXTargetDependency; target = {ref(40)}; targetProxy = {ref(42)};')
add(40, f'isa = PBXNativeTarget; name = Demo; productName = Demo; productReference = {ref(13)}; productType = "com.apple.product-type.application"; buildConfigurationList = {ref(51)}; buildPhases = ({ref(30)}, {ref(32)}); buildRules = (); dependencies = ();')
add(41, f'isa = PBXNativeTarget; name = DemoTests; productName = DemoTests; productReference = {ref(14)}; productType = "com.apple.product-type.bundle.unit-test"; buildConfigurationList = {ref(52)}; buildPhases = ({ref(31)}, {ref(33)}); buildRules = (); dependencies = ({ref(43)});')
common = dict(SDKROOT='iphonesimulator', IPHONEOS_DEPLOYMENT_TARGET='17.0', SWIFT_VERSION='5.0', SWIFT_OPTIMIZATION_LEVEL=q('-O'), SWIFT_COMPILATION_MODE='wholemodule', ENABLE_TESTABILITY='YES', ONLY_ACTIVE_ARCH='YES', CLANG_ENABLE_MODULES='YES', CODE_SIGNING_ALLOWED='NO', GENERATE_INFOPLIST_FILE='YES', TARGETED_DEVICE_FAMILY=q('1,2'), SWIFT_INCLUDE_PATHS=q(products), LD_RUNPATH_SEARCH_PATHS=q('$(inherited) @executable_path/Frameworks @loader_path/Frameworks'))
app_settings = dict(PRODUCT_NAME=q('$(TARGET_NAME)'), PRODUCT_BUNDLE_IDENTIFIER=q('com.sondra.WaterfallBenchmark'), OTHER_LDFLAGS='(' + ', '.join(q(p) for p in objects) + ')', INFOPLIST_KEY_UILaunchScreen_Generation='YES')
test_settings = dict(SWIFT_ACTIVE_COMPILATION_CONDITIONS=q('WATERFALL_STANDALONE_HOST'), PRODUCT_NAME=q('$(TARGET_NAME)'), PRODUCT_BUNDLE_IDENTIFIER=q('com.sondra.WaterfallBenchmarkTests'), TEST_HOST=q('$(BUILT_PRODUCTS_DIR)/Demo.app/Demo'), BUNDLE_LOADER=q('$(TEST_HOST)'))
for config, values in [(60, common), (61, app_settings), (62, test_settings)]:
    add(config, f'isa = XCBuildConfiguration; name = Release; buildSettings = {settings(values)};')
    add(config - 10, f'isa = XCConfigurationList; buildConfigurations = ({ref(config)}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
add(1, f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2630; }}; buildConfigurationList = {ref(50)}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; knownRegions = (en, Base); mainGroup = {ref(2)}; productRefGroup = {ref(3)}; projectDirPath = ""; projectRoot = ""; targets = ({ref(40)}, {ref(41)});')
(project / 'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + '\n'.join(f'{k} = {v}' for k, v in entries.items()) + f'\n}}; rootObject = {ref(1)}; }}\n')
scheme = project / 'xcshareddata/xcschemes/Demo.xcscheme'
scheme.parent.mkdir(parents=True, exist_ok=True)
def buildable(n, name):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ref(n)}" BuildableName="{name}" BlueprintName="{name.split(".")[0]}" ReferencedContainer="container:Benchmark.xcodeproj"/>'
scheme.write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2630" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
    <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="NO" buildForAnalyzing="YES">{buildable(40, "Demo.app")}</BuildActionEntry>
  </BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Release" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{buildable(41, "DemoTests.xctest")}</TestableReference></Testables></TestAction>
  <LaunchAction buildConfiguration="Release" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable(40, "Demo.app")}</BuildableProductRunnable></LaunchAction>
</Scheme>
''')
print(project)
