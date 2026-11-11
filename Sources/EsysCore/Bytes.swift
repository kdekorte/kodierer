import Foundation

/// Small byte / hex helpers shared across the protocol layer.
public enum Bytes {
    public static func u16be(_ value: UInt16) -> [UInt8] {
        [UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
    }

    public static func u32be(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF),
         UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
    }

    public static func readU16BE(_ bytes: [UInt8], at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 1 < bytes.count else { return nil }
        return UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
    }

    public static func readU32BE(_ bytes: [UInt8], at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 3 < bytes.count else { return nil }
        return UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16
            | UInt32(bytes[offset + 2]) << 8 | UInt32(bytes[offset + 3])
    }

    public static func hex(_ bytes: [UInt8], max: Int = .max) -> String {
        bytes.prefix(max).map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    public static func ascii(_ bytes: [UInt8]) -> String {
        String(bytes: bytes.filter { $0 >= 0x20 && $0 < 0x7F }, encoding: .ascii) ?? ""
    }

    /// Hex without separators, e.g. "00FF0A" — for storing raw blobs in JSON.
    public static func hexCompact(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined()
    }

    /// Parses compact or space-separated hex back to bytes. Nil when malformed.
    public static func fromHex(_ text: String) -> [UInt8]? {
        let clean = text.filter { !$0.isWhitespace }
        guard !clean.isEmpty, clean.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        var index = clean.startIndex
        while index < clean.endIndex {
            let next = clean.index(index, offsetBy: 2, limitedBy: clean.endIndex) ?? clean.endIndex
            guard let value = UInt8(clean[index..<next], radix: 16) else { return nil }
            bytes.append(value)
            index = next
        }
        return bytes
    }
}
