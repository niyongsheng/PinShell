import XCTest
@testable import PinShellCore

final class ShortcutComboTests: XCTestCase {
    func testDisplayUsesAppleModifierOrder() {
        let combo = ShortcutCombo(keyCode: 40,
                                  modifiers: [.command, .shift, .option, .control],
                                  key: "k")
        XCTAssertEqual(combo.displayString, "⌃⌥⇧⌘K")
    }

    func testLettersNormalizeToLowercase() {
        let combo = ShortcutCombo(keyCode: 4,
                                  modifiers: [.command, .shift],
                                  characters: "H")
        XCTAssertEqual(combo?.key, "h")
        XCTAssertEqual(combo?.displayString, "⇧⌘H")
    }

    func testShiftedNumberUsesBaseKey() {
        let combo = ShortcutCombo(keyCode: 18,
                                  modifiers: [.command, .shift],
                                  characters: "!")
        XCTAssertEqual(combo?.key, "1")
        XCTAssertEqual(combo?.displayString, "⇧⌘1")
    }

    func testSpecialKeysUseSymbols() {
        let ret = ShortcutCombo(keyCode: 36,
                                modifiers: [.command],
                                characters: "\r")
        XCTAssertEqual(ret?.displayString, "⌘↩")

        let escape = ShortcutCombo(keyCode: 53,
                                   modifiers: [.option],
                                   characters: "\u{1b}")
        XCTAssertEqual(escape?.displayString, "⌥⎋")

        let f5 = ShortcutCombo(keyCode: 96,
                               modifiers: [.control],
                               characters: "\u{F708}")
        XCTAssertEqual(f5?.displayString, "⌃F5")
    }

    func testSpaceIsNamed() {
        let combo = ShortcutCombo(keyCode: 49,
                                  modifiers: [.command],
                                  characters: " ")
        XCTAssertEqual(combo?.displayString, "⌘Space")
    }

    func testValidityRequiresCommandOptionOrControl() {
        let shiftOnly = ShortcutCombo(keyCode: 4,
                                      modifiers: [.shift],
                                      key: "h")
        XCTAssertFalse(shiftOnly.isValid)

        let command = ShortcutCombo(keyCode: 40,
                                    modifiers: [.command],
                                    key: "k")
        XCTAssertTrue(command.isValid)
    }

    func testEmptyCharactersProduceNil() {
        XCTAssertNil(ShortcutCombo(keyCode: 4, modifiers: [.command], characters: ""))
    }

    func testMatchingIgnoresLayoutCharacter() {
        let combo = ShortcutCombo(keyCode: 35,
                                  modifiers: [.control, .option],
                                  key: "p")
        XCTAssertTrue(combo.matches(keyCode: 35, modifiers: [.control, .option]))
        XCTAssertFalse(combo.matches(keyCode: 35, modifiers: [.command]))
        XCTAssertFalse(combo.matches(keyCode: 17, modifiers: [.control, .option]))

        // 同一物理键位在不同布局下字符不同，仍视为同一组合。
        let otherLayout = ShortcutCombo(keyCode: 35,
                                        modifiers: [.control, .option],
                                        key: "з")
        XCTAssertTrue(combo.isEquivalent(to: otherLayout))
    }

    func testCodableRoundTrip() throws {
        let combo = ShortcutCombo(keyCode: 35,
                                  modifiers: [.control, .option, .shift],
                                  key: "p")
        let data = try JSONEncoder().encode(combo)
        let decoded = try JSONDecoder().decode(ShortcutCombo.self, from: data)
        XCTAssertEqual(decoded, combo)
        XCTAssertEqual(decoded.displayString, "⌃⌥⇧P")
    }
}
