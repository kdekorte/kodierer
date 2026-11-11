import Foundation

/// An E-Sys NCD: one ECU's coding data as Motorola S-records.
///
/// The S0 header record carries the CAFD id + version; the S2 records place
/// section bytes at `blockAddress * 256 + offset` — the same "addressing" the
/// car uses (an NCD block's memory address is DID * 256 + offset).
///
/// Sources: kdrcoding/fake-car `Car.cs` (LoadNcd), OpenCAFDMap
/// `ocm/cod_import.py` (write_ncd — S0 = CAFD id/version, S2 = 32-byte chunks).
public struct NCD: Sendable {
    public let cafdID: UInt32?
    public let version: (main: Int, sub: Int, patch: Int)?
    public let sections: [CodingSection]

    public init(cafdID: UInt32?, version: (main: Int, sub: Int, patch: Int)?, sections: [CodingSection]) {
        self.cafdID = cafdID
        self.version = version
        self.sections = sections.sorted { $0.did < $1.did }
    }

    public enum NCDError: Error, CustomStringConvertible, Sendable {
        case malformed(line: Int, detail: String)
        case badChecksum(line: Int)

        public var description: String {
            switch self {
            case .malformed(let line, let detail): return "NCD line \(line): \(detail)"
            case .badChecksum(let line): return "NCD line \(line): checksum mismatch"
            }
        }
    }

    /// Parses S-record text. Unknown record types (S1/S3/S5/S7-S9) are skipped,
    /// as in the reference loaders.
    public static func parse(text: String) throws -> NCD {
        var cafdID: UInt32?
        var version: (main: Int, sub: Int, patch: Int)?
        var blocks: [Int: [UInt8]] = [:]

        for (index, rawLine) in text.split(separator: "\n").enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("S") else { continue }
            let record = try parseRecord(line, lineNumber: index + 1)
            switch record.type {
            case "0":
                // Header: 4-byte CAFD id + 3-byte version (write_ncd layout).
                if record.data.count >= 7 {
                    cafdID = UInt32(record.data[0]) << 24 | UInt32(record.data[1]) << 16
                        | UInt32(record.data[2]) << 8 | UInt32(record.data[3])
                    version = (Int(record.data[4]), Int(record.data[5]), Int(record.data[6]))
                }
            case "2":
                let block = Int(record.address >> 8)
                let offset = Int(record.address & 0xFF)
                var bytes = blocks[block] ?? []
                if offset > bytes.count {
                    bytes += [UInt8](repeating: 0, count: offset - bytes.count)
                }
                for (position, byte) in record.data.enumerated() {
                    let target = offset + position
                    if target < bytes.count { bytes[target] = byte } else { bytes.append(byte) }
                }
                blocks[block] = bytes
            default:
                break
            }
        }
        let sections = blocks.keys.sorted().map { CodingSection(did: $0, bytes: blocks[$0]!) }
        return NCD(cafdID: cafdID, version: version, sections: sections)
    }

    public static func parse(url: URL) throws -> NCD {
        try parse(text: String(contentsOf: url, encoding: .utf8))
    }

    /// One S-record: "S<type><count hex><address hex><data hex><checksum hex>".
    private static func parseRecord(_ line: String, lineNumber: Int) throws
        -> (type: String, address: UInt32, data: [UInt8]) {
        let hex = String(line.dropFirst())
        guard let type = hex.first, type.isNumber, let bytes = Bytes.fromHex(String(hex.dropFirst())),
              bytes.count >= 2 else {
            throw NCDError.malformed(line: lineNumber, detail: "not a valid S-record")
        }
        let count = Int(bytes[0])
        guard bytes.count == count + 1 else {
            throw NCDError.malformed(line: lineNumber, detail: "length field \(count) ≠ \(bytes.count - 1)")
        }
        let checksum = Int(bytes[bytes.count - 1])
        let sum = bytes.dropLast().reduce(0) { $0 + Int($1) } & 0xFF
        guard (~sum & 0xFF) == checksum else {
            throw NCDError.badChecksum(line: lineNumber)
        }
        let addressLength: Int
        switch type {
        case "0", "1", "5": addressLength = 2
        case "2": addressLength = 3
        case "3", "4": addressLength = 4
        default: addressLength = 0
        }
        var address: UInt32 = 0
        for byte in bytes[1...(addressLength > 0 ? addressLength : 0)] {
            address = address << 8 | UInt32(byte)
        }
        let data = Array(bytes[(1 + addressLength)..<(bytes.count - 1)])
        return (String(type), address, data)
    }

    /// The sections as a backup snapshot (the ECU address must be supplied —
    /// an NCD does not carry it).
    public func backup(ecuAddress: Int, ecuName: String? = nil, vin: String? = nil) -> CodingBackup {
        CodingBackup(vin: vin, ecuAddress: ecuAddress, ecuName: ecuName, sections: sections)
    }
}
