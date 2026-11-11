import XCTest
@testable import KodiererCore

final class NCDTests: XCTestCase {
    /// Builds one Motorola S-record line, checksum and all.
    private func record(_ type: Int, address: [UInt8], data: [UInt8]) -> String {
        let count = UInt8(address.count + data.count + 1)
        let body = [count] + address + data
        let checksum = UInt8((~body.reduce(0) { $0 + Int($1) }) & 0xFF)
        return "S\(type)" + (body + [checksum]).map { String(format: "%02X", $0) }.joined()
    }

    private func threeByteAddress(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
    }

    func testParsesSRecords() throws {
        // S0 header: CAFD 00000F07 version 013_001_009 (write_ncd layout).
        let s0 = record(0, address: [0x00, 0x00],
                        data: [0x00, 0x00, 0x0F, 0x07, 13, 1, 9])
        // S2: 32 bytes at 0x300000 (block 0x3000, offset 0) + 16 more at +32.
        var block: [UInt8] = (0..<32).map { UInt8($0) }
        block += (0..<16).map { UInt8(0x40 + $0) }
        let s2a = record(2, address: threeByteAddress(0x3000 << 8), data: Array(block[0..<32]))
        let s2b = record(2, address: threeByteAddress((0x3000 << 8) + 32), data: Array(block[32..<48]))
        // A second block at 0x3062.
        let s2c = record(2, address: threeByteAddress(0x3062 << 8), data: [0xAA, 0xBB])
        // Unrelated record types are skipped.
        let s5 = record(5, address: [0x00, 0x01], data: [])

        let ncd = try NCD.parse(text: [s0, s2a, s2b, s2c, s5].joined(separator: "\n") + "\n")
        XCTAssertEqual(ncd.cafdID, 0x00000F07)
        XCTAssertEqual(ncd.version?.main, 13)
        XCTAssertEqual(ncd.version?.sub, 1)
        XCTAssertEqual(ncd.version?.patch, 9)
        XCTAssertEqual(ncd.sections.map(\.did), [0x3000, 0x3062])
        XCTAssertEqual(ncd.sections.first?.bytes, block)
        XCTAssertEqual(ncd.sections.last?.bytes, [0xAA, 0xBB])
    }

    func testRejectsBadChecksum() {
        let good = record(2, address: threeByteAddress(0x3000 << 8), data: [1, 2, 3])
        // Flip one data nibble.
        let bad = good.replacingOccurrences(of: "010203", with: "010204")
        XCTAssertNotEqual(good, bad)
        XCTAssertThrowsError(try NCD.parse(text: bad)) { error in
            guard case NCD.NCDError.badChecksum = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testBackupConversion() throws {
        let s2 = record(2, address: threeByteAddress(0x3000 << 8), data: [9, 8, 7])
        let ncd = try NCD.parse(text: s2 + "\n")
        let backup = ncd.backup(ecuAddress: 0x63, ecuName: "HU_NBT")
        XCTAssertEqual(backup.ecuAddress, 0x63)
        XCTAssertEqual(backup.sectionBytes(0x3000), [9, 8, 7])
    }
}
