import Foundation

/// The value an FDL operation writes: raw bytes or a symbolic choice whose
/// numeric encoding comes from the CAFD (we resolve the common German
/// activ/nicht_aktiv words; everything else must be numeric).
public enum FDLValue: Equatable, Sendable {
    case bytes([UInt8])
    case symbolic(String)

    public static func parse(_ text: String) -> FDLValue {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("b"), trimmed.dropLast().allSatisfy({ $0 == "0" || $0 == "1" }) {
            return .bytes([UInt8(trimmed.dropLast(), radix: 2) ?? 0])
        }
        if trimmed.hasPrefix("0x") || trimmed.hasPrefix("0X") {
            let hex = String(trimmed.dropFirst(2))
            var bytes: [UInt8] = []
            var index = hex.startIndex
            while index < hex.endIndex {
                let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
                if let value = UInt8(hex[index..<next], radix: 16) { bytes.append(value) }
                index = next
            }
            return .bytes(bytes)
        }
        let pureDigits = !trimmed.isEmpty && trimmed.allSatisfy(\.isNumber)
        if pureDigits, let value = UInt8(trimmed, radix: 10) { return .bytes([value]) }
        // Cheat sheets write bare hex like "0B" for values that are not decimal.
        if !pureDigits, trimmed.count <= 2, let value = UInt8(trimmed, radix: 16) {
            return .bytes([value])
        }
        return .symbolic(trimmed)
    }

    /// Resolve to bytes for a field `byteCount` wide with the given mask.
    public func resolved(byteCount: Int, mask: UInt8) throws -> [UInt8] {
        switch self {
        case .bytes(let bytes):
            return bytes
        case .symbolic(let symbol):
            guard byteCount == 1, let numeric = FDLSymbolTable.numeric(symbol, mask: mask) else {
                throw FDLEditError.unresolvedSymbol(symbol)
            }
            return [numeric]
        }
    }
}

/// Common symbolic values used across BMW CAFDs.
public enum FDLSymbolTable {
    public static func numeric(_ symbol: String, mask: UInt8) -> UInt8? {
        let key = symbol.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
        switch key {
        case "aktiv", "active", "ja", "yes", "ein", "on", "true", "enabled":
            return mask == 0xFF ? 1 : mask
        case "nicht_aktiv", "inactive", "nein", "no", "aus", "off", "false", "disabled":
            return 0
        default:
            return nil
        }
    }
}

public enum FDLEditError: Error, CustomStringConvertible, Sendable {
    case sectionMissing(Int)
    case offsetOutOfRange(section: Int, offset: Int, length: Int)
    case unresolvedSymbol(String)
    case maskMismatch

    public var description: String {
        switch self {
        case .sectionMissing(let did):
            return "coding section \(did) not present in this ECU"
        case .offsetOutOfRange(let section, let offset, let length):
            return "byte offset \(offset) outside section \(section) (\(length) bytes)"
        case .unresolvedSymbol(let symbol):
            return "cannot resolve symbolic value \"\(symbol)\" without CAFD data"
        case .maskMismatch:
            return "mask length does not match the byte range"
        }
    }
}

/// A single byte-level edit, as used by cheat sheets:
/// `function start end mask` inside a `group`.
public struct FDLOperation: Equatable, Sendable {
    /// Section (= DID) number, decimal, e.g. 3062.
    public let group: Int
    /// First byte offset inside the section (0-based).
    public let start: Int
    /// Last byte offset inside the section (inclusive).
    public let end: Int
    /// Bitmask applied to every byte of the range (from e.g. "00110000b").
    public let mask: UInt8
    public let value: FDLValue

    public init(group: Int, start: Int, end: Int, mask: UInt8, value: FDLValue) {
        self.group = group
        self.start = start
        self.end = end
        self.mask = mask
        self.value = value
    }

    /// The bytes this operation would write into a section that reads `current`.
    public func applied(to current: [UInt8]) throws -> [UInt8] {
        var bytes = current
        let length = end - start + 1
        guard length > 0 else { throw FDLEditError.offsetOutOfRange(section: group, offset: start, length: current.count) }
        guard start >= 0, end < current.count else {
            throw FDLEditError.offsetOutOfRange(section: group, offset: max(start, end), length: current.count)
        }
        let valueBytes = try value.resolved(byteCount: length, mask: mask)
        guard valueBytes.count == 1 || valueBytes.count == length else { throw FDLEditError.maskMismatch }
        for index in 0..<length {
            let valueByte = valueBytes.count == 1 ? valueBytes[0] : valueBytes[index]
            bytes[start + index] = (bytes[start + index] & ~mask) | (valueByte & mask)
        }
        return bytes
    }
}

/// One named coding option (a `<code>` in a cheat sheet): a set of byte edits.
public struct FDLCheatCode: Equatable, Sendable {
    public let cafdID: String?
    public let cafdName: String?
    public let description: String
    public let operations: [FDLOperation]

    public init(cafdID: String?, cafdName: String?, description: String, operations: [FDLOperation]) {
        self.cafdID = cafdID
        self.cafdName = cafdName
        self.description = description
        self.operations = operations
    }

    /// Applies every operation to a coding backup, returning the modified copy.
    public func applied(to backup: CodingBackup) throws -> CodingBackup {
        var result = backup
        for operation in operations {
            guard var section = result.section(operation.group) else {
                throw FDLEditError.sectionMissing(operation.group)
            }
            section.setBytes(try operation.applied(to: section.bytes))
            result.replace(section: section)
        }
        return result
    }
}
