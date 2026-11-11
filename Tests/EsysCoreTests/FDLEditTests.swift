import XCTest
@testable import EsysCore

final class FDLEditTests: XCTestCase {
    /// The "Angel Eyes 50%" cheat from the community FDLCodes.xml:
    /// section 3062, byte 68, mask 11111111b, value 32.
    func testAngelEyes() throws {
        let operation = FDLOperation(group: 3062, start: 68, end: 68, mask: 0xFF, value: .bytes([32]))
        let section = [UInt8](repeating: 0, count: 128)
        let result = try operation.applied(to: section)
        XCTAssertEqual(result[68], 32)
        XCTAssertEqual(result.filter { $0 != 0 }.count, 1)

        let result100 = try FDLOperation(group: 3062, start: 68, end: 68, mask: 0xFF,
                                         value: .bytes([64])).applied(to: section)
        XCTAssertEqual(result100[68], 64)
    }

    func testBitmaskOnlyTouchesMaskedBits() throws {
        let operation = FDLOperation(group: 3000, start: 0, end: 0, mask: 0b0000_1111, value: .bytes([0b0000_0011]))
        let result = try operation.applied(to: [0b1010_1010] + [UInt8](repeating: 0, count: 15))
        // Low nibble (1010) replaced by the value's low nibble (0011).
        XCTAssertEqual(result[0], 0b1010_0011)
    }

    func testSymbolicValues() throws {
        XCTAssertEqual(try FDLValue.parse("aktiv").resolved(byteCount: 1, mask: 0x10), [0x10])
        XCTAssertEqual(try FDLValue.parse("nicht_aktiv").resolved(byteCount: 1, mask: 0x10), [0x00])
        XCTAssertEqual(try FDLValue.parse("32").resolved(byteCount: 1, mask: 0xFF), [32])
        XCTAssertEqual(try FDLValue.parse("0B").resolved(byteCount: 1, mask: 0xFF), [0x0B])
        XCTAssertEqual(try FDLValue.parse("1010b").resolved(byteCount: 1, mask: 0xFF), [0b1010])
    }

    func testCheatCodeApplicationOnBackup() throws {
        var backup = CodingBackup(vin: nil, ecuAddress: 0x63, ecuName: "HU_NBT", sections: [])
        backup.replace(section: CodingSection(did: 3062, bytes: [UInt8](repeating: 0, count: 128)))
        let code = FDLCheatCode(
            cafdID: "00000794", cafdName: "FEM_BODY",
            description: "Angel Eyes Parking Light Brightness 50%",
            operations: [
                FDLOperation(group: 3062, start: 68, end: 68, mask: 0xFF, value: .bytes([32])),
                FDLOperation(group: 3062, start: 80, end: 80, mask: 0xFF, value: .bytes([32])),
            ])
        let modified = try code.applied(to: backup)
        XCTAssertEqual(modified.sectionBytes(3062)?[68], 32)
        XCTAssertEqual(modified.sectionBytes(3062)?[80], 32)
        // The diff reports exactly those two bytes.
        let diff = backup.diff(to: modified)
        XCTAssertEqual(diff.count, 1)
        XCTAssertEqual(diff[0].did, 3062)
        XCTAssertEqual(diff[0].changes.count, 2)
    }

    func testOffsetOutOfRangeFails() {
        let operation = FDLOperation(group: 3000, start: 300, end: 300, mask: 0xFF, value: .bytes([1]))
        XCTAssertThrowsError(try operation.applied(to: [UInt8](repeating: 0, count: 64)))
    }

    func testSectionMissingFails() {
        let backup = CodingBackup(vin: nil, ecuAddress: 0x63, ecuName: nil,
                                  sections: [CodingSection(did: 3000, bytes: [0, 0])])
        let code = FDLCheatCode(cafdID: nil, cafdName: nil, description: "x",
                                operations: [FDLOperation(group: 3062, start: 0, end: 0,
                                                          mask: 0xFF, value: .bytes([1]))])
        XCTAssertThrowsError(try code.applied(to: backup))
    }
}

final class CheatSheetTests: XCTestCase {
    /// A snippet in the exact format of the community FDLCodes.xml files.
    static let sampleXML = """
    <?xml version="1.0" encoding="utf-8" ?>
    <FDL>
        <cafd id="00000794" name="FEM_BODY">
            <code description="Angel Eyes Parking Light Brightness 50%">
                <group id="3062">
                    <function start="68" end="68" mask="11111111b">32</function>
                    <function start="80" end="80" mask="11111111b">32</function>
                </group>
            </code>
            <code description="Enable DRL">
                <group id="3060">
                    <function start="31" end="31" mask="00110000b">TFL_S</function>
                </group>
            </code>
        </cafd>
        <cafd id="0000F007" name="HU_NBT">
            <code description="CarPlay Fullscreen">
                <group id="3000">
                    <function start="96" end="96" mask="00010000b">01</function>
                </group>
            </code>
        </cafd>
    </FDL>
    """

    func testParsing() throws {
        let sheet = try CheatSheet.parse(data: Data(Self.sampleXML.utf8))
        XCTAssertEqual(sheet.cafds.count, 2)
        XCTAssertEqual(sheet.cafd(named: "FEM_BODY")?.codes.count, 2)
        let drl = try XCTUnwrap(sheet.codes(ecuName: "FEM_BODY").first { $0.description == "Enable DRL" })
        XCTAssertEqual(drl.operations, [
            FDLOperation(group: 3060, start: 31, end: 31, mask: 0b00110000, value: .symbolic("TFL_S")),
        ])
        // Filtering by CAFD id works case-insensitively.
        XCTAssertEqual(sheet.codes(cafdID: "0000f007").count, 1)
    }
}
