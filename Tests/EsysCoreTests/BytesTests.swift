import XCTest
@testable import EsysCore

final class BytesTests: XCTestCase {
    func testHexRoundTrip() {
        let bytes: [UInt8] = [0x00, 0xFF, 0x0A, 0x93]
        XCTAssertEqual(Bytes.hexCompact(bytes), "00FF0A93")
        XCTAssertEqual(Bytes.fromHex("00FF0A93"), bytes)
        XCTAssertEqual(Bytes.fromHex("00 FF 0A 93"), bytes)
        XCTAssertNil(Bytes.fromHex("0"))
        XCTAssertNil(Bytes.fromHex("ZZ"))
    }

    func testInterfaceListing() {
        // Loopback is always there; a healthy Mac also lists en0 etc.
        let interfaces = NetworkInterfaces.list()
        XCTAssertTrue(interfaces.contains { $0.name == "lo0" && $0.ipv4.contains("127.0.0.1") })
    }
}
