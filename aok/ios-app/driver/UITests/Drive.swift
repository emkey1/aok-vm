// Drives AOK VM on a device as a person would, so a check needs nobody at the device. Each test is one step,
// run by drive.sh with -only-testing; what it saw goes to the log ("DRIVE ..."); screenshots come from
// `xcrun devicectl device capture screenshot`. The device needs Settings, Developer, Enable UI Automation, and must
// be unlocked when a step starts ("Timed out while enabling automation mode" otherwise).
import XCTest

final class Drive: XCTestCase {
    let vm = XCUIApplication(bundleIdentifier: "app.ish.aok.vm")

    override func setUp() {
        continueAfterFailure = false
    }

    func note(_ s: String) { print("DRIVE \(s)") }

    // No XCTAttachment: on the A10X (iOS 17.7) Xcode 27's request to delete attachments traps testmanagerd and the
    // run restarts. Screenshots come from devicectl instead.
    func shot(_ name: String) { note("shot \(name)") }

    /// Settings, AOK VM, "Disable screen dimming when idle" on: a running machine keeps the screen awake.
    func testKeepAwake() {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        let cell = settings.cells.staticTexts["AOK VM"]
        var tries = 0
        while !cell.exists && tries < 15 { settings.swipeUp(); tries += 1 }
        XCTAssertTrue(cell.exists, "no AOK VM in Settings")
        cell.tap()
        let toggle = settings.switches["Disable screen dimming when idle"]
        tries = 0
        while !toggle.exists && tries < 8 { settings.swipeUp(); tries += 1 }
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "no idle switch")
        note("idle switch was \(toggle.value ?? "?")")
        // iOS 17's Settings reports the whole row as the switch: its knob is at the right end.
        if (toggle.value as? String) != "1" {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.5)).tap(); sleep(1)
        }
        note("idle switch \(toggle.value ?? "?")")
        shot("settings")
    }

    /// AOK VM in front, past What's New, its machine list in the log.
    func testOpen() {
        vm.launch()
        if vm.buttons["Continue"].waitForExistence(timeout: 8) { vm.buttons["Continue"].tap() }
        sleep(2)
        note(vm.debugDescription)
        shot("list")
    }

    /// Starts the machine `name` from AOK VM's list, waits `wait` seconds, and logs what is on screen.
    func start(_ name: String, wait: UInt32) {
        vm.launch()
        if vm.buttons["Continue"].waitForExistence(timeout: 3) { vm.buttons["Continue"].tap() }
        let run = vm.cells.containing(.staticText, identifier: name).buttons["Run"]
        XCTAssertTrue(run.waitForExistence(timeout: 10), "no Run for \(name)")
        run.tap()
        note("started \(name)")
        sleep(wait)
        XCTAssertEqual(vm.state, .runningForeground, "AOK VM is not running in front")
        note(vm.debugDescription)
    }

    func test68k() { start("AOK 68k Console", wait: 75) }

    /// One of the two x86-64 test machines (CPU Default; cores Default, and 1), which run the four parallel checks
    /// (stresst) and leave a shell: started from the list and given `wait` seconds. The screen has the result
    /// (devicectl's screenshot), Data/debug.log the QEMU command line: -cpu, -smp and -accel.
    func x86(_ name: String, wait: UInt32) {
        start(name, wait: wait)
    }
    func testX86Default() { x86("AOK x86-64 Default", wait: 420) }
    func testX86One() { x86("AOK x86-64 One Core", wait: 600) }
    func testPPC() { start("AOK PowerPC Console", wait: 120) }

    /// The window menu's Current Window: picks the device whose label starts with `prefix`.
    func pick(_ prefix: String) {
        vm.activate()
        if !vm.buttons["Display"].isHittable { vm.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
        vm.buttons["Display"].tap()
        vm.buttons["Current Window"].tap()
        let item = vm.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "no \(prefix) in the menu")
        note("menu item \(item.label)")
        item.tap()
        sleep(4)
        XCTAssertEqual(vm.state, .runningForeground, "AOK VM is not running in front")
        note("showing \(prefix), AOK VM \(vm.state.rawValue)")
    }

    func testShowDisplay() { pick("Display 0") }
    func testShowSerial() { pick("Serial 0") }

    /// The toolbar's Power Off, and whatever confirmation follows.
    func testPowerOff() {
        vm.activate()
        if !vm.buttons["Power Off"].isHittable { vm.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
        vm.buttons["Power Off"].tap()
        sleep(2)
        note(vm.debugDescription)
        for b in ["Yes", "OK", "Stop", "Force Stop", "Power Off"] where vm.alerts.buttons[b].exists || vm.sheets.buttons[b].exists {
            (vm.alerts.buttons[b].exists ? vm.alerts.buttons[b] : vm.sheets.buttons[b]).tap(); note("confirmed \(b)"); break
        }
        sleep(5)
        note("AOK VM \(vm.state.rawValue)")
    }

    /// "poweroff -f" typed at the machine's shell: the guest powers itself off (on a PowerMac, through the PMU), and
    /// AOK VM, as UTM SE does, exits with it.
    func testGuestPowerOff() {
        vm.activate()
        vm.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.6)).tap()
        sleep(1)
        vm.typeText("poweroff -f\n")
        var i = 0
        while vm.state == .runningForeground && i < 30 { sleep(1); i += 1 }
        note("AOK VM \(vm.state.rawValue) after \(i) s")
    }
}
