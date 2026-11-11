import XCTest
@testable import EsysCore

/// Exercises the full client stack against the in-process virtual car:
/// connect → identity → SVT scan → coding read → security → write → verify →
/// restore. No real car, no network hardware.
final class MockCarEndToEndTests: XCTestCase {
    func testFullWorkflow() async throws {
        let car = MockCar()
        try await car.start()
        defer { car.stop() }

        let connection = HSFZConnection()
        try await connection.connect(to: "127.0.0.1", port: car.port)
        defer { connection.close() }
        XCTAssertTrue(connection.isOpen)

        let session = VehicleSession(transport: connection)

        // 1. Identity from the gateway (VCM DIDs).
        let identity = await session.readIdentity()
        XCTAssertEqual(identity.vin, car.vin)
        XCTAssertEqual(identity.iStepText.first, "F025-17-07-503")

        // 2. SVT scan finds the head unit by name and reads its SVK.
        let modules = await session.scanSVT(range: 0x10...0x70, dwell: 0.05)
        let hu = SVTScan.find(named: "HU_NBT", in: modules)
        XCTAssertEqual(hu?.address, BMWAddresses.huNBT)
        XCTAssertEqual(hu?.svk?.primaryCAFD?.id, 0x0000F007)
        XCTAssertTrue(modules.contains { $0.name == "KOMBI" })

        // 3. Coding read discovers the sections and snapshots them (with SVK).
        let backup = try await session.readCoding(ecu: car.huNBTAddress, ecuName: "HU_NBT")
        XCTAssertEqual(backup.sections.map(\.did), [0x3000, 0x3001, 0x3002, 0x3010])
        XCTAssertEqual(backup.sectionBytes(0x3000)?.count, 256)
        XCTAssertEqual(backup.sectionBytes(0x3000)?[96], 0x00)
        let svkHex = try XCTUnwrap(backup.svkHex)
        XCTAssertEqual(SVK.parse(try XCTUnwrap(Bytes.fromHex(svkHex))).primaryCAFD?.id,
                       0x0000F007)

        // 4. Writing without a security algorithm fails with a clear error.
        do {
            _ = try await session.applyOperations([MockCar.demoOperation()], to: backup, security: nil)
            XCTFail("expected a security error")
        } catch let error as SecurityAccessError {
            guard case .noAlgorithm = error else { return XCTFail("unexpected error: \(error)") }
        } catch {
            XCTFail("unexpected error type: \(error)")
        }

        // 5. Apply the demo edit with security unlock and verification.
        let modified = try await session.applyOperations(
            [MockCar.demoOperation()], to: backup, security: MockCarAlgorithm())
        XCTAssertEqual(car.codingBytes(did: 0x3000)?[96], 0x10)
        XCTAssertEqual(modified.sectionBytes(0x3000)?[96], 0x10)
        let diffs = backup.diff(to: modified)
        XCTAssertEqual(diffs.count, 1)
        XCTAssertEqual(diffs[0].changes, [ByteChange(offset: 96, from: 0x00, to: 0x10)])

        // 6. Applying the same edit again is a no-op.
        let again = try await session.applyOperations(
            [MockCar.demoOperation()], to: modified, security: MockCarAlgorithm())
        XCTAssertEqual(again.diff(to: modified), [])

        // 7. Restore returns the ECU to the backup state.
        try await session.restore(backup, security: MockCarAlgorithm())
        XCTAssertEqual(car.codingBytes(did: 0x3000)?[96], 0x00)
        let reread = try await session.readCoding(ecu: car.huNBTAddress, ecuName: "HU_NBT",
                                                  dids: [0x3000])
        XCTAssertEqual(reread.sectionBytes(0x3000), backup.sectionBytes(0x3000))
    }

    func testBackupPersistenceRoundTrip() throws {
        var backup = CodingBackup(vin: "WBA8E9G51GNT00042", ecuAddress: 0x63, ecuName: "HU_NBT",
                                  sections: [CodingSection(did: 0x3000, bytes: [1, 2, 3])])
        backup.replace(section: CodingSection(did: 0x3000, bytes: [1, 2, 4]))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("esys-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try backup.save(to: url)
        let loaded = try CodingBackup.load(from: url)
        XCTAssertEqual(loaded.vin, backup.vin)
        XCTAssertEqual(loaded.ecuAddress, 0x63)
        XCTAssertEqual(loaded.ecuName, "HU_NBT")
        XCTAssertEqual(loaded.sections, backup.sections)
        XCTAssertEqual(loaded.sectionBytes(0x3000), [1, 2, 4])
    }
}
