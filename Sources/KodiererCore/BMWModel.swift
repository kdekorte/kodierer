import Foundation

/// Well-known BMW F-series diagnostic addresses (single byte, HSFZ addressing).
///
/// The head unit address is expected to be 0x63 on F-series (HU_CIC era used
/// nearby addresses; G-series MGU also sits at 0x63 per public tools). The app
/// never trusts these blindly — it discovers the actual SVT by scanning
/// addresses with TesterPresent + ReadDataByIdentifier(F197).
public enum BMWAddresses {
    /// Our tester address on HSFZ.
    public static let tester: UInt8 = 0xF4
    /// Functional (broadcast to all ECUs) address.
    public static let functional: UInt8 = 0xDF
    /// Central gateway (ZGW). Also answers VCM DIDs (FA / FP / I-Step).
    public static let gateway: UInt8 = 0x10
    /// Engine (DME).
    public static let dme: UInt8 = 0x12
    /// Front electronic module.
    public static let fem: UInt8 = 0x40
    /// Instrument cluster.
    public static let kombi: UInt8 = 0x60
    /// Head unit NBT / NBT EVO (expected — verify with SVT scan).
    public static let huNBT: UInt8 = 0x63
    /// Rear electronic module.
    public static let rem: UInt8 = 0x72
}

/// Data identifiers (DIDs) used by BMW F-series modules.
public enum BMWDID {
    /// VIN.
    public static let vin: UInt16 = 0xF190
    /// ECU name, e.g. "HU_NBT".
    public static let ecuName: UInt16 = 0xF197
    /// Hardware number.
    public static let hwNumber: UInt16 = 0xF191
    /// Software version.
    public static let swVersion: UInt16 = 0xF189
    /// Which SGBD (ECU description file) the module belongs to.
    public static let sgbdIndex: UInt16 = 0xF150
    /// Software version container (list of installed SGBMIDs incl. the CAFD).
    public static let svk: UInt16 = 0xF101
    /// Currently active diagnostic session.
    public static let activeSession: UInt16 = 0xF186
    /// Vehicle order (FA) — lives on the gateway (VCM).
    public static let fa: UInt16 = 0x3F06
    /// Vehicle profile (FP) — lives on the gateway (VCM).
    public static let fp: UInt16 = 0x3F09
    /// Integration step (I-Step), e.g. F020-17-07-503 — lives on the gateway.
    public static let iStep: UInt16 = 0x100B
    /// Coding stamp: last 7 VIN chars the module was coded on.
    public static let codingStamp: UInt16 = 0x37FE

    /// Range of DIDs that hold FDL coding data ("sections"). An NCD block's
    /// memory address is DID * 256 + offset; block numbers are written in hex
    /// (3000, 3062, ...) and double as the UDS DIDs, so the numeric range is
    /// 0x3000...0x30FF. The authoritative per-ECU list lives in its CAFD
    /// (CAFD.swift); this range is only the discovery default.
    public static let codingSectionRange: ClosedRange<Int> = 0x3000...0x30FF
}

/// One entry of the SVK (software version container, DID 0xF101): a software
/// module (SGBMID) with process class, id and version.
public struct SVKEntry: Equatable, Sendable {
    public let processClass: UInt8
    public let id: UInt32
    public let mainVersion: UInt8
    public let subVersion: UInt8
    public let patchVersion: UInt8

    /// "CAFD_00000794_010_002_054" style name.
    public var fileName: String {
        String(format: "%@_%08X_%03d_%03d_%03d",
               SVK.processClassName(processClass), id, mainVersion, subVersion, patchVersion)
    }
}

/// Parsed SVK: a 16-byte header followed by 8-byte SGBMID entries
/// (1 byte process class code, 4 byte id, 3 version bytes).
public struct SVK: Equatable, Sendable {
    public let header: [UInt8]
    public let entries: [SVKEntry]

    public var cafdEntries: [SVKEntry] { entries.filter { $0.processClass == SVK.cafdProcessClass } }

    /// The CAFD whose coding data is in the module (nil when erased — E-Sys
    /// then shows CAFD_FFFFFFFF).
    public var primaryCAFD: SVKEntry? { cafdEntries.first }

    public static func parse(_ bytes: [UInt8]) -> SVK {
        guard bytes.count >= 16 else { return SVK(header: bytes, entries: []) }
        var entries: [SVKEntry] = []
        var offset = 16
        while offset + 8 <= bytes.count {
            let entry = SVKEntry(
                processClass: bytes[offset],
                id: UInt32(bytes[offset + 1]) << 24 | UInt32(bytes[offset + 2]) << 16
                    | UInt32(bytes[offset + 3]) << 8 | UInt32(bytes[offset + 4]),
                mainVersion: bytes[offset + 5],
                subVersion: bytes[offset + 6],
                patchVersion: bytes[offset + 7])
            // All-0xFF entries are erased slots (e.g. CAFD_FFFFFFFF after a flash).
            if entry.id != 0xFFFFFFFF || entry.processClass != 0xFF {
                entries.append(entry)
            }
            offset += 8
        }
        return SVK(header: Array(bytes[0..<16]), entries: entries)
    }

    /// Process class code for CAFDs (coding data containers).
    /// 0x11 has been observed for CAFD entries in SVKs; kept as a constant so
    /// tests and live captures can adjust in one place.
    public static let cafdProcessClass: UInt8 = 0x11

    static func processClassName(_ code: UInt8) -> String {
        switch code {
        case cafdProcessClass: return "CAFD"
        default: return String(format: "PC_%02X", code)
        }
    }
}
