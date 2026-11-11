import XCTest
@testable import EsysCore

/// HSFZ codec tests, validated against real captured traffic published with
/// the MIT-licensed bmw-enet-tool (ISTA talking to an F10 over ENET).
final class HSFZTests: XCTestCase {
    /// ISTA "define frame": 10-byte body [F4][12] + UDS 2C 01 F3 00 58 15 01 01.
    func testDiagFrameEncodingMatchesCapturedTraffic() {
        let frame = HSFZFrame.diag(src: 0xF4, dst: 0x12,
                                   uds: [0x2C, 0x01, 0xF3, 0x00, 0x58, 0x15, 0x01, 0x01])
        XCTAssertEqual(frame.encoded(),
                       [0x00, 0x00, 0x00, 0x0A, 0x00, 0x01, 0xF4, 0x12,
                        0x2C, 0x01, 0xF3, 0x00, 0x58, 0x15, 0x01, 0x01])
    }

    /// ISTA "value response": body [12][F4] + UDS 62 F3 00 93.
    func testParseCapturedResponse() throws {
        let bytes: [UInt8] = [0x00, 0x00, 0x00, 0x06, 0x00, 0x01, 0x12, 0xF4, 0x62, 0xF3, 0x00, 0x93]
        let frame = try XCTUnwrap(try HSFZFrame.parse(bytes))
        XCTAssertEqual(frame.control, HSFZControl.diag.rawValue)
        XCTAssertEqual(frame.src, 0x12)
        XCTAssertEqual(frame.dst, 0xF4)
        XCTAssertEqual(frame.uds, [0x62, 0xF3, 0x00, 0x93])
    }

    func testIdentRequestWireFormat() {
        XCTAssertEqual(HSFZDiscovery.identRequest(), [0x00, 0x00, 0x00, 0x00, 0x00, 0x11])
    }

    func testFragmentedFrameNeedsAllBytes() throws {
        let bytes: [UInt8] = [0x00, 0x00, 0x00, 0x06, 0x00, 0x01, 0x12, 0xF4, 0x62, 0xF3, 0x00, 0x93]
        XCTAssertNil(try HSFZFrame.parse(Array(bytes[0..<5])))
        XCTAssertNil(try HSFZFrame.parse(Array(bytes[0..<11])))
        XCTAssertNotNil(try HSFZFrame.parse(bytes))
    }

    func testErrorControlWords() {
        XCTAssertEqual(HSFZProtocolError.from(controlWord: 0x43), .incorrectDestinationAddress)
        XCTAssertEqual(HSFZProtocolError.from(controlWord: 0xFF), .outOfMemory)
        XCTAssertNil(HSFZProtocolError.from(controlWord: 0x0002))
    }

    func testAdvertisementParsing() {
        let payload = Array("DIAGADR10BMWMAC001A37DEC550BMWVINWBA8E9G51GNT12345".utf8)
        let ad = VehicleAdvertisement.parse(host: "169.254.9.103", payload: payload)
        XCTAssertEqual(ad.gatewayAddress, 0x10)
        XCTAssertEqual(ad.mac, "001A37DEC550")
        XCTAssertEqual(ad.vin, "WBA8E9G51GNT12345")
    }
}
