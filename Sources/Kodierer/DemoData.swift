import Foundation
import KodiererCore

/// Built-in demo definitions — 100% synthetic (mirrors the CLI `kodierer-cli demo`
/// fixtures and MockCar's data) so every screen can be tried without files or
/// hardware. The CarPlay bit here is NOT a real offset for any real CAFD.
enum DemoData {

    static let cafdXML = #"""
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
              <caf:start>30</caf:start>
              <caf:end>30</caf:end>
              <caf:size>1</caf:size>
              <caf:mask>11111111b</caf:mask>
            </caf:storageInfo>
            <caf:condParam>
              <caf:values>
                <caf:unitVal position="0">00</caf:unitVal>
              </caf:values>
            </caf:condParam>
            <caf:condParam>
              <caf:values>
                <caf:unitVal position="0">01</caf:unitVal>
              </caf:values>
            </caf:condParam>
            <caf:condParam>
              <caf:values>
                <caf:unitVal position="0">02</caf:unitVal>
              </caf:values>
            </caf:condParam>
          </caf:function>
          <caf:function>
            <caf:storageInfo>
              <caf:start>42</caf:start>
              <caf:end>42</caf:end>
              <caf:size>1</caf:size>
              <caf:mask>00000001b</caf:mask>
            </caf:storageInfo>
            <caf:condParam>
              <caf:bool mainSeries="F025" isDefault="true">//cat[@val='F025']</caf:bool>
              <caf:values>
                <caf:unitVal position="0">00</caf:unitVal>
              </caf:values>
            </caf:condParam>
            <caf:condParam>
              <caf:bool mainSeries="F020">//cat[@val='F020']</caf:bool>
              <caf:values>
                <caf:unitVal position="0">01</caf:unitVal>
              </caf:values>
            </caf:condParam>
          </caf:function>
          <caf:function>
            <caf:storageInfo>
              <caf:start>55</caf:start>
              <caf:end>55</caf:end>
              <caf:size>1</caf:size>
              <caf:mask>11111111b</caf:mask>
            </caf:storageInfo>
            <caf:condParam>
              <caf:bool mainSeries="F025" isDefault="true">//cat[@val='F025']</caf:bool>
              <caf:values>
                <caf:unitVal position="0">32</caf:unitVal>
              </caf:values>
            </caf:condParam>
            <caf:condParam>
              <caf:bool mainSeries="F025">//cat[@val='F025' and SA6WA]</caf:bool>
              <caf:values>
                <caf:unitVal position="0">40</caf:unitVal>
              </caf:values>
            </caf:condParam>
            <caf:condParam>
              <caf:bool mainSeries="F020">//cat[@val='F020']</caf:bool>
              <caf:values>
                <caf:unitVal position="0">48</caf:unitVal>
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
            <caf:condParam>
              <caf:bool mainSeries="F025">//cat[@val='F025' and SA6WA]</caf:bool>
              <caf:values>
                <caf:unitVal position="0">01</caf:unitVal>
              </caf:values>
            </caf:condParam>
          </caf:function>
        </caf:datagroup>
      </caf:data>
    </caf:cafd>
    """#

    /// Demo names — OpenCAFDMap names/*.tsv format, plus the optional 9th
    /// CATEGORY column that groups options BimmerCode-style.
    static let namesTSV = """
    # Demo names (synthetic) — OpenCAFDMap names/*.tsv format
    # CAFD_ID\tADDRESS\tSTART\tEND\tMASK\tVALUE_HEX\tNAME\tCOMMENT\tCATEGORY
    ANY\t3000\t\t\t\t\tHMI\t\t
    ANY\t3000\t96\t96\t16\t\tCARPLAY_FULLSCREEN\tdemo row — synthetic\tMedia
    ANY\t3000\t96\t96\t16\t00\tNot fullscreen\t\tMedia
    ANY\t3000\t96\t96\t16\t10\tFullscreen\t\tMedia
    ANY\t3000\t30\t30\t255\t\tSTARTUP_SCREEN\tdemo row — synthetic\tDisplay
    ANY\t3000\t30\t30\t255\t00\tWelcome\t\tDisplay
    ANY\t3000\t30\t30\t255\t01\tM logo\t\tDisplay
    ANY\t3000\t30\t30\t255\t02\tMotorsport logo\t\tDisplay
    ANY\t3000\t42\t42\t1\t\tVIDEO_SPEED_LOCK\tdemo row — synthetic\tComfort
    ANY\t3000\t42\t42\t1\t00\tLocked\t\tComfort
    ANY\t3000\t42\t42\t1\t01\tUnlocked\t\tComfort
    ANY\t3000\t55\t55\t255\t\tSTART_VOLUME\tdemo row — synthetic\tMedia
    ANY\t3000\t55\t55\t255\t32\tLow\t\tMedia
    ANY\t3000\t55\t55\t255\t40\tMedium\t\tMedia
    ANY\t3000\t55\t55\t255\t48\tHigh\t\tMedia
    ANY\t3062\t0\t0\t255\t\tAUTO_HOLD\tdemo row — synthetic\tComfort
    ANY\t3062\t0\t0\t255\t00\tInactive\t\tComfort
    ANY\t3062\t0\t0\t255\t01\tActive\t\tComfort
    """

    /// The demo cheat code: the same synthetic bit MockCar's demo uses.
    static func cheatCodes() -> [FDLCheatCode] {
        [FDLCheatCode(cafdID: nil, cafdName: "HU_NBT",
                      description: "CarPlay Fullscreen (demo bit — synthetic)",
                      operations: [MockCar.demoOperation()])]
    }
}
