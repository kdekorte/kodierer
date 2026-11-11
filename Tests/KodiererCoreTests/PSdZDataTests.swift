import XCTest
@testable import KodiererCore

final class PSdZDataTests: XCTestCase {
    func testFileNameParsing() {
        let name = SWEFileName.parse("cafd_00000F07.caf.013_001_009")
        XCTAssertEqual(name?.kind, "cafd")
        XCTAssertEqual(name?.id, 0x00000F07)
        XCTAssertEqual(name?.ext, "caf")
        XCTAssertEqual(name?.main, 13)
        XCTAssertEqual(name?.sub, 1)
        XCTAssertEqual(name?.patch, 9)
        XCTAssertEqual(name?.version, "013_001_009")
        XCTAssertEqual(name?.fileName, "cafd_00000F07.caf.013_001_009")
        XCTAssertEqual(name?.longName, "CAFD_00000F07_013_001_009")

        XCTAssertEqual(SWEFileName.parse("swfl_00004693.bin.005_000_000")?.id, 0x00004693)
        // Uppercase input still parses.
        XCTAssertNotNil(SWEFileName.parse("CAFD_0000F007.CAF.013_001_009"))
        XCTAssertNil(SWEFileName.parse("readme.txt"))
        XCTAssertNil(SWEFileName.parse("cafd_123.caf.1_2_3"))
        XCTAssertNil(SWEFileName.parse("cafd_00000F07.caf"))
    }

    func testStoreLocatesCAFDs() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("kodierer-psdz-\(UUID().uuidString)")
        let cafdFolder = root.appendingPathComponent("swe/cafd")
        let swflFolder = root.appendingPathComponent("swe/swfl")
        try FileManager.default.createDirectory(at: cafdFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: swflFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let files = ["cafd_00000F07.caf.012_000_003", "cafd_00000F07.caf.013_001_009",
                     "cafd_00000F07.caf.013_000_000", "cafd_00001234.caf.001_001_001",
                     "notes.txt"]
        for file in files {
            try Data([0x00]).write(to: cafdFolder.appendingPathComponent(file))
        }
        try Data([0x00]).write(to: swflFolder.appendingPathComponent("swfl_00004693.bin.005_000_000"))

        let store = PSdZDataStore(path: root.path)
        XCTAssertEqual(store.sweRoot, root.appendingPathComponent("swe"))
        XCTAssertEqual(store.files(kind: "cafd").count, 4)
        XCTAssertEqual(store.files(kind: "cafd", id: 0x00000F07).map(\.name.version),
                       ["012_000_003", "013_000_000", "013_001_009"])   // oldest first
        // Newest version wins without an explicit version.
        XCTAssertEqual(store.cafdFile(id: 0x00000F07)?.name.version, "013_001_009")
        // Exact version match.
        XCTAssertEqual(store.cafdFile(id: 0x00000F07, version: (12, 0, 3))?.name.version,
                       "012_000_003")
        XCTAssertNil(store.cafdFile(id: 0x00009999))

        // A parent of the psdzdata folder works too.
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("kodierer-psdz-parent-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: parent) }
        try FileManager.default.createDirectory(
            at: parent.appendingPathComponent("psdzdata/swe/cafd"), withIntermediateDirectories: true)
        try Data([0x00]).write(to: parent.appendingPathComponent(
            "psdzdata/swe/cafd/cafd_00000F07.caf.013_001_009"))
        let parentStore = PSdZDataStore(path: parent.path)
        XCTAssertEqual(parentStore.files(kind: "cafd").count, 1)

        // No swe tree: nothing found, no crash.
        let empty = PSdZDataStore(path: FileManager.default.temporaryDirectory.path)
        XCTAssertNil(empty.sweRoot)
        XCTAssertTrue(empty.files(kind: "cafd").isEmpty)
    }

    func testProbeIdentifiesContent() throws {
        let xml = CAFDTests.sampleXML
        // Plain CAFD XML.
        XCTAssertEqual(CAFDProbe.probe(data: Data(xml.utf8), series: "F025").kind, .cafdXML)
        // Gzip-wrapped (OpenCAFDMap cache format).
        let gzipped = try XCTUnwrap(Bytes.fromHex(CAFDTests.sampleGzipHex))
        let gzipProbe = CAFDProbe.probe(data: Data(gzipped), series: "F025")
        XCTAssertEqual(gzipProbe.kind, .gzipCAFDXML)
        XCTAssertEqual(gzipProbe.cafd?.datagroups.count, 2)
        // XML that is not CAFD data.
        XCTAssertEqual(CAFDProbe.probe(data: Data("<foo/>".utf8)).kind, .notCAFD)
        // Random binary — the PSdZ-encrypted .caf case.
        XCTAssertEqual(CAFDProbe.probe(data: Data((0..<64).map { UInt8(($0 &* 31 &+ 7) & 0xFF) })).kind,
                       .encrypted)
        // Empty file.
        XCTAssertEqual(CAFDProbe.probe(data: Data()).kind, .encrypted)
    }
}
