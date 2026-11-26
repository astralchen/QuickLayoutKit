import XCTest

final class AlertExamplesUITests: XCTestCase {
    @MainActor
    func testPreferredActionIsAccessibleByIdentifier() {
        continueAfterFailure = false
        let app = launchExamples()
        open("simple", in: app.tables["alerts.examples"])
        let preferred = app.buttons["alerts.action.default"]
        XCTAssertTrue(preferred.waitForExistence(timeout: 5))
        preferred.tap()
        XCTAssertTrue(preferred.waitForNonExistence(timeout: 5))
        expectResult("Default action", in: app)
    }

    @MainActor
    func testLanguageSwitchMirrorsAlertExamples() {
        continueAfterFailure = false
        let app = launchExamples()
        let style = app.segmentedControls["alerts.style"]
        let table = app.tables["alerts.examples"]
        XCTAssertLessThan(style.buttons["Alert"].frame.midX, style.buttons["Action Sheet"].frame.midX)

        let menu = app.buttons.matching(identifier: "demo.language.menu").firstMatch
        func switchLanguage(to name: String) {
            menu.tap()
            let option = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
            XCTAssertTrue(option.waitForExistence(timeout: 5))
            option.tap()
        }

        switchLanguage(to: "العربية")
        let arabicAlert = style.buttons["تنبيه"]
        XCTAssertTrue(arabicAlert.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(arabicAlert.frame.midX, style.buttons["ورقة إجراءات"].frame.midX)
        XCTAssertTrue(table.cells["alerts.demo.login"].staticTexts["نموذج تسجيل الدخول"].exists)

        if #available(iOS 26, *) { style.buttons["ورقة إجراءات"].tap() }
        for engine in ["QuickLayoutKit", "UIKit"] {
            app.segmentedControls["alerts.engine"].buttons[engine].tap()
            open("login", in: table)
            let account = app.textFields["alerts.field.first"]
            let password = app.secureTextFields["alerts.field.password"]
            XCTAssertTrue(account.waitForExistence(timeout: 5))
            XCTAssertEqual(account.placeholderValue, "الحساب")
            XCTAssertEqual(password.placeholderValue, "كلمة السر")
            tapAction("تسجيل الدخول", in: app)
            XCTAssertTrue(account.waitForNonExistence(timeout: 5))
        }

        arabicAlert.tap()
        app.segmentedControls["alerts.engine"].buttons["QuickLayoutKit"].tap()
        open("color", in: table)
        let label = app.staticTexts["التشبع"]
        let slider = app.sliders["alerts.color.saturation"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(label.frame.midX, slider.frame.midX)
        tapAction("تم", in: app)

        open("imagePicker", in: table)
        let firstPhoto = app.descendants(matching: .any)["alerts.photo.0"].firstMatch
        let secondPhoto = app.descendants(matching: .any)["alerts.photo.1"].firstMatch
        XCTAssertTrue(firstPhoto.waitForExistence(timeout: 5))
        XCTAssertTrue(secondPhoto.exists)
        XCTAssertGreaterThan(firstPhoto.frame.midX, secondPhoto.frame.midX)
        tapAction("تم", in: app)

        switchLanguage(to: "简体中文")
        let chineseAlert = style.buttons["警告框"]
        XCTAssertTrue(chineseAlert.waitForExistence(timeout: 5))
        XCTAssertLessThan(chineseAlert.frame.midX, style.buttons["操作表单"].frame.midX)
        XCTAssertTrue(table.cells["alerts.demo.login"].staticTexts["登录表单"].exists)
    }

    @MainActor
    func testActionsAndInputs() {
        continueAfterFailure = false
        let app = launchExamples()
        let table = app.tables["alerts.examples"]

        open("simple", in: table)
        tapAction("Destructive", in: app)
        expectResult("Destructive action", in: app)

        open("images", in: table)
        let disabled = app.buttons["Unavailable"]
        XCTAssertTrue(disabled.waitForExistence(timeout: 4))
        XCTAssertFalse(disabled.isEnabled)
        tapAction("Default", in: app)
        expectResult("Default action", in: app)

        checkAlertTextInputs(in: app, engine: "QuickLayoutKit")
    }

    @MainActor
    func testUIKitAlertTextFieldsAreSystemManaged() {
        continueAfterFailure = false
        let app = launchExamples()
        app.segmentedControls["alerts.engine"].buttons["UIKit"].tap()
        checkAlertTextInputs(in: app, engine: "UIKit")
    }

    @MainActor
    func testActionSheetTextFieldLayoutAndNextMatchUIKit() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("Centered Action Sheet on iOS 26 and later") }
        try checkActionSheetTextFields(anchored: false)
    }

    @MainActor
    func testPopoverTextFieldLayoutAndNextMatchUIKit() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("Modern Popover on iOS 26 and later") }
        try checkActionSheetTextFields(anchored: true)
    }

    @MainActor
    private func checkActionSheetTextFields(anchored: Bool) throws {
        continueAfterFailure = false
        var frameworkFields: [CGRect] = []
        for engine in ["QuickLayoutKit", "UIKit"] {
            let app = launchExamples(hideSidebar: false)
            let table = app.tables["alerts.examples"]
            let engineButton = app.segmentedControls["alerts.engine"].buttons[engine]
            XCTAssertTrue(engineButton.isHittable, engine)
            if !engineButton.isSelected { engineButton.tap() }
            XCTAssertTrue(engineButton.isSelected, engine)
            app.segmentedControls["alerts.style"].buttons["Action Sheet"].tap()
            app.segmentedControls["alerts.anchor"].buttons[anchored ? "Popover" : "No Anchor"].tap()

            for example in ["textField", "login"] {
                open(example, in: table)
                let field = app.textFields["alerts.field.first"]
                XCTAssertTrue(field.waitForExistence(timeout: 5), engine)
                XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), engine)
                let password = app.secureTextFields["alerts.field.password"]
                let fields = example == "login" ? [field.frame, password.frame] : [field.frame]
                let primary = example == "login" ? "Sign In" : "OK"
                let action = app.buttons[primary]
                let leading = anchored ? action.frame.minX : app.buttons["Cancel"].frame.minX
                let trailing = action.frame.maxX
                print("ACTION_SHEET_FIELDS \(engine) \(example) popover=\(anchored) \(fields)")
                for frame in fields {
                    XCTAssertEqual(frame.minX, leading, accuracy: 1, engine)
                    XCTAssertEqual(frame.maxX, trailing, accuracy: 1, engine)
                    if engine == "QuickLayoutKit" {
                        frameworkFields.append(frame)
                    } else {
                        let reference = frameworkFields.removeFirst()
                        XCTAssertEqual(frame.width, reference.width, accuracy: 1, engine)
                        XCTAssertEqual(frame.height, reference.height, accuracy: 1, engine)
                    }
                }
                if anchored {
                    let title = example == "login" ? "Login Form" : "One Text Field"
                    let titleFrames = app.staticTexts.matching(NSPredicate(format: "label == %@", title))
                        .allElementsBoundByIndex.map(\.frame)
                    let fieldFrame = fields[0]
                    let titleFrame = try XCTUnwrap(titleFrames.first {
                        abs($0.midX - fieldFrame.midX) < 2 && $0.maxY < fieldFrame.minY
                    }, "\(engine) \(title)")
                    let titleGap = fieldFrame.minY - titleFrame.maxY
                    XCTAssertEqual(titleGap, 16, accuracy: 1, "\(engine) \(title)")
                    print("POPOVER_TITLE_GAP \(engine) \(example) \(titleGap) pt")
                    for (index, screen) in XCUIScreen.screens.enumerated() {
                        let screenshot = XCTAttachment(screenshot: screen.screenshot())
                        screenshot.name = "\(engine) \(example) Popover display\(index)"
                        screenshot.lifetime = .keepAlways
                        add(screenshot)
                    }
                }
                if example == "login" {
                    app.typeText("demo\n")
                    app.typeText("test")
                    tapAction(primary, in: app)
                    expectResult("Account: demo · Password length: 4", in: app)
                } else {
                    app.typeText("demo")
                    tapAction(primary, in: app)
                    expectResult("demo", in: app)
                }
                XCTAssertTrue(field.waitForNonExistence(timeout: 5), engine)
                XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), engine)
                let measurements = app.staticTexts["alerts.measurements"].label
                XCTAssertTrue(measurements.hasPrefix(engine == "UIKit" ? "UIKit guide " : "Entry "), measurements)
            }
        }
    }

    @MainActor
    private func checkAlertTextInputs(in app: XCUIApplication, engine: String) {
        let table = app.tables["alerts.examples"]
        open("textField", in: table)
        let field = app.textFields["alerts.field.first"]
        XCTAssertTrue(field.waitForExistence(timeout: 4), engine)
        XCTAssertGreaterThan(field.frame.height, 10, engine)
        XCTAssertLessThan(field.frame.height, 70, engine)
        let checksFieldInsets: Bool
        if #available(iOS 26, *) { checksFieldInsets = true }
        else { checksFieldInsets = false }
        if checksFieldInsets {
            XCTAssertEqual(field.frame.minX - app.buttons["Cancel"].frame.minX, 14, accuracy: 1)
            XCTAssertEqual(app.buttons["OK"].frame.maxX - field.frame.maxX, 14, accuracy: 1)
            XCTAssertEqual(field.frame.height, 35, accuracy: 1)
        }
        if engine == "UIKit" { field.tap() }
        print("ALERT_FIELD \(engine) \(field.frame)")
        field.typeText("UIKit")
        tapAction("OK", in: app)
        expectResult("UIKit", in: app)
        XCTAssertTrue(app.staticTexts["alerts.measurements"].label.hasPrefix("\(engine) text fields "))

        open("login", in: table)
        let password = app.secureTextFields["alerts.field.password"]
        XCTAssertTrue(password.waitForExistence(timeout: 4), engine)
        XCTAssertLessThanOrEqual(field.frame.maxY, password.frame.minY + 1, engine)
        if checksFieldInsets {
            XCTAssertEqual(field.frame.minX - app.buttons["Cancel"].frame.minX, 14, accuracy: 1)
            XCTAssertEqual(password.frame.minX, field.frame.minX, accuracy: 1)
            XCTAssertEqual(app.buttons["Sign In"].frame.maxX - password.frame.maxX, 14, accuracy: 1)
            XCTAssertEqual(password.frame.minY - field.frame.maxY, 13, accuracy: 1)
        }
        print("ALERT_LOGIN \(engine) \(field.frame) \(password.frame)")
        field.tap()
        field.typeText("demo\n")
        password.typeText("test")
        tapAction("Sign In", in: app)
        expectResult("Account: demo · Password length: 4", in: app)
    }

    @MainActor
    func testDateAndHeightPickerResults() {
        continueAfterFailure = false
        let app = launchExamples()
        let table = app.tables["alerts.examples"]
        open("date", in: table)
        let minuteWheel = app.pickerWheels.element(boundBy: 2)
        XCTAssertTrue(minuteWheel.waitForExistence(timeout: 4))
        let originalMinute = minuteWheel.value as? String
        let minute = minuteWheel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        minute.withOffset(CGVector(dx: 0, dy: 31)).tap()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            minuteWheel.value as? String != originalMinute
        }, object: minuteWheel)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 4), .completed)
        tapAction("Done", in: app)
        XCTAssertNotEqual(app.staticTexts["alerts.result"].label, "Date Picker")

        open("height", in: table)
        let heightWheel = app.pickerWheels.firstMatch
        XCTAssertTrue(heightWheel.waitForExistence(timeout: 4))
        heightWheel.adjust(toPickerWheelValue: "215 pt")
        tapAction("Done", in: app)
        expectResult("Content height: 215 pt", in: app)
        // UIKit 滚轮的无障碍范围可以超出显示区域，入口高度由实际内容 guide 验证。
        let metrics = app.staticTexts["alerts.measurements"].label
        XCTAssertNotNil(metrics.range(of: #"Guide [0-9]+×216"#, options: .regularExpression), metrics)
    }

    @MainActor
    func testAnchoredWheelPickerKeepsItsPlannedGuide() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("Requires the modern Action Sheet presentation") }
        continueAfterFailure = false
        let device = XCUIDevice.shared
        let original = device.orientation
        defer { device.orientation = original }
        device.orientation = .landscapeLeft
        let app = launchExamples(hideSidebar: false)
        app.segmentedControls["alerts.style"].buttons["Action Sheet"].tap()
        app.segmentedControls["alerts.anchor"].buttons["Popover"].tap()
        open("height", in: app.tables["alerts.examples"])

        XCTAssertTrue(app.pickerWheels.firstMatch.waitForExistence(timeout: 5))
        tapAction("Done", in: app)
        expectResult("Content height: 216 pt", in: app)
        let metrics = app.staticTexts["alerts.measurements"].label
        XCTAssertTrue(metrics.contains("Entry 240×216 · Planned 208×216"), metrics)
        XCTAssertTrue(metrics.contains("Guide 208×216 · Panel 240×"), metrics)
    }

    @MainActor
    func testCalendarReminderHeaderInBothEngines() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("Requires the modern Action Sheet presentation") }
        continueAfterFailure = false
        let app = launchExamples()
        let table = app.tables["alerts.examples"]
        let engines = app.segmentedControls["alerts.engine"]
        let styles = app.segmentedControls["alerts.style"]
        let calendar = Calendar(identifier: .gregorian)
        var components = calendar.dateComponents([.year, .month, .day], from: .now)
        components.day = components.day == 15 ? 16 : 15
        let date = try XCTUnwrap(calendar.date(from: components))
        let locale = Locale(identifier: "en_US")
        let dayLabel = date.formatted(.dateTime.month(.wide).day().locale(locale))
        let resultDate = date.formatted(.dateTime.month(.abbreviated).day().year().locale(locale))
        let dayPredicate = NSPredicate(format: "label CONTAINS[c] %@", dayLabel)

        for style in ["Alert", "Action Sheet"] {
            styles.buttons[style].tap()
            var frameworkGaps: [String: CGFloat] = [:]
            for engine in ["QuickLayoutKit", "UIKit"] {
                engines.buttons[engine].tap()
                open("calendar", in: table)

                let selectedDay = app.buttons.matching(dayPredicate).firstMatch
                XCTAssertTrue(selectedDay.waitForExistence(timeout: 4), "\(engine) \(style) \(dayLabel)")
                let message = app.staticTexts["Choose a date and reminder timing."]
                let timing = app.segmentedControls["alerts.calendar.timing"]
                XCTAssertTrue(message.exists)
                XCTAssertTrue(timing.exists)
                XCTAssertLessThanOrEqual(selectedDay.frame.maxY, message.frame.minY + 1, "\(engine) \(style)")
                XCTAssertLessThanOrEqual(message.frame.maxY, timing.frame.minY + 1, "\(engine) \(style)")

                selectedDay.tap()
                timing.buttons["Day before"].tap()
                let done = app.buttons["Done"]
                XCTAssertTrue(done.isHittable, "\(engine) \(style)")
                if style == "Action Sheet" {
                    let original = done.frame
                    let gaps = ["message": message.frame.minY, "timing": timing.frame.minY, "done": original.minY]
                        .mapValues { $0 - selectedDay.frame.minY }
                    if engine == "QuickLayoutKit" {
                        frameworkGaps = gaps
                    } else {
                        for (element, system) in gaps {
                            let framework = try XCTUnwrap(frameworkGaps[element])
                            XCTAssertEqual(framework, system, accuracy: 2, "Selected date to \(element)")
                        }
                        print("Calendar Action Sheet offsets from selected date: QuickLayoutKit \(frameworkGaps), UIKit \(gaps)")
                    }
                    let start = message.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                    start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -96)))
                    XCTAssertEqual(done.frame.minY, original.minY, accuracy: 1, "\(engine) Popover should fit without scrolling")
                }
                // Duo 展开时，默认截图可能取到熄灭的外屏。
                for (index, screen) in XCUIScreen.screens.enumerated() {
                    let screenshot = XCTAttachment(screenshot: screen.screenshot())
                    screenshot.name = "\(engine) \(style) Calendar Header display\(index)"
                    screenshot.lifetime = .keepAlways
                    add(screenshot)
                }
                tapAction("Done", in: app)
                XCTAssertTrue(timing.waitForNonExistence(timeout: 4))
                expectResult("\(resultDate) · Day before", in: app)
            }
        }
    }

    @MainActor
    func testSearchImagesColorAndMap() {
        continueAfterFailure = false
        let app = launchExamples()
        let table = app.tables["alerts.examples"]
        for (example, query, country, value) in [
            ("country", "Japan", "Japan", "Japan · JP"),
            ("phone", "+81", "Japan", "Japan · +81 · JP"),
            ("currency", "JPY", "Japanese Yen", "Japanese Yen · JPY"),
        ] {
            open(example, in: table)
            let search = app.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 4))
            search.tap()
            search.typeText(query + "\n")
            let cell = app.cells.containing(.staticText, identifier: country).firstMatch
            XCTAssertTrue(cell.waitForExistence(timeout: 4))
            cell.tap()
            expectResult(value, in: app)
        }

        open("imagePicker", in: table)
        let image = app.descendants(matching: .any)["alerts.photo.0"].firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 4))
        image.tap()
        tapAction("Done", in: app)
        expectResult("Image 1", in: app)
        XCTAssertTrue(image.waitForNonExistence(timeout: 5))

        let imageRow = table.cells["alerts.demo.imagePicker"]
        let modes = imageRow.buttons["alerts.imageModes"]
        for _ in 0..<4 where !modes.isHittable {
            scrollTable(table, towardsTop: imageRow.frame.midY < table.frame.midY)
        }
        XCTAssertTrue(modes.isHittable, "Image row: \(imageRow.debugDescription)")
        modes.tap()
        app.buttons["Multiple · Grid"].tap()
        for index in 0...1 {
            app.descendants(matching: .any)["alerts.photo.\(index)"].firstMatch.tap()
        }
        let firstPhoto = app.descendants(matching: .any)["alerts.photo.0"].firstMatch
        firstPhoto.tap()
        XCTAssertFalse(firstPhoto.isSelected)
        firstPhoto.tap()
        XCTAssertTrue(firstPhoto.isSelected)
        tapAction("Done", in: app)
        expectResult("Image 2, Image 1", in: app)

        modes.tap()
        app.buttons["Single · Paging"].tap()
        let grid = app.collectionViews["alerts.photos.grid"]
        grid.swipeLeft()
        let secondPhoto = grid.cells["alerts.photo.1"]
        XCTAssertTrue(secondPhoto.isHittable)
        XCTAssertEqual(secondPhoto.frame.width, grid.frame.width, accuracy: 1)
        secondPhoto.tap()
        tapAction("Done", in: app)
        expectResult("Image 2", in: app)

        open("color", in: table)
        let swatch = app.staticTexts["alerts.color.hex"]
        XCTAssertTrue(swatch.waitForExistence(timeout: 4))
        XCTAssertEqual(swatch.label, "#FF2DC6")
        app.sliders["alerts.color.saturation"].adjust(toNormalizedSliderPosition: 0.3)
        let changed = swatch.label
        XCTAssertNotEqual(changed, "#FF2DC6")
        tapAction("Done", in: app)
        expectResult(changed, in: app)

        open("location", in: table)
        let pick = app.buttons["alerts.map.choose"]
        XCTAssertTrue(pick.waitForExistence(timeout: 4))
        pick.tap()
        let result = app.staticTexts["alerts.result"]
        let coordinates = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", ","), object: result)
        XCTAssertEqual(XCTWaiter.wait(for: [coordinates], timeout: 4), .completed)
    }

    @MainActor
    func testColorPickerSlidersHaveRoomInBothEngines() {
        continueAfterFailure = false
        let app = launchExamples()
        let table = app.tables["alerts.examples"]

        for engine in ["QuickLayoutKit", "UIKit"] {
            app.segmentedControls["alerts.engine"].buttons[engine].tap()
            open("color", in: table)
            let swatch = app.staticTexts["alerts.color.hex"]
            XCTAssertTrue(swatch.waitForExistence(timeout: 5))
            XCTAssertEqual(swatch.label, "#FF2DC6")
            XCTAssertGreaterThan(swatch.frame.width, 180, engine)
            for component in ["hue", "saturation", "brightness"] {
                let slider = app.sliders["alerts.color.\(component)"]
                XCTAssertTrue(slider.isHittable, "\(engine) \(component)")
                XCTAssertGreaterThan(slider.frame.width, 100, "\(engine) \(component)")
            }

            app.sliders["alerts.color.saturation"].adjust(toNormalizedSliderPosition: 0.3)
            let updatedHex = swatch.label
            XCTAssertNotEqual(updatedHex, "#FF2DC6", engine)
            tapAction("Done", in: app)
            expectResult(updatedHex, in: app)
        }
    }

    @MainActor
    func testActionAlignmentDemoRunsInBothEngines() {
        continueAfterFailure = false
        let app = launchExamples()
        let table = app.tables["alerts.examples"]
        for engine in ["QuickLayoutKit", "UIKit"] {
            app.segmentedControls["alerts.engine"].buttons[engine].tap()
            open("images", in: table)
            let defaultAction = app.buttons["Default"]
            let destructive = app.buttons["Destructive"]
            let unavailable = app.buttons["Unavailable"]
            XCTAssertTrue(defaultAction.waitForExistence(timeout: 5), engine)
            XCTAssertTrue(destructive.isHittable, engine)
            XCTAssertTrue(unavailable.exists, engine)
            XCTAssertFalse(unavailable.isEnabled, engine)
            print("ALERT_IMAGES \(engine) \(defaultAction.frame) \(destructive.frame) \(unavailable.frame)")
            tapAction("Default", in: app)
            expectResult("Default action", in: app)
            open("images", in: table)
            tapAction("Destructive", in: app)
            expectResult("Destructive action", in: app)
        }
    }

    @MainActor
    func testImagePickerUsesPanelWidthInBothEngines() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("iOS 26+ alert layout") }
        continueAfterFailure = false
        let app = launchExamples()
        let table = app.tables["alerts.examples"]
        let grid = app.collectionViews["alerts.photos.grid"]
        let cancel = app.buttons["Cancel"]
        let metrics = app.staticTexts["alerts.measurements"]

        for engine in ["QuickLayoutKit", "UIKit"] {
            app.segmentedControls["alerts.engine"].buttons[engine].tap()
            open("imagePicker", in: table)
            XCTAssertTrue(grid.waitForExistence(timeout: 5), engine)
            let first = grid.descendants(matching: .any)["alerts.photo.0"].firstMatch
            let third = grid.descendants(matching: .any)["alerts.photo.2"].firstMatch
            XCTAssertTrue(first.isHittable, engine)
            XCTAssertTrue(third.isHittable, engine)
            let frame = grid.frame
            let firstFrame = first.frame
            XCTAssertEqual(frame.width, 320, accuracy: 1, engine)
            XCTAssertEqual(frame.height, 254, accuracy: 1, engine)
            XCTAssertEqual(cancel.frame.minX - frame.minX, 16, accuracy: 1, engine)
            XCTAssertEqual(cancel.frame.minY - frame.maxY, 24, accuracy: 1, engine)
            XCTAssertEqual(firstFrame.minX, frame.minX, accuracy: 1, engine)
            XCTAssertEqual(third.frame.maxX, frame.maxX, accuracy: 1, engine)

            let last = grid.descendants(matching: .any)["alerts.photo.9"].firstMatch
            XCTAssertFalse(last.isHittable, engine)
            for _ in 0..<4 where !last.isHittable { grid.swipeUp() }
            XCTAssertTrue(last.isHittable, engine)
            print("ALERT_IMAGE_PICKER \(engine) grid=\(frame) first=\(firstFrame.size) last=\(last.frame)")
            last.tap()
            tapAction("Done", in: app)
            expectResult("Image 10", in: app)
            XCTAssertTrue(metrics.label.localizedCaseInsensitiveContains("Guide 288×254"), metrics.label)
            if engine == "QuickLayoutKit" {
                XCTAssertTrue(metrics.label.contains("Entry 320×254 · Planned 288×254"), metrics.label)
            }
        }
    }

    @MainActor
    func testActionSheetLayoutMatchesUIKit() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else { throw XCTSkip("Unanchored Action Sheet on iPhone") }
        continueAfterFailure = false
        let app = launchExamples()
        let table = app.tables["alerts.examples"]
        app.segmentedControls["alerts.style"].buttons["Action Sheet"].tap()
        app.segmentedControls["alerts.anchor"].buttons["No Anchor"].tap()

        func frames() -> [CGRect] {
            open("simple", in: table)
            let actions = ["Default", "Destructive", "Cancel"].map { app.buttons[$0] }
            XCTAssertTrue(actions[0].waitForExistence(timeout: 5))
            let frames = actions.map(\.frame)
            actions[2].tap()
            expectResult("Cancelled", in: app)
            return frames
        }

        let custom = frames()
        app.segmentedControls["alerts.engine"].buttons["UIKit"].tap()
        let system = frames()
        for (actual, expected) in zip(custom, system) {
            XCTAssertEqual(actual.minX, expected.minX, accuracy: 1)
            XCTAssertEqual(actual.minY, expected.minY, accuracy: 1)
            XCTAssertEqual(actual.width, expected.width, accuracy: 1)
            XCTAssertEqual(actual.height, expected.height, accuracy: 1)
        }
        if #unavailable(iOS 26) {
            XCTAssertEqual(custom[2].minY - custom[1].maxY, 8, accuracy: 1)
        }
    }

    @MainActor
    func testModernAlertLayoutInBothEngines() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("iOS 26+ alert layout") }
        continueAfterFailure = false
        let app = launchExamples()
        let table = app.tables["alerts.examples"]
        let messageText = "Default, destructive and cancel actions"
        let firstAction = app.buttons["Default"]
        let cancel = app.buttons["Cancel"]
        let done = app.buttons["Done"]
        let metrics = app.staticTexts["alerts.measurements"]

        for engine in ["QuickLayoutKit", "UIKit"] {
            app.segmentedControls["alerts.engine"].buttons[engine].tap()
            open("simple", in: table)
            let message = app.staticTexts[engine == "UIKit" ? messageText : "AlertController.messageLabel"]
            XCTAssertTrue(message.waitForExistence(timeout: 5), engine)
            XCTAssertTrue(firstAction.waitForExistence(timeout: 5), engine)
            XCTAssertEqual(message.frame.height, 38, accuracy: 2, engine)
            XCTAssertEqual(firstAction.frame.minY - message.frame.maxY, 20, accuracy: 2, engine)
            XCTAssertEqual(firstAction.frame.width, 288, accuracy: 2, engine)
            if engine == "QuickLayoutKit" {
                let reader = app.scrollViews["AlertController.messageScrollView"]
                XCTAssertEqual(reader.frame.width, 320, accuracy: 1)
                XCTAssertEqual(message.frame.minX - reader.frame.minX, 30, accuracy: 1)
                XCTAssertEqual(firstAction.frame.minX - reader.frame.minX, 16, accuracy: 1)
            }
            print("ALERT_UI \(engine) Simple message=\(message.frame.size) action=\(firstAction.frame.size)")
            tapAction("Cancel", in: app)
            expectResult("Cancelled", in: app)

            open("country", in: table)
            let list = app.tables["alerts.picker.list"]
            let search = app.searchFields["alerts.picker.searchField"]
            XCTAssertTrue(list.waitForExistence(timeout: 5), engine)
            XCTAssertTrue(search.waitForExistence(timeout: 5), engine)
            XCTAssertTrue(done.isHittable, engine)
            let listFrame = list.frame
            let searchFrame = search.frame
            let cancelFrame = cancel.frame
            let doneFrame = done.frame
            XCTAssertLessThan(cancelFrame.minX, doneFrame.minX, engine)
            XCTAssertEqual(cancelFrame.midY, doneFrame.midY, accuracy: 1, engine)
            XCTAssertEqual(listFrame.width, 320, accuracy: 1, engine)
            XCTAssertEqual(searchFrame.minX - listFrame.minX, 8, accuracy: 1, engine)
            XCTAssertEqual(listFrame.maxX - searchFrame.maxX, 8, accuracy: 1, engine)
            XCTAssertEqual(cancelFrame.minY - listFrame.maxY, 24, accuracy: 1, engine)
            let firstName = list.cells.firstMatch.staticTexts.firstMatch.label
            let firstCountry = list.staticTexts[firstName].firstMatch
            XCTAssertTrue(firstCountry.isHittable, engine)
            XCTAssertEqual(firstCountry.frame.minX - listFrame.minX, 16, accuracy: 1, engine)
            list.swipeUp()
            XCTAssertFalse(firstCountry.isHittable, engine)
            print("ALERT_UI \(engine) Country-Picker list=\(listFrame) search=\(searchFrame) cancel=\(cancelFrame)")
            tapAction("Cancel", in: app)
            expectResult("Cancelled", in: app)
            XCTAssertTrue(metrics.label.localizedCaseInsensitiveContains("Guide 288×264"), metrics.label)
            if engine == "QuickLayoutKit" {
                XCTAssertTrue(metrics.label.contains("Entry 320×264 · Planned 288×264"), metrics.label)
            }
            print("ALERT_UI \(engine) \(metrics.label)")
        }
    }

    @MainActor
    func testRichTextTitleDetailAndAction() {
        checkRichText(actionSheet: false)
    }

    @MainActor
    func testRichTextActionSheetTitleDetailAndAction() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("Centered Action Sheet on iOS 26 and later") }
        checkRichText(actionSheet: true)
    }

    @MainActor
    private func checkRichText(actionSheet: Bool) {
        continueAfterFailure = false
        let app = launchExamples()
        let table = app.tables["alerts.examples"]
        if actionSheet {
            app.segmentedControls["alerts.style"].buttons["Action Sheet"].tap()
            app.segmentedControls["alerts.anchor"].buttons["No Anchor"].tap()
        }
        open("richText", in: table)

        let title = app.staticTexts["AlertController.titleLabel"]
        let message = app.staticTexts["AlertController.messageLabel"]
        let detail = app.staticTexts["AlertController.detailMessageLabel"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(title.label.hasPrefix("Review display options"))
        XCTAssertGreaterThan(title.frame.height, 35)
        XCTAssertLessThan(title.frame.height, 50)
        XCTAssertTrue(message.label.hasPrefix("Apply to all windows"))
        XCTAssertEqual(detail.label, "You can change this later in Settings.")

        var frameworkActionWidth: CGFloat?
        for engine in ["QuickLayoutKit", "UIKit"] {
            if engine == "UIKit" {
                app.segmentedControls["alerts.engine"].buttons[engine].tap()
                open("richText", in: table)
            }
            let apply = app.buttons["Apply changes"]
            let cancel = app.buttons["Cancel"]
            XCTAssertTrue(apply.waitForExistence(timeout: 5), engine)
            let applyFrame = apply.frame
            let cancelFrame = cancel.frame
            if #available(iOS 26, *) {
                XCTAssertLessThan(cancelFrame.minX, applyFrame.minX, engine)
                XCTAssertEqual(applyFrame.minY, cancelFrame.minY, accuracy: 1, engine)
                XCTAssertEqual(applyFrame.height, 48, accuracy: 1, engine)
                let actionWidth = applyFrame.union(cancelFrame).width
                if let frameworkActionWidth {
                    XCTAssertEqual(actionWidth, frameworkActionWidth, accuracy: 1)
                } else {
                    frameworkActionWidth = actionWidth
                }
            } else {
                XCTAssertEqual(applyFrame.minX, cancelFrame.minX, accuracy: 1, engine)
                XCTAssertLessThan(applyFrame.maxY, cancelFrame.minY, engine)
                XCTAssertEqual(applyFrame.height, 44, accuracy: 1, engine)
            }
            if engine == "QuickLayoutKit" {
                XCTAssertGreaterThan(detail.frame.minY, max(applyFrame.maxY, cancelFrame.maxY))
            }
            apply.tap()
            expectResult("Applied", in: app)
        }
    }

    @MainActor
    func testLongMessageScrollsWithActionsVisible() {
        continueAfterFailure = false
        let app = launchExamples()
        let table = app.tables["alerts.examples"]
        let title = app.staticTexts["AlertController.titleLabel"]
        let message = app.staticTexts["AlertController.messageLabel"]
        let reader = app.scrollViews["AlertController.messageScrollView"]
        let done = app.buttons["Done"]
        open("longMessage", in: table)
        XCTAssertTrue(reader.waitForExistence(timeout: 5))
        XCTAssertTrue(message.label.hasPrefix("Reading on different displays"))
        XCTAssertTrue(message.label.contains("You have reached the final paragraph."))
        XCTAssertTrue(done.isHittable)
        let textInset: CGFloat
        let bottomPadding: CGFloat
        if #available(iOS 26, *) {
            textInset = 30
            bottomPadding = 0
            XCTAssertEqual(app.buttons["Cancel"].frame.minX - reader.frame.minX, 16, accuracy: 1)
            XCTAssertEqual(reader.frame.maxX - done.frame.maxX, 16, accuracy: 1)
        } else {
            textInset = 16
            bottomPadding = 20.5
            XCTAssertEqual(app.buttons["Cancel"].frame.minX, reader.frame.minX, accuracy: 1)
            XCTAssertEqual(done.frame.maxX, reader.frame.maxX, accuracy: 1)
        }
        XCTAssertEqual(message.frame.minX - reader.frame.minX, textInset, accuracy: 1)
        XCTAssertEqual(reader.frame.maxX - message.frame.maxX, textInset, accuracy: 1)

        let startingY = message.frame.minY
        let startingTitleY = title.frame.minY
        let startingActionY = done.frame.minY
        XCTAssertGreaterThan(message.frame.maxY, reader.frame.maxY)
        for _ in 0..<16 where message.frame.maxY > reader.frame.maxY + 1 { reader.swipeUp() }
        XCTAssertLessThan(message.frame.minY, startingY)
        if #unavailable(iOS 26), title.exists {
            XCTAssertEqual(title.frame.minY - startingTitleY, message.frame.minY - startingY, accuracy: 2)
        }
        XCTAssertEqual(message.frame.maxY, reader.frame.maxY - bottomPadding, accuracy: 2)
        XCTAssertEqual(done.frame.minY, startingActionY, accuracy: 1)
        XCTAssertTrue(done.isHittable)
        done.tap()
        XCTAssertTrue(reader.waitForNonExistence(timeout: 4))
    }

    @MainActor
    func testUIKitLongMessagePopoverKeepsDoneFullyVisibleInLandscape() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("Anchored Action Sheet on iOS 26 and later") }
        continueAfterFailure = false
        let device = XCUIDevice.shared
        let original = device.orientation
        defer { device.orientation = original }
        device.orientation = .landscapeLeft
        let app = launchExamples(hideSidebar: false)
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(window.width, window.height)
        app.buttons.matching(identifier: "demo.language.menu").firstMatch.tap()
        let chinese = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "简体中文")).firstMatch
        XCTAssertTrue(chinese.waitForExistence(timeout: 5))
        chinese.tap()
        let table = app.tables["alerts.examples"]
        app.segmentedControls["alerts.engine"].buttons["UIKit"].tap()
        app.segmentedControls["alerts.style"].buttons["操作表单"].tap()
        app.segmentedControls["alerts.anchor"].buttons["浮层"].tap()
        open("longMessage", in: table)

        let popover = app.popovers.firstMatch
        let done = popover.buttons["完成"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        let panelFrame = popover.frame
        let actionFrame = done.frame
        XCTAssertGreaterThanOrEqual(panelFrame.maxY - actionFrame.maxY, 8,
                                    "Popover \(panelFrame), Done \(actionFrame)")
        XCTAssertTrue(done.isHittable)

        let reader = popover.scrollViews["alerts.text.content"]
        let end = reader.staticTexts["alerts.text.end"]
        XCTAssertTrue(reader.exists)
        XCTAssertFalse(end.isHittable)
        let start = popover.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.68))
        let destination = popover.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.24))
        for _ in 0..<16 where !end.isHittable {
            start.press(forDuration: 0.1, thenDragTo: destination, withVelocity: .fast, thenHoldForDuration: 0.1)
        }
        XCTAssertTrue(end.isHittable, "Reader \(reader.frame), last paragraph \(end.frame)")
        XCTAssertEqual(done.frame, actionFrame)
        XCTAssertTrue(done.isHittable)
        done.tap()
        XCTAssertTrue(popover.waitForNonExistence(timeout: 4))
    }

    @MainActor
    func testTextViewerScrollsToTheEndWithActionsVisible() {
        continueAfterFailure = false
        let app = launchExamples()
        let table = app.tables["alerts.examples"]
        let reader = app.scrollViews["alerts.text.content"]
        let end = app.staticTexts["alerts.text.end"]
        let done = app.buttons["Done"]

        for engine in ["QuickLayoutKit", "UIKit"] {
            app.segmentedControls["alerts.engine"].buttons[engine].tap()
            open("text", in: table)
            XCTAssertTrue(reader.waitForExistence(timeout: 5), engine)
            XCTAssertTrue(done.isHittable, engine)
            XCTAssertFalse(end.isHittable, engine)
            for _ in 0..<16 where !end.isHittable { reader.swipeUp() }
            XCTAssertTrue(end.isHittable, engine)
            XCTAssertTrue(done.isHittable, engine)
            done.tap()
            XCTAssertTrue(reader.waitForNonExistence(timeout: 4), engine)
        }
    }

    @MainActor
    func testAnchoredActionSheetDismissesLikeUIKit() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("Anchored Action Sheet on iOS 26 and later") }
        continueAfterFailure = false
        let app = launchExamples()
        let table = app.tables["alerts.examples"]
        app.segmentedControls["alerts.style"].buttons["Action Sheet"].tap()
        app.segmentedControls["alerts.anchor"].buttons["Popover"].tap()
        for engine in ["UIKit", "QuickLayoutKit"] {
            app.segmentedControls["alerts.engine"].buttons[engine].tap()
            open("text", in: table)
            let text = app.scrollViews["alerts.text.content"]
            XCTAssertTrue(text.waitForExistence(timeout: 5), engine)
            XCTAssertFalse(app.buttons["Cancel"].exists, engine)
            let dismissRegion = app.otherElements["PopoverDismissRegion"]
            XCTAssertTrue(dismissRegion.isHittable, engine)
            dismissRegion.tap()
            XCTAssertTrue(text.waitForNonExistence(timeout: 4), engine)
            expectResult("Cancelled", in: app)
        }
    }

    @MainActor
    func testWidthSensitiveContentAndCancellationInEveryPresentation() {
        continueAfterFailure = false
        let device = XCUIDevice.shared
        let original = device.orientation
        defer { device.orientation = original }
        device.orientation = .portrait
        let app = launchExamples()
        let table = app.tables["alerts.examples"]
        let style = app.segmentedControls["alerts.style"]
        let anchor = app.segmentedControls["alerts.anchor"]

        func checkTextLayout(anchored: Bool, guideHorizontalInsets: CGFloat = 0) {
            open("text", in: table)
            let text = app.scrollViews["alerts.text.content"]
            XCTAssertTrue(text.waitForExistence(timeout: 4))
            let frame = text.frame
            XCTAssertGreaterThan(frame.width, 100)
            XCTAssertGreaterThan(frame.height, 100)
            if anchored {
                XCTAssertFalse(app.buttons["Cancel"].exists)
                tapOutside(text, in: app)
            } else {
                tapAction("Cancel", in: app)
            }
            XCTAssertTrue(text.waitForNonExistence(timeout: 4))
            expectResult("Cancelled", in: app)
            let metrics = app.staticTexts["alerts.measurements"].label
            let size = "\(Int(frame.width.rounded()))×\(Int(frame.height.rounded()))"
            let guideSize = "\(Int((frame.width - guideHorizontalInsets).rounded()))×\(Int(frame.height.rounded()))"
            XCTAssertTrue(metrics.contains("Entry " + size), metrics)
            XCTAssertTrue(metrics.contains("Planned " + guideSize), metrics)
            XCTAssertTrue(metrics.contains("Guide " + guideSize), metrics)
            print("ALERT_UI \(device.orientation.rawValue) anchored=\(anchored): \(metrics)")
        }

        if #available(iOS 26, *) { checkTextLayout(anchored: false, guideHorizontalInsets: 32) }
        else { checkTextLayout(anchored: false) }
        style.buttons["Action Sheet"].tap()
        anchor.buttons["No Anchor"].tap()
        checkTextLayout(anchored: false, guideHorizontalInsets: 32)
        anchor.buttons["Popover"].tap()
        if #available(iOS 26, *) {
            checkTextLayout(anchored: true, guideHorizontalInsets: 32)
        } else if UIDevice.current.userInterfaceIdiom == .phone {
            checkTextLayout(anchored: false, guideHorizontalInsets: 32)
        } else {
            checkTextLayout(anchored: true)
        }

        if UIDevice.current.userInterfaceIdiom == .pad {
            device.orientation = .landscapeLeft
            let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                // iPad 的应用窗口可以在横屏时保持较窄，按显示器方向确认旋转。
                let screen = XCUIScreen.main.screenshot().image.size
                return screen.width > screen.height
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 6), .completed)
            if #available(iOS 26, *) { checkTextLayout(anchored: true, guideHorizontalInsets: 32) }
            else { checkTextLayout(anchored: true) }
        }

        app.segmentedControls["alerts.engine"].buttons["UIKit"].tap()
        open("text", in: table)
        let nativeText = app.scrollViews["alerts.text.content"]
        XCTAssertTrue(nativeText.waitForExistence(timeout: 4))
        XCTAssertGreaterThan(nativeText.frame.width, 100)
        XCTAssertGreaterThan(nativeText.frame.height, 100)
        tapAction("Done", in: app)
        XCTAssertTrue(nativeText.waitForNonExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["alerts.measurements"].label.contains("UIKit guide"))
        print("ALERT_UI UIKit \(app.staticTexts["alerts.measurements"].label)")
    }

    @MainActor
    private func launchExamples(hideSidebar: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-quicklayoutkit.demo.locale.identifier", "en"]
        app.launch()
        let sidebar = app.buttons["Show Sidebar"]
        if sidebar.exists, sidebar.isHittable { sidebar.tap() }
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        search.tap()
        search.typeText("Alerts")
        let entry = app.cells["demo.alertExamples.title"]
        XCTAssertTrue(entry.waitForExistence(timeout: 6))
        entry.tap()
        let hide = app.buttons["Hide Sidebar"]
        if hideSidebar, hide.exists, hide.isHittable { hide.tap() }
        XCTAssertTrue(app.tables["alerts.examples"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    private func open(_ example: String, in table: XCUIElement) {
        let item = table.cells["alerts.demo.\(example)"]
        for _ in 0..<4 where !item.isHittable { scrollTable(table, towardsTop: true) }
        for _ in 0..<8 where !item.isHittable { scrollTable(table, towardsTop: false) }
        XCTAssertTrue(item.isHittable, example)
        item.tap()
    }

    @MainActor
    private func scrollTable(_ table: XCUIElement, towardsTop: Bool) {
        let upper = table.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.26))
        let lower = table.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.70))
        let start = towardsTop ? upper : lower
        let end = towardsTop ? lower : upper
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
    }

    @MainActor
    private func tapOutside(_ content: XCUIElement, in app: XCUIApplication) {
        let frame = app.popovers.firstMatch.frame
        let bounds = app.windows.firstMatch.frame
        let leadingRoom = frame.minX - bounds.minX
        let trailingRoom = bounds.maxX - frame.maxX
        // 紧贴 Popover 外沿取点，避免跨到 Duo 的另一侧或落到浮动窗口之外。
        let x = leadingRoom > trailingRoom
            ? frame.minX - min(24, leadingRoom / 2)
            : frame.maxX + min(24, trailingRoom / 2)
        let center = content.frame
        content.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .withOffset(CGVector(dx: x - center.midX, dy: 0)).tap()
    }

    @MainActor
    private func tapAction(_ title: String, in app: XCUIApplication) {
        let action = app.buttons[title]
        XCTAssertTrue(action.waitForExistence(timeout: 5), title)
        if !action.isHittable, let scroll = app.scrollViews.allElementsBoundByIndex.last {
            scroll.swipeUp()
        }
        XCTAssertTrue(action.isHittable, title)
        action.tap()
    }

    @MainActor
    private func expectResult(_ expected: String, in app: XCUIApplication) {
        let result = app.staticTexts["alerts.result"]
        XCTAssertTrue(result.waitForExistence(timeout: 4))
        let wait = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", expected), object: result)
        XCTAssertEqual(XCTWaiter.wait(for: [wait], timeout: 4), .completed, result.label)
    }
}
