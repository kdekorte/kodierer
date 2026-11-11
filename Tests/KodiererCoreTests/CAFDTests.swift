import XCTest
@testable import KodiererCore

final class CAFDTests: XCTestCase {
    /// CAFD XML in the shape BMW's PsdZ library writes (namespace prefix "caf",
    /// per OpenCAFDMap's decrypted cache): one HU_NBT-style datagroup with a
    /// byte-96/bit-4 function (the CarPlay-style demo parameter) and a plain
    /// byte function, plus a second datagroup.
    static let sampleXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <caf:cafd xmlns:caf="http://bmw.com/2005/psdz.data.caf">
      <caf:fpInfo>
        <caf:mainSeries name="F025"/>
        <caf:mainSeries name="F020"/>
      </caf:fpInfo>
      <caf:data>
        <caf:datagroup address="3000" datagroupClass="USER" units="256">
          <caf:activatingCondition>
            <caf:boolExpression mainSeries="F025" isDefault="true">//cat[@val='F025']</caf:boolExpression>
          </caf:activatingCondition>
          <caf:function>
            <caf:storageInfo>
              <caf:start>96</caf:start>
              <caf:end>96</caf:end>
              <caf:size>1</caf:size>
              <caf:mask>00010000b</caf:mask>
            </caf:storageInfo>
            <caf:condParam>
              <caf:bool mainSeries="F025" isDefault="true">//cat[@val='F025' and not(SA6CP)]</caf:bool>
              <caf:values>
                <caf:unitVal position="0">00</caf:unitVal>
              </caf:values>
            </caf:condParam>
            <caf:condParam>
              <caf:bool mainSeries="F025">//cat[@val='F025' and SA6CP]</caf:bool>
              <caf:values>
                <caf:unitVal position="0">10</caf:unitVal>
              </caf:values>
            </caf:condParam>
          </caf:function>
          <caf:function>
            <caf:storageInfo>
              <caf:start>68</caf:start>
              <caf:end>68</caf:end>
              <caf:mask>11111111b</caf:mask>
            </caf:storageInfo>
            <caf:condParam>
              <caf:values>
                <caf:unitVal position="0">32</caf:unitVal>
              </caf:values>
            </caf:condParam>
          </caf:function>
        </caf:datagroup>
        <caf:datagroup address="3062" datagroupClass="USER" units="128">
          <caf:function>
            <caf:storageInfo>
              <caf:start>0</caf:start>
              <caf:end>0</caf:end>
              <caf:mask>11111111b</caf:mask>
            </caf:storageInfo>
            <caf:condParam>
              <caf:bool mainSeries="F025" isDefault="true">//cat[@val='F025']</caf:bool>
              <caf:values>
                <caf:unitVal position="0">00</caf:unitVal>
              </caf:values>
            </caf:condParam>
          </caf:function>
        </caf:datagroup>
      </caf:data>
    </caf:cafd>
    """

    /// The same XML, gzip-wrapped exactly as `gzip -c -n` produces it — the
    /// format of OpenCAFDMap's decrypted CAFD cache (.xml.gz).
    static let sampleGzipHex =
        "1f8b0800000000000003cd555d6fdb20147dcfaf40bcb47b58c0ae626555ec76ca5a696fd5d2ee65dac38d2129aa0d96c159d55f3f30e43b95b734d566c912dc7b38dc73b8c6a3abe7b2400b5e6ba1648aa33ec588cb5c3121e7297eb8bffd38c457596f94c3ecd2be0c59b8d46e98e24763aa4b42a6e5af7eae4a12533a2095662f7d0606fa1682b31e42edd259f555ce949b864009424e782db846124a9ee25b1a0f30e940508f18916dce16ef36dd58eea6f35a351502c66aae758a2f28b5ea568971012efa30b9f986512385b1937890604f126820376201c6ba31569209635d5ae60362aa5471f35cb92d6c12adcb0e9a90d05ff80c9ac2a4d8d40dc719b1e59b1fd70b28d2330739fbe9056d33adca201d7578831b991f284e1b55c39cafcddfca416db24f89dfc0cf76315cb215c28df738c40bcfa2c0e0c6bb8012f453667d8fec4ba71ed8c6d67592570bf55d67f5de410de51eb7f3eb28bf114886a432e793cfc9f8eec386fd7b7bd8450dd79be190700df31d0a5429dd9e468a29b6423d55486eb19143743e7a40e251d25f51daaa3c9dc8e84422c357bcd3b86febe664d8d5cd4bc4a16e6e1b330acf899bf5ef3cbe88dfcf631f5b5d835d77661277dc99513cc4a7393dda7578f4df9cddd117cdff77b3fc6143ac43f6df4f963fffacf71bc4983de02f080000"

    func testParsesPrefixedNamespaceXML() throws {
        let cafd = try CAFD.parse(data: Data(Self.sampleXML.utf8), series: "F025")
        XCTAssertEqual(cafd.mainSeries, ["F025", "F020"])
        XCTAssertEqual(cafd.datagroups.count, 2)
        XCTAssertEqual(cafd.functionCount, 3)

        let first = try XCTUnwrap(cafd.datagroups.first)
        XCTAssertEqual(first.addressText, "3000")
        XCTAssertEqual(first.address, 0x3000)      // hex block number as numeric DID
        XCTAssertEqual(first.datagroupClass, "USER")
        XCTAssertEqual(first.units, "256")
        guard case .applicable(let activation) = first.activation else {
            return XCTFail("expected an applicable activation rule")
        }
        XCTAssertEqual(activation.series, "F025")

        let carplay = try XCTUnwrap(first.functions.first)
        XCTAssertEqual(carplay.start, 96)
        XCTAssertEqual(carplay.end, 96)
        XCTAssertEqual(carplay.sizeText, "1")
        XCTAssertEqual(carplay.maskText, "00010000b")
        XCTAssertEqual(carplay.mask, 0x10)
        XCTAssertEqual(carplay.values.count, 2)
        XCTAssertEqual(carplay.values[0].hex, "00")
        XCTAssertTrue(carplay.values[0].isDefault)
        XCTAssertEqual(carplay.values[1].hex, "10")
        XCTAssertFalse(carplay.values[1].isDefault)
        XCTAssertEqual(carplay.defaultValue, carplay.values[0])

        // The rule for value 2 selects via SA6CP; check it resolved for F025.
        guard case .applicable(let rule) = carplay.values[1].rule else {
            return XCTFail("expected an applicable value rule")
        }
        XCTAssertTrue(rule.text.contains("SA6CP"))

        // Function without rules is "fixed".
        let brightness = try XCTUnwrap(first.functions.last)
        XCTAssertEqual(brightness.start, 68)
        XCTAssertEqual(brightness.mask, 0xFF)
        XCTAssertEqual(brightness.values.map(\.hex), ["32"])
        XCTAssertEqual(brightness.values[0].rule, .fixed)

        XCTAssertEqual(cafd.datagroups.last?.address, 0x3062)
    }

    func testParsesDefaultNamespaceXML() throws {
        // Same document with a default namespace instead of the "caf:" prefix.
        let xml = Self.sampleXML.replacingOccurrences(of: "caf:", with: "")
            .replacingOccurrences(of: "<cafd ", with: "<cafd xmlns=\"http://bmw.com/2005/psdz.data.caf\" ")
        let cafd = try CAFD.parse(data: Data(xml.utf8), series: "F025")
        XCTAssertEqual(cafd.datagroups.count, 2)
        XCTAssertEqual(cafd.datagroups.first?.functions.first?.mask, 0x10)
    }

    func testParsesGzipWrappedXML() throws {
        let gzipped = try XCTUnwrap(Bytes.fromHex(Self.sampleGzipHex))
        let cafd = try CAFD.parse(data: Data(gzipped), series: "F025")
        XCTAssertEqual(cafd.datagroups.count, 2)
        XCTAssertEqual(cafd.functionCount, 3)
        // The gzip payload must be the sample XML (modulo the trailing
        // newline, which the Swift literal does not carry).
        let unwrapped = try Gzip.unwrapIfGzip(Data(gzipped))
        XCTAssertEqual(
            String(data: unwrapped, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
            Self.sampleXML.trimmingCharacters(in: .whitespacesAndNewlines))
        // Non-gzip data passes through untouched.
        XCTAssertEqual(try Gzip.unwrapIfGzip(Data(Self.sampleXML.utf8)),
                       Data(Self.sampleXML.utf8))
    }

    func testRejectsNonCAFDXML() {
        XCTAssertThrowsError(try CAFD.parse(data: Data("<foo><bar/></foo>".utf8))) { error in
            guard case CAFDError.notCAFDXML = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testValueHelpers() {
        XCTAssertEqual(CAFD.parseAddress("3000"), 0x3000)
        XCTAssertEqual(CAFD.parseAddress("0x3000"), 0x3000)
        XCTAssertEqual(CAFD.parseAddress("3062"), 0x3062)
        XCTAssertEqual(CAFD.parseMask("11111111b"), 0xFF)
        XCTAssertEqual(CAFD.parseMask("00010000b"), 0x10)
        XCTAssertEqual(CAFD.parseMask("FF"), 0xFF)
        XCTAssertNil(CAFD.parseMask("100000000b"))
        XCTAssertEqual(CAFD.parseHexBytes("01"), [0x01])
        XCTAssertEqual(CAFD.parseHexBytes("1"), [0x01])
        XCTAssertEqual(CAFD.parseHexBytes("0123"), [0x01, 0x23])
        XCTAssertNil(CAFD.parseHexBytes("0G"))
    }

    func testDecodeAgainstBackup() throws {
        let cafd = try CAFD.parse(data: Data(Self.sampleXML.utf8), series: "F025")
        let datagroup = try XCTUnwrap(cafd.datagroup(address: 0x3000))
        let function = try XCTUnwrap(datagroup.functions.first)

        var bytes = [UInt8](repeating: 0x00, count: 256)
        bytes[96] = 0x10
        let backup = CodingBackup(vin: nil, ecuAddress: 0x63, ecuName: "HU_NBT",
                                  sections: [CodingSection(did: 0x3000, bytes: bytes)])

        XCTAssertEqual(CAFD.maskedHex(sectionBytes: bytes, function: function), "10")
        // Current value: the SA6CP value (10), not the default (00).
        let current = try XCTUnwrap(cafd.currentValue(of: function, in: datagroup, backup: backup))
        XCTAssertEqual(current.hex, "10")

        // The write operation for that value matches the demo edit shape.
        let operation = try XCTUnwrap(cafd.operation(setting: current, of: function, in: datagroup))
        XCTAssertEqual(operation, FDLOperation(group: 0x3000, start: 96, end: 96,
                                               mask: 0x10, value: .bytes([0x10])))
        // Applying it to an un-set section flips exactly the masked bit.
        var original = bytes
        original[96] = 0x00
        let modified = try operation.applied(to: original)
        XCTAssertEqual(modified[96], 0x10)

        // Sections missing from the backup decode to nil.
        XCTAssertNil(cafd.currentValue(of: function, in: datagroup,
                                       backup: CodingBackup(vin: nil, ecuAddress: 0x63,
                                                            ecuName: nil, sections: [])))
    }

    func testCommunityNamesOverlay() throws {
        let tsv = [
            ["# community names (test fixture)"],
            ["CAFD_ID", "ADDRESS", "START", "END", "MASK", "VALUE_HEX", "NAME", "COMMENT"],
            ["ANY", "3000", "", "", "", "", "HMI", ""],
            ["ANY", "3000", "96", "96", "16", "", "CARPLAY_FULLSCREEN", "from a backup diff"],
            ["ANY", "3000", "96", "96", "16", "10", "Fullscreen", ""],
        ].map { $0.joined(separator: "\t") }.joined(separator: "\n")

        let names = CAFDNames.parse(text: tsv)
        XCTAssertEqual(names.entries.count, 3)   // header + comment skipped

        let cafd = try CAFD.parse(data: Data(Self.sampleXML.utf8), series: "F025")
        let datagroup = try XCTUnwrap(cafd.datagroup(address: 0x3000))
        let function = try XCTUnwrap(datagroup.functions.first)
        XCTAssertEqual(names.groupName(datagroup: datagroup), "HMI")
        XCTAssertEqual(names.functionName(datagroup: datagroup, function: function), "CARPLAY_FULLSCREEN")
        XCTAssertEqual(names.valueName(datagroup: datagroup, function: function,
                                       value: function.values[1]), "Fullscreen")
        // The plain-byte function (mask 0xFF / 255 decimal) is not named here.
        XCTAssertNil(names.functionName(datagroup: datagroup, function: datagroup.functions[1]))
    }
}
