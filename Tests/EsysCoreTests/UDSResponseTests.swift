import XCTest
@testable import EsysCore

final class UDSResponseTests: XCTestCase {
    func testRequestBuilders() {
        XCTAssertEqual(UDS.readDID(3062), [0x22, 0x0B, 0xF6])          // 3062 = 0x0BF6
        XCTAssertEqual(UDS.writeDID(3000, [0x01]), [0x2E, 0x0B, 0xB8, 0x01])
        XCTAssertEqual(UDS.testerPresent(), [0x3E, 0x80])
        XCTAssertEqual(UDS.securitySeedRequest(level: 0x11), [0x27, 0x11])
        XCTAssertEqual(UDS.session(UDS.extendedSession), [0x10, 0x03])
    }

    func testAnswersReadDID() {
        let request = UDS.readDID(3000)
        XCTAssertTrue(udsAnswers(request: request, response: [0x62, 0x0B, 0xB8, 0x00]))
        XCTAssertFalse(udsAnswers(request: request, response: [0x62, 0x0B, 0xB9, 0x00]))
        XCTAssertFalse(udsAnswers(request: request, response: [0x6E, 0x0B, 0xB8]))
    }

    func testAnswersNegative() {
        XCTAssertTrue(udsAnswers(request: UDS.readDID(3000), response: [0x7F, 0x22, 0x31]))
        XCTAssertFalse(udsAnswers(request: UDS.writeDID(3000, []), response: [0x7F, 0x22, 0x31]))
    }

    func testAnswersTesterPresentWithSuppressedBit() {
        XCTAssertTrue(udsAnswers(request: [0x3E, 0x80], response: [0x7E, 0x00]))
    }

    func testAnswersWriteDID() {
        let request = UDS.writeDID(3062, [32, 32])
        XCTAssertTrue(udsAnswers(request: request, response: [0x6E, 0x0B, 0xF6]))
    }

    func testResponseParsing() {
        let negative = UDSResponse(raw: [0x7F, 0x2E, 0x33])
        XCTAssertTrue(negative.isNegative)
        XCTAssertEqual(negative.requestSID, 0x2E)
        XCTAssertEqual(negative.nrc, UDSNRC.securityAccessDenied.rawValue)
        XCTAssertFalse(negative.isPending)

        let pending = UDSResponse(raw: [0x7F, 0x22, 0x78])
        XCTAssertTrue(pending.isPending)

        let positive = UDSResponse(raw: [0x62, 0x0B, 0xB8, 0xAB])
        XCTAssertFalse(positive.isNegative)
        XCTAssertEqual(positive.requestSID, 0x22)
        XCTAssertEqual(positive.data, [0x0B, 0xB8, 0xAB])
    }
}

final class SVKTests: XCTestCase {
    func testParseEntries() {
        // 16-byte header + two 8-byte entries.
        var bytes = [UInt8](repeating: 0, count: 16)
        bytes[0] = 0x02
        bytes += [0x11, 0x00, 0x00, 0xF0, 0x07, 0x0D, 0x01, 0x09] // CAFD 0xF007 v13.1.9
        bytes += [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF] // erased slot -> skipped
        let svk = SVK.parse(bytes)
        XCTAssertEqual(svk.entries.count, 1)
        XCTAssertEqual(svk.primaryCAFD?.id, 0x0000F007)
        XCTAssertEqual(svk.primaryCAFD?.fileName, "CAFD_0000F007_013_001_009")
    }
}
