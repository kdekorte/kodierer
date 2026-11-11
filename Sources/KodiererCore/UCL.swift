import Foundation

/// UCL (NRV2B / NRV2D / NRV2E) decompression — the algorithm family BMW uses
/// for compressed segments in PSdZData flash files (their XML manifests say
/// COMPRESSION-METHOD "nrv"/"ucl"; the community `unucl` tool decodes them).
///
/// Direct port of the reference decompressors in UCL 1.03 by Markus F.X.J.
/// Oberhumer (GPL-2): src/n2b_d.c, src/n2d_d.c, src/n2e_d.c, src/getbit.h —
/// including the three bit-stream layouts the library offers:
///   - u8:   bits MSB-first from each single byte
///   - le16: bits MSB-first from each little-endian 16-bit word
///   - le32: bits MSB-first from each little-endian 32-bit word
public enum UCL {
    public enum Algorithm: String, CaseIterable, Sendable {
        case nrv2b, nrv2d, nrv2e
    }

    /// How the flag bits are packed in the compressed stream.
    public enum BitStream: String, CaseIterable, Sendable {
        case u8, le16, le32
    }

    public enum UCLError: Error, CustomStringConvertible, Sendable {
        case inputOverrun
        case outputOverrun
        case lookbehindOverrun
        case inputNotConsumed(remaining: Int)

        public var description: String {
            switch self {
            case .inputOverrun: return "UCL: compressed stream ended early"
            case .outputOverrun: return "UCL: decompressed data exceeds the size limit"
            case .lookbehindOverrun: return "UCL: match reaches before the start of the output"
            case .inputNotConsumed(let remaining):
                return "UCL: \(remaining) input byte(s) left unconsumed"
            }
        }
    }

    /// What `decompressAuto` found.
    public struct Decompressed: Sendable {
        public let bytes: [UInt8]
        public let algorithm: Algorithm
        public let bitStream: BitStream
    }

    /// Decompresses `input`. Throws `UCLError` on malformed input; a stream
    /// that ends without consuming every input byte also throws — auto
    /// detection relies on that strictness.
    public static func decompress(_ input: [UInt8], algorithm: Algorithm, bitStream: BitStream,
                                  maxOutputBytes maxOutput: Int = 64 * 1024 * 1024) throws -> [UInt8] {
        switch algorithm {
        case .nrv2b: return try nrv2b(input, bitStream, maxOutput)
        case .nrv2d: return try nrv2d(input, bitStream, maxOutput)
        case .nrv2e: return try nrv2e(input, bitStream, maxOutput)
        }
    }

    /// Tries every algorithm / bit-stream combination, like the community
    /// `unucl` tool does, and returns the first clean decode. Nil if none fits.
    public static func decompressAuto(_ input: [UInt8],
                                      maxOutputBytes maxOutput: Int = 64 * 1024 * 1024) -> Decompressed? {
        guard !input.isEmpty else { return nil }
        for algorithm in Algorithm.allCases {
            for bitStream in BitStream.allCases {
                if let bytes = try? decompress(input, algorithm: algorithm, bitStream: bitStream,
                                               maxOutputBytes: maxOutput), !bytes.isEmpty {
                    return Decompressed(bytes: bytes, algorithm: algorithm, bitStream: bitStream)
                }
            }
        }
        return nil
    }

    // MARK: - Bit/byte reader (getbit.h)

    /// Reads flag bits MSB-first inside words of 1/2/4 little-endian bytes,
    /// and raw bytes between them — exactly what UCL's getbit_8 / getbit_le16
    /// / getbit_le32 macros do.
    private struct Reader {
        let input: [UInt8]
        let stream: BitStream
        var offset = 0
        private var buffer: UInt32 = 0
        private var bitsLeft = 0

        mutating func bit() throws -> UInt32 {
            if bitsLeft == 0 {
                let width: Int
                switch stream {
                case .u8: width = 1
                case .le16: width = 2
                case .le32: width = 4
                }
                guard offset + width <= input.count else { throw UCLError.inputOverrun }
                var word: UInt32 = 0
                for index in 0..<width {
                    word |= UInt32(input[offset + index]) << (8 * index)
                }
                buffer = word
                bitsLeft = width * 8
                offset += width
            }
            bitsLeft -= 1
            return (buffer >> bitsLeft) & 1
        }

        /// One raw byte (literal data / offset low byte).
        mutating func byte() throws -> UInt8 {
            guard offset < input.count else { throw UCLError.inputOverrun }
            let value = input[offset]
            offset += 1
            return value
        }

        func requireConsumed() throws {
            if offset != input.count {
                throw UCLError.inputNotConsumed(remaining: input.count - offset)
            }
        }
    }

    /// Copies a match `distance` bytes back, `length + 1` bytes long, byte by
    /// byte so overlapping matches work (as in the C reference).
    private static func copyMatch(_ output: inout [UInt8], distance: UInt32, length: UInt32,
                                  maxOutput: Int) throws {
        guard Int(distance) <= output.count else { throw UCLError.lookbehindOverrun }
        guard output.count + Int(length) + 1 <= maxOutput else { throw UCLError.outputOverrun }
        var position = output.count - Int(distance)
        for _ in 0...Int(length) {
            output.append(output[position])
            position += 1
        }
    }

    // MARK: - NRV2B (src/n2b_d.c)

    /// NRV2B: offset bits come in (extend, stop) pairs; length is 2 bits,
    /// or an extended unary-ish code when both are zero.
    private static func nrv2b(_ input: [UInt8], _ stream: BitStream, _ maxOutput: Int) throws -> [UInt8] {
        var reader = Reader(input: input, stream: stream)
        var output: [UInt8] = []
        output.reserveCapacity(Swift.min(input.count * 4, 1 << 20))
        var lastOffset: UInt32 = 1

        outer: while true {
            while try reader.bit() != 0 {                        // literal run
                guard output.count < maxOutput else { throw UCLError.outputOverrun }
                output.append(try reader.byte())
            }
            var offset: UInt32 = 1
            while true {                                         // offset accumulator
                offset = offset &* 2 &+ (try reader.bit())
                guard offset <= 0xFFFFFF + 3 else { throw UCLError.lookbehindOverrun }
                if try reader.bit() != 0 { break }
            }
            if offset == 2 {
                offset = lastOffset                              // reuse previous match
            } else {
                offset = (offset - 3) &* 256 &+ UInt32(try reader.byte())
                if offset == 0xFFFFFFFF { break outer }          // end-of-stream marker
                offset += 1
                lastOffset = offset
            }
            var length = try reader.bit()
            length = length &* 2 &+ (try reader.bit())
            if length == 0 {
                length = 1
                while true {
                    length = length &* 2 &+ (try reader.bit())
                    guard Int(length) < maxOutput else { throw UCLError.outputOverrun }
                    if try reader.bit() != 0 { break }
                }
                length += 2
            }
            length += (offset > 0xD00) ? 1 : 0
            try copyMatch(&output, distance: offset, length: length, maxOutput: maxOutput)
        }
        try reader.requireConsumed()
        return output
    }

    // MARK: - NRV2D (src/n2d_d.c)

    /// NRV2D: offset bits come in (extend, stop, extend) triples; the length's
    /// first bit hides in the offset bits for non-reused matches.
    private static func nrv2d(_ input: [UInt8], _ stream: BitStream, _ maxOutput: Int) throws -> [UInt8] {
        var reader = Reader(input: input, stream: stream)
        var output: [UInt8] = []
        output.reserveCapacity(Swift.min(input.count * 4, 1 << 20))
        var lastOffset: UInt32 = 1

        outer: while true {
            while try reader.bit() != 0 {
                guard output.count < maxOutput else { throw UCLError.outputOverrun }
                output.append(try reader.byte())
            }
            var offset: UInt32 = 1
            while true {
                offset = offset &* 2 &+ (try reader.bit())
                guard offset <= 0xFFFFFF + 3 else { throw UCLError.lookbehindOverrun }
                if try reader.bit() != 0 { break }
                offset = (offset - 1) &* 2 &+ (try reader.bit())
            }
            var length: UInt32
            if offset == 2 {
                offset = lastOffset
                length = try reader.bit()
            } else {
                offset = (offset - 3) &* 256 &+ UInt32(try reader.byte())
                if offset == 0xFFFFFFFF { break outer }
                length = (offset ^ 0xFFFFFFFF) & 1
                offset >>= 1
                offset += 1
                lastOffset = offset
            }
            length = length &* 2 &+ (try reader.bit())
            if length == 0 {
                length = 1
                while true {
                    length = length &* 2 &+ (try reader.bit())
                    guard Int(length) < maxOutput else { throw UCLError.outputOverrun }
                    if try reader.bit() != 0 { break }
                }
                length += 2
            }
            length += (offset > 0x500) ? 1 : 0
            try copyMatch(&output, distance: offset, length: length, maxOutput: maxOutput)
        }
        try reader.requireConsumed()
        return output
    }

    // MARK: - NRV2E (src/n2e_d.c)

    /// NRV2E: same offset coding as NRV2D, but a three-way length scheme.
    private static func nrv2e(_ input: [UInt8], _ stream: BitStream, _ maxOutput: Int) throws -> [UInt8] {
        var reader = Reader(input: input, stream: stream)
        var output: [UInt8] = []
        output.reserveCapacity(Swift.min(input.count * 4, 1 << 20))
        var lastOffset: UInt32 = 1

        outer: while true {
            while try reader.bit() != 0 {
                guard output.count < maxOutput else { throw UCLError.outputOverrun }
                output.append(try reader.byte())
            }
            var offset: UInt32 = 1
            while true {
                offset = offset &* 2 &+ (try reader.bit())
                guard offset <= 0xFFFFFF + 3 else { throw UCLError.lookbehindOverrun }
                if try reader.bit() != 0 { break }
                offset = (offset - 1) &* 2 &+ (try reader.bit())
            }
            var length: UInt32
            if offset == 2 {
                offset = lastOffset
                length = try reader.bit()
            } else {
                offset = (offset - 3) &* 256 &+ UInt32(try reader.byte())
                if offset == 0xFFFFFFFF { break outer }
                length = (offset ^ 0xFFFFFFFF) & 1
                offset >>= 1
                offset += 1
                lastOffset = offset
            }
            if length != 0 {
                length = 1 + (try reader.bit())
            } else if try reader.bit() != 0 {
                length = 3 + (try reader.bit())
            } else {
                length = 1
                while true {
                    length = length &* 2 &+ (try reader.bit())
                    guard Int(length) < maxOutput else { throw UCLError.outputOverrun }
                    if try reader.bit() != 0 { break }
                }
                length += 3
            }
            length += (offset > 0x500) ? 1 : 0
            try copyMatch(&output, distance: offset, length: length, maxOutput: maxOutput)
        }
        try reader.requireConsumed()
        return output
    }
}
