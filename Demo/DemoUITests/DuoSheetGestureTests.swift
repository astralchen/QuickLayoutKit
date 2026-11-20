import XCTest

@MainActor
final class DuoSheetGestureTests: XCTestCase {
    private struct Reading: Decodable {
        let pose: String
        let detent: String
        let geometry: [CGFloat] // 前页四侧间距及四角、叠放时的下层四角和双轴比例、后页窗口坐标
        let windowSize: [CGFloat]
        let samples: [[CGFloat]]
    }

    /// 同一触摸序列在不同控制器中采样帧数不同，按面板顶边位置比较。
    private func interpolate(_ samples: [[CGFloat]], at top: CGFloat) -> [CGFloat]? {
        for (a, b) in zip(samples, samples.dropFirst()) where a[1] != b[1] {
            guard (min(a[1], b[1])...max(a[1], b[1])).contains(top) else { continue }
            let t = (top - a[1]) / (b[1] - a[1])
            return zip(a, b).map { $0 + ($1 - $0) * t }
        }
        return nil
    }

    func testPresentingPageDuringDragsAndRotation() throws {
        try comparePresenter(stacked: false, orientations: [.portrait, .landscapeLeft])
    }

    func testRotatingOpenLargeSheet() throws {
        guard #available(iOS 17, *), UIDevice.current.userInterfaceIdiom == .phone else { throw XCTSkip("iPhone") }
        let device = XCUIDevice.shared
        let original = device.orientation
        defer { device.orientation = original }
        device.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-duo-sheet-gestures", "-test-initial-large"]
        app.launch()
        let reading = app.buttons["gesture.reading"]
        var native: [[CGFloat]] = []
        for engine in ["UIKit", "Sheet", "Panel"] {
            app.buttons[engine].tap()
            XCTAssertTrue(reading.waitForExistence(timeout: 5))
            for (step, orientation) in [UIDeviceOrientation.portrait, .landscapeLeft, .portrait].enumerated() {
                device.orientation = orientation
                let window = app.windows.firstMatch.frame
                XCTAssertEqual(window.width > window.height, orientation.isLandscape)
                let data = Data(try XCTUnwrap(reading.value as? String).utf8)
                let value = try JSONDecoder().decode(Reading.self, from: data)
                XCTAssertEqual(value.detent, "large")
                let frame = Array(value.geometry.suffix(4))
                print("PRESENTER_ROTATION", engine, step, window, frame)
                if engine == "UIKit" { native.append(frame) }
                else { for (a,b) in zip(frame, native[step]) { XCTAssertEqual(a,b,accuracy: 1) } }
            }
            reading.tap()
            XCTAssertTrue(reading.waitForNonExistence(timeout: 5))
        }
    }

    func testStackedPresentingPageDuringDrags() throws {
        try comparePresenter(stacked: true, orientations: [.portrait])
    }

    private func comparePresenter(stacked: Bool, orientations: [UIDeviceOrientation]) throws {
        guard #available(iOS 17, *), UIDevice.current.userInterfaceIdiom == .phone else { throw XCTSkip("iPhone") }
        let device = XCUIDevice.shared
        let original = device.orientation
        defer { device.orientation = original }
        let app = XCUIApplication()
        app.launchArguments = ["-duo-sheet-gestures"]
        if stacked { app.launchArguments.append("-test-stacked-sheet") }
        for orientation in orientations {
            device.orientation = orientation
            app.launch()
            let button = app.buttons["gesture.reading"]
            func read() throws -> Reading {
                try JSONDecoder().decode(Reading.self, from: Data(try XCTUnwrap(button.value as? String).utf8))
            }
            var reference: [Reading] = []
            for engine in ["UIKit", "Sheet", "Panel"] {
                app.buttons[engine].tap()
                XCTAssertTrue(button.waitForExistence(timeout: 6))
                let window = app.windows.firstMatch.frame
                let initial = try read()
                let compact = orientation.isLandscape
                let targets = compact ? ["large", "third"] : ["medium", "large", "medium", "third"]
                var previous = initial
                for (i, target) in targets.enumerated() {
                    let up = target == "large" || target == "medium" && previous.detent == "third"
                    let far = target == "large" || previous.detent == "large"
                    let distance = window.height * (compact ? 0.62 : far ? 0.44 : 0.22)
                    let y = previous.geometry[1] + 50
                    let dy = min(window.height - 20, max(16, y + (up ? -distance : distance))) - y
                    let anchor = button.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5))
                    let start = anchor.withOffset(.init(dx: 0, dy: y - button.frame.midY))
                    start.press(forDuration: 0.15, thenDragTo: start.withOffset(.init(dx: 0, dy: dy)),
                                withVelocity: .init(rawValue: 360), thenHoldForDuration: 0.3)
                    let value = try read()
                    let samples = Array(value.samples.dropFirst(previous.samples.count))
                    print("PAGE_TOUCH", engine, orientation.rawValue, target, value.detent, value.geometry, samples.map { [$0[1]] + Array($0.suffix(4)) })
                    if target == "large" && orientation == .portrait {
                        let image = XCTAttachment(screenshot: app.screenshot())
                        image.name = "presenter-\(stacked ? "stack" : "root")-\(engine)-large"
                        image.lifetime = .keepAlways
                        add(image)
                    }
                    XCTAssertEqual(value.detent, target)
                    XCTAssertGreaterThan(samples.count, 2)
                    if engine == "UIKit" { reference.append(value) }
                    else {
                        let native = reference[i]
                        for (a,b) in zip(value.geometry.suffix(4), native.geometry.suffix(4)) { XCTAssertEqual(a, b, accuracy: 1) }
                        let base = i == 0 ? initial : reference[i - 1]
                        for t: CGFloat in [0.25, 0.5, 0.75] {
                            let top = base.geometry[1] + (native.geometry[1] - base.geometry[1]) * t
                            let a = try XCTUnwrap(interpolate(samples, at: top))
                            let b = try XCTUnwrap(interpolate(Array(native.samples.dropFirst(i == 0 ? 0 : base.samples.count)), at: top))
                            for (x,y) in zip(a.suffix(4), b.suffix(4)) { XCTAssertEqual(x, y, accuracy: 2) }
                        }
                    }
                    previous = value
                }
                button.tap()
                XCTAssertTrue(button.waitForNonExistence(timeout: 5))
            }
        }
    }

    func testPresentingPageInResizedPadWindow() throws {
        guard #available(iOS 26, *), UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("Windowed iPad") }
        let app = XCUIApplication()
        for form in [false, true] {
            app.launchArguments = ["-duo-sheet-gestures", "-test-initial-large"] + (form ? ["-test-form-sizing"] : [])
            app.launch()
            let window = app.windows.firstMatch
            let button = app.buttons["gesture.reading"]
            let original = window.frame
            let delta = CGVector(dx: original.width < 650 ? 150 : -180, dy: original.height < 600 ? 110 : -145)
            func resize(_ vector: CGVector) {
                let corner = window.coordinate(withNormalizedOffset: .init(dx: 1, dy: 1)).withOffset(.init(dx: -9, dy: -10))
                corner.press(forDuration: 0.5, thenDragTo: corner.withOffset(vector))
            }
            // 在同一个打开的大档内拖动系统窗口把手。窗口管理器可能为每一轮选择不同吸附尺寸，
            // 因此比较后页相对于当前窗口的四侧距离。
            var reference: [[CGFloat]] = []
            for engine in ["UIKit", "Sheet", "Panel"] {
                app.buttons[engine].tap()
                XCTAssertTrue(button.waitForExistence(timeout: 5))
                let start = window.frame
                for (step, state) in ["initial", "resized"].enumerated() {
                    if step == 1 {
                        resize(delta)
                        XCTAssertGreaterThan(abs(window.frame.width - start.width) + abs(window.frame.height - start.height), 40)
                    }
                    let data = Data(try XCTUnwrap(button.value as? String).utf8)
                    let value = try JSONDecoder().decode(Reading.self, from: data)
                    XCTAssertEqual(value.detent, "large")
                    let back = Array(value.geometry.suffix(4))
                    let gaps = [back[0], back[1], value.windowSize[0] - back[0] - back[2], value.windowSize[1] - back[1] - back[3]]
                    print("PAD_PRESENTER", state, form, engine, window.frame, back)
                    if engine == "UIKit" { reference.append(gaps) }
                    else { for (a,b) in zip(gaps, reference[step]) { XCTAssertEqual(a, b, accuracy: 1) } }
                }
                button.tap()
                XCTAssertTrue(button.waitForNonExistence(timeout: 5))
                resize(.init(dx: -delta.dx, dy: -delta.dy))
            }
        }
    }

    func testDetentDragsInDevicePoses() throws {
        try compareDevicePoses(stacked: false)
    }

    func testStackedDetentDragsInDevicePoses() throws {
        try compareDevicePoses(stacked: true)
    }

    func testDragsAboveShortSheetInDevicePoses() throws {
        try compareDevicePoses(stacked: true, shortLower: true)
    }

    private func compareDevicePoses(stacked: Bool, shortLower: Bool = false) throws {
        let environment = ProcessInfo.processInfo.environment
        guard let poses = environment["DUO_GESTURE_POSES"] else { throw XCTSkip("Requires the Device Hub pose driver") }
        let requested = poses.components(separatedBy: ",")
        let app = XCUIApplication()
        app.launchArguments = ["-duo-sheet-gestures"]
        if stacked { app.launchArguments += ["-test-stacked-sheet", "-measure-lower-sheet"] }
        if shortLower { app.launchArguments.append("-test-short-lower") }
        app.launchEnvironment["DUO_DIM_THRESHOLD"] = environment["DUO_DIM_THRESHOLD"]
        app.launchEnvironment["DUO_CORNER_RADIUS"] = environment["DUO_CORNER_RADIUS"]
        app.launch()
        let label = app.staticTexts["gesture.pose"]
        let button = app.buttons["gesture.reading"]
        func read() throws -> Reading {
            let value = try XCTUnwrap(button.value as? String)
            return try JSONDecoder().decode(Reading.self, from: Data(value.utf8))
        }
        func compare(_ actual: [CGFloat], _ expected: [CGFloat], _ label: String, lowerOnly: Bool = false) {
            let scaleIndices = lowerOnly ? 8..<10 : 12..<14
            XCTAssertEqual(actual.count, expected.count, label)
            for (index, (a, b)) in zip(actual, expected).enumerated() {
                let tolerance: CGFloat = stacked && scaleIndices.contains(index) ? 0.002 : 1
                XCTAssertEqual(a, b, accuracy: tolerance, "\(label) component \(index)")
            }
            if stacked, !lowerOnly, actual.count == 18, expected.count == 18 {
                // 同一窗口下，右边和底边的位置差等于对应窗口边距的差。
                XCTAssertEqual(actual[14] + actual[16], expected[14] + expected[16], accuracy: 1, "\(label) lower right")
                XCTAssertEqual(actual[15] + actual[17], expected[15] + expected[17], accuracy: 1, "\(label) lower bottom")
            }
        }
        for pose in requested {
            let deadline = Date().addingTimeInterval(85)
            var nextRequest = Date.distantPast
            var stableSince = Date()
            var state: [Substring] = []
            repeat {
                state = label.label.split(separator: " ")
                let shortSide = pose.hasPrefix("closed") ? 466 : 669
                if state.count == 4, state[0] == pose, min(Int(state[1]) ?? 0, Int(state[2]) ?? 0) == shortSide {
                    if Date().timeIntervalSince(stableSince) > 2.5 { break }
                } else { stableSince = Date() }
                if Date() > nextRequest, let name = state.first, !["unknown", "partial", "open"].contains(String(name)), name != pose {
                    print("SHEET_ADJUST \(pose) \(name)")
                    nextRequest = Date().addingTimeInterval(7)
                }
                Thread.sleep(forTimeInterval: 0.4)
            } while Date() < deadline
            guard Date() < deadline else { XCTFail("Device Hub did not reach \(pose): \(state)"); return }
            Thread.sleep(forTimeInterval: 0.8)
            let width = try XCTUnwrap(Double(state[1])), height = try XCTUnwrap(Double(state[2]))
            let compact = pose == "closedLandscape"
            let targets = compact ? ["large", "third"] : ["medium", "large", "medium", "third"]
            let lower = app.buttons["gesture.lower"]
            func lowerGeometry() throws -> [CGFloat] {
                let data = Data(try XCTUnwrap(lower.value as? String).utf8)
                return try JSONDecoder().decode([CGFloat].self, from: data)
            }
            var nativeLower: [CGFloat] = []
            var native: [[CGFloat]] = []
            var nativeMotion: [Int: [[CGFloat]]] = [:]
            for engine in ["UIKit", "Sheet", "Panel"] {
                app.buttons[engine].tap()
                var before: [CGFloat] = []
                if stacked {
                    XCTAssertTrue(lower.waitForExistence(timeout: 6))
                    before = try lowerGeometry()
                    XCTAssertEqual(before.count, 10)
                    print("DUO_LOWER_BEFORE", pose, engine, before)
                    if engine == "UIKit" { nativeLower = before }
                    else { compare(before, nativeLower, "\(pose) \(engine) lower before", lowerOnly: true) }
                    if environment["DUO_RECORD_DIMMING"] == "1" { Thread.sleep(forTimeInterval: 1) }
                    lower.tap()
                }
                XCTAssertTrue(button.waitForExistence(timeout: 6))
                var previous = try read()
                XCTAssertEqual(previous.detent, "third")
                for (step, target) in (["third"] + targets).enumerated() {
                    var value = previous
                    if step > 0 {
                        let upper = target == "large" || target == "medium" && previous.detent == "third"
                        let longer = target == "large" || previous.detent == "large"
                        // 普通速度拖过目标档位，保证四分之三处来自手指移动期间，而非松手后的动画。
                        let distance = height * (compact ? 0.60 : longer ? 0.42 : 0.22) + 12
                        let top = previous.geometry[1]
                        let startY = min(height - 30, top + 48)
                        let endY = min(height - 20, max(22, startY + (upper ? -distance : distance)))
                        let midX = (previous.geometry[0] + width - previous.geometry[2]) / 2
                        // 以面板内的元素为基准，让 XCTest 将触摸送到当前活动的内屏或外屏。
                        let anchor = button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                        let start = anchor.withOffset(CGVector(dx: midX - button.frame.midX, dy: startY - button.frame.midY))
                        func drag() {
                            start.press(forDuration: 0.12, thenDragTo: start.withOffset(CGVector(dx: 0, dy: endY - startY)),
                                    withVelocity: XCUIGestureVelocity(rawValue: 360), thenHoldForDuration: 0.3)
                            Thread.sleep(forTimeInterval: 0.35)
                        }
                        var sampleCount = previous.samples.count
                        drag()
                        value = try read()
                        // 系统换屏后首个触摸有时只用于激活窗口。仅在面板完全没有移动时重试。
                        if value.detent == previous.detent,
                           !value.samples.dropFirst(sampleCount).contains(where: { abs($0[1] - top) > 1 }) {
                            print("DUO_TOUCH_RETRY \(pose) \(engine) \(step)")
                            sampleCount = value.samples.count
                            drag()
                            value = try read()
                        }
                        let moved = Array(value.samples.dropFirst(sampleCount))
                        print("DUO_DRAG \(pose) \(engine) \(step) \(target) \(value.detent) \(moved)")
                        if engine == "UIKit" { nativeMotion[step] = moved }
                        else if let reference = nativeMotion[step] {
                            for progress: CGFloat in [0.25, 0.50, 0.75] {
                                let top = native[step - 1][1] + progress * (native[step][1] - native[step - 1][1])
                                let actual = try XCTUnwrap(interpolate(moved, at: top), "\(pose) \(engine) \(target) \(progress)")
                                let expected = try XCTUnwrap(interpolate(reference, at: top))
                                compare(actual, expected, "\(pose) \(engine) \(target) \(progress)")
                            }
                        }
                        XCTAssertGreaterThan(moved.count, 2, "Missing actual moving touch samples \(pose) \(engine)")
                    }
                    print("DUO_STOP \(pose) \(state[3]) \(engine) \(step) \(target) \(value.detent) \(value.geometry)")
                    XCTAssertEqual(value.pose.split(separator: " ").prefix(3), state.prefix(3))
                    XCTAssertEqual(value.detent, target, "\(pose) \(engine) step \(step)")
                    if stacked && target == "large" {
                        // XCTest 的默认截图在 Duo 内屏点亮时可能返回黑帧。让宿主按当前屏幕采集。
                        if environment["DUO_CAPTURE_DISPLAYS"] == "1" {
                            print("SHEET_CAPTURE \(engine) \(pose)")
                            Thread.sleep(forTimeInterval: 1.5)
                        } else if pose.hasPrefix("closed") {
                            let attachment = XCTAttachment(screenshot: app.screenshot())
                            attachment.name = "Duo-stack-\(pose)-\(engine)"
                            attachment.lifetime = .keepAlways
                            add(attachment)
                        }
                    }
                    XCTAssertEqual(value.geometry.count, stacked ? 18 : 12)
                    if engine == "UIKit" { native.append(value.geometry) }
                    else {
                        compare(value.geometry, native[step], "\(pose) \(engine) \(target)")
                    }
                    previous = value
                }
                if stacked, compact, environment["DUO_TOP_EDGE"] == "1" {
                    // 用较慢的真实拖动穿过半程，宿主能在松手前取得两侧的原始外屏像素。
                    let top = previous.geometry[1]
                    let travel = top - native[1][1]
                    let halfway = top - travel / 2
                    let anchor = button.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5))
                    let start = anchor.withOffset(.init(dx: 0, dy: top + 48 - button.frame.midY))
                    print("DUO_EDGE_BEGIN \(engine) \(width) \(halfway)")
                    start.press(forDuration: 0.2, thenDragTo: start.withOffset(.init(dx: 0, dy: -travel * 0.64)),
                                withVelocity: .init(rawValue: 4), thenHoldForDuration: 0.2)
                    print("DUO_EDGE_END \(engine)")
                    let moved = Array(try read().samples.dropFirst(previous.samples.count))
                    XCTAssertNotNil(interpolate(moved, at: halfway), "\(engine) 顶边未在拖动中穿过半程")
                }
                button.tap()
                XCTAssertTrue(button.waitForNonExistence(timeout: 5))
                if stacked {
                    let restored = try lowerGeometry()
                    print("DUO_LOWER_RESTORED", pose, engine, restored)
                    compare(restored, before, "\(pose) \(engine) lower restored", lowerOnly: true)
                    lower.tap()
                    XCTAssertTrue(lower.waitForNonExistence(timeout: 5))
                }
            }
        }
    }
}
