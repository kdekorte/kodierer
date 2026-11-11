import XCTest
@testable import KodiererCore

final class CAFDNamesTests: XCTestCase {
    /// The optional 9th CATEGORY column: parsed, and used for the
    /// BimmerCode-style grouping; older 8-column files still parse.
    func testCategoryColumn() throws {
        let names = CAFDNames.parse(text: """
        # CAFD_ID\tADDRESS\tSTART\tEND\tMASK\tVALUE_HEX\tNAME\tCOMMENT\tCATEGORY
        ANY\t3000\t96\t96\t16\t\tCARPLAY_FULLSCREEN\tdemo\tMedia
        ANY\t3000\t96\t96\t16\t10\tFullscreen\t\tMedia
        ANY\t3000\t30\t30\t255\t\tSTARTUP_SCREEN\t\tDisplay
        ANY\t3000\t42\t42\t1\t\tVIDEO_SPEED_LOCK\t\t
        """)
        XCTAssertEqual(names.entries.count, 4)
        XCTAssertEqual(names.entries[0].category, "Media")
        XCTAssertNil(names.entries[3].category)

        let cafd = try CAFD.parse(data: Data(KodiererDemo.xmlForNamesTests.utf8))
        let group = try XCTUnwrap(cafd.datagroup(address: 0x3000))
        let carPlay = try XCTUnwrap(group.functions.first { $0.start == 96 })
        XCTAssertEqual(names.functionCategory(datagroup: group, function: carPlay), "Media")
        let startup = try XCTUnwrap(group.functions.first { $0.start == 30 })
        XCTAssertEqual(names.functionCategory(datagroup: group, function: startup), "Display")
        let speedLock = try XCTUnwrap(group.functions.first { $0.start == 42 })
        XCTAssertNil(names.functionCategory(datagroup: group, function: speedLock))
        // The function row itself still resolves its name.
        XCTAssertEqual(names.functionName(datagroup: group, function: speedLock), "VIDEO_SPEED_LOCK")
    }
}

/// Minimal CAFD XML for the names tests (not the app's demo data).
enum KodiererDemo {
    static let xmlForNamesTests = """
    <?xml version="1.0" encoding="UTF-8"?>
    <caf:cafd xmlns:caf="http://bmw.com/2005/psdz.data.caf">
      <caf:data>
        <caf:datagroup address="3000" units="256">
          <caf:function>
            <caf:storageInfo><caf:start>96</caf:start><caf:end>96</caf:end><caf:mask>00010000b</caf:mask></caf:storageInfo>
            <caf:condParam><caf:values><caf:unitVal position="0">00</caf:unitVal></caf:values></caf:condParam>
            <caf:condParam><caf:values><caf:unitVal position="0">10</caf:unitVal></caf:values></caf:condParam>
          </caf:function>
          <caf:function>
            <caf:storageInfo><caf:start>30</caf:start><caf:end>30</caf:end><caf:mask>11111111b</caf:mask></caf:storageInfo>
            <caf:condParam><caf:values><caf:unitVal position="0">00</caf:unitVal></caf:values></caf:condParam>
          </caf:function>
          <caf:function>
            <caf:storageInfo><caf:start>42</caf:start><caf:end>42</caf:end><caf:mask>00000001b</caf:mask></caf:storageInfo>
            <caf:condParam><caf:values><caf:unitVal position="0">00</caf:unitVal></caf:values></caf:condParam>
          </caf:function>
        </caf:datagroup>
      </caf:data>
    </caf:cafd>
    """
}
