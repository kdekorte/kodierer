import XCTest
@testable import KodiererCore

/// Test encoder mirroring the reference bit writer (src/ucl_mchw.ch
/// bbPutBit / bbPutByte / bbFlushBits): a bit word reserves its bytes in the
/// output first; raw bytes are appended while the word is still filling;
/// flushing pads with zero bits.
private struct UCLWriter {
        let stream: UCL.BitStream
        private var bits: [Bool] = []
        private(set) var bytes: [UInt8] = []
        private var wordStart = -1

        init(stream: UCL.BitStream) { self.stream = stream }

        private var wordBits: Int {
            switch stream {
            case .u8: return 8
            case .le16: return 16
            case .le32: return 32
            }
        }

        mutating func bit(_ value: Bool) {
            if bits.isEmpty {
                wordStart = bytes.count
                bytes += [UInt8](repeating: 0, count: wordBits / 8)
            }
            bits.append(value)
            if bits.count == wordBits { writeWord() }
        }

        mutating func raw(_ byte: UInt8) { bytes.append(byte) }

        private mutating func writeWord() {
            var word: UInt32 = 0
            for bit in bits { word = word << 1 | (bit ? 1 : 0) }
            for index in 0..<(wordBits / 8) {
                bytes[wordStart + index] = UInt8((word >> (8 * index)) & 0xFF)
            }
            bits = []
            wordStart = -1
        }

        /// bbFlushBits(c, 0): pad the pending word with zero bits, if any.
        mutating func finish() {
            guard !bits.isEmpty else { return }
            while bits.count < wordBits { bits.append(false) }
            writeWord()
        }
    }

// code_prefix_ss11: pairs (bit, 0) … then (bit, 1). Port of n2_99.ch.
private extension UCLWriter {
        mutating func prefix11(_ value: UInt32) {
            var i = value
            if i >= 2 {
                i += 2
                var t: UInt32 = 4
                repeat { t <<= 1 } while i >= t
                t >>= 1
                repeat {
                    t >>= 1
                    bit(i & t != 0)
                    bit(false)
                } while t > 2
            }
            bit(i & 1 != 0)
            bit(true)
        }

        // code_prefix_ss12: triples (bit, 0, bit) … then (bit, 1).
        mutating func prefix12(_ value: UInt32) {
            var i = value
            if i >= 2 {
                var t: UInt32 = 2
                repeat { i -= t; t <<= 2 } while i >= t
                repeat {
                    t >>= 1
                    bit(i & t != 0)
                    bit(false)
                    t >>= 1
                    bit(i & t != 0)
                } while t > 2
            }
            bit(i & 1 != 0)
            bit(true)
        }

        // code_run: literal flag + byte per literal.
        mutating func literals(_ data: [UInt8]) {
            for byte in data {
                bit(true)
                raw(byte)
            }
        }

        // NRV2B code_match for m_len bytes at m_off (explicit or reused).
        mutating func match2b(length: UInt32, offset: UInt32, reuseLast: Bool) {
            bit(false)
            if reuseLast {
                bit(false)
                bit(true)
            } else {
                prefix11(1 + ((offset - 1) >> 8))
                raw(UInt8((offset - 1) & 0xFF))
            }
            let len = length - 1 - (offset > 0xD00 ? 1 : 0)
            if len >= 4 {
                bit(false)
                bit(false)
                prefix11(len - 4)
            } else {
                bit(len > 1)
                bit(len & 1 != 0)
            }
        }

        // EOF marker: match flag + prefix(0x1000000) + 0xFF, then flush.
        mutating func eof2b() {
            bit(false)
            prefix11(0x1000000)
            raw(0xFF)
            finish()
        }
    }

// NRV2D / NRV2E code_match + the shared EOF marker.
private extension UCLWriter {
        // NRV2D code_match.
        mutating func match2d(length: UInt32, offset: UInt32, reuseLast: Bool) {
            bit(false)
            let len = length - 1 - (offset > 0x500 ? 1 : 0)
            let low = len >= 4 ? UInt32(0) : len
            if reuseLast {
                bit(false)
                bit(true)
                bit(low > 1)
                bit(low & 1 != 0)
            } else {
                prefix12(1 + ((offset - 1) >> 7))
                raw(UInt8((((offset - 1) & 0x7F) << 1) | (low > 1 ? 0 : 1)))
                bit(low & 1 != 0)
            }
            if len >= 4 { prefix11(len - 4) }
        }

        // NRV2E code_match.
        mutating func match2e(length: UInt32, offset: UInt32, reuseLast: Bool) {
            bit(false)
            let len = length - 1 - (offset > 0x500 ? 1 : 0)
            let low = len <= 2
            if reuseLast {
                bit(false)
                bit(true)
                bit(low)
            } else {
                prefix12(1 + ((offset - 1) >> 7))
                raw(UInt8((((offset - 1) & 0x7F) << 1) | (low ? 0 : 1)))
            }
            if low {
                bit(len == 2)
            } else if len <= 4 {
                bit(true)
                bit(len == 4)
            } else {
                bit(false)
                prefix11(len - 5)
            }
        }

        mutating func eof2d2e() {
            bit(false)
            prefix12(0x1000000)
            raw(0xFF)
            finish()
        }
    }

/// Round-trip tests for the UCL port. The encoder above is ported
/// line-for-line from UCL 1.03's own reference compressor (src/n2_99.ch
/// code_run / code_match / code_prefix_ss11 / ss12), so a passing test means
/// our decoder agrees with the reference encoder's bit layout.
final class UCLTests: XCTestCase {
    /// Appends what a match of `length` bytes `offset` back would produce.
    private func simulateMatch(_ output: inout [UInt8], offset: Int, length: Int) {
        var position = output.count - offset
        for _ in 0..<length {
            output.append(output[position])
            position += 1
        }
    }

    func testLiteralRoundTripAllCombinations() throws {
        let data = (0..<100).map { UInt8(($0 &* 37 &+ 11) & 0xFF) }
        for algorithm in UCL.Algorithm.allCases {
            for stream in UCL.BitStream.allCases {
                var writer = UCLWriter(stream: stream)
                writer.literals(data)
                switch algorithm {
                case .nrv2b: writer.eof2b()
                case .nrv2d, .nrv2e: writer.eof2d2e()
                }
                let output = try UCL.decompress(writer.bytes, algorithm: algorithm, bitStream: stream)
                XCTAssertEqual(output, data, "\(algorithm) / \(stream)")
            }
        }
    }

    func testNRV2BMatchesRoundTrip() throws {
        let data: [UInt8] = Array("ABCDEFGH".utf8)
        var writer = UCLWriter(stream: .u8)
        writer.literals(data)
        writer.match2b(length: 4, offset: 3, reuseLast: false)   // self-overlapping copy
        writer.match2b(length: 2, offset: 3, reuseLast: true)    // reuse previous offset
        writer.eof2b()

        var expected = data
        simulateMatch(&expected, offset: 3, length: 4)
        simulateMatch(&expected, offset: 3, length: 2)
        XCTAssertEqual(try UCL.decompress(writer.bytes, algorithm: .nrv2b, bitStream: .u8), expected)
    }

    func testNRV2DAndNRV2EMatchesRoundTrip() throws {
        let data: [UInt8] = Array("0123456789".utf8)
        for (algorithm, stream) in [(UCL.Algorithm.nrv2d, UCL.BitStream.le16),
                                    (UCL.Algorithm.nrv2e, UCL.BitStream.le32)] {
            var writer = UCLWriter(stream: stream)
            writer.literals(data)
            writer.match(length: 7, offset: 4, reuseLast: false, algorithm: algorithm)   // extended length
            writer.match(length: 2, offset: 4, reuseLast: true, algorithm: algorithm)
            writer.eof2d2e()
            var expected = data
            simulateMatch(&expected, offset: 4, length: 7)
            simulateMatch(&expected, offset: 4, length: 2)
            XCTAssertEqual(try UCL.decompress(writer.bytes, algorithm: algorithm, bitStream: stream),
                           expected, "\(algorithm)")
        }
    }

    func testTruncatedStreamThrows() throws {
        var writer = UCLWriter(stream: .u8)
        writer.literals((0..<40).map { UInt8($0) })
        writer.eof2b()
        var truncated = writer.bytes
        truncated.removeLast(3)
        XCTAssertThrowsError(try UCL.decompress(truncated, algorithm: .nrv2b, bitStream: .u8))
        XCTAssertThrowsError(try UCL.decompress([], algorithm: .nrv2b, bitStream: .u8))
    }

    func testAutoDetectFindsStream() throws {
        let data = (0..<60).map { UInt8(($0 &* 53 &+ 7) & 0xFF) }
        var writer = UCLWriter(stream: .le16)
        writer.literals(data)
        writer.eof2d2e()
        let found = try XCTUnwrap(UCL.decompressAuto(writer.bytes))
        XCTAssertEqual(found.algorithm, .nrv2d)
        XCTAssertEqual(found.bitStream, .le16)
        XCTAssertEqual(found.bytes, data)
    }

    func testGarbageIsNotDecodable() {
        // All-ones bits decode as an endless literal run, which overruns.
        XCTAssertNil(UCL.decompressAuto([UInt8](repeating: 0xFF, count: 64)))
        XCTAssertNil(UCL.decompressAuto([]))
    }
}

private extension UCLWriter {
    /// Algorithm dispatch used by the round-trip tests.
    mutating func match(length: UInt32, offset: UInt32, reuseLast: Bool, algorithm: UCL.Algorithm) {
        switch algorithm {
        case .nrv2b: match2b(length: length, offset: offset, reuseLast: reuseLast)
        case .nrv2d: match2d(length: length, offset: offset, reuseLast: reuseLast)
        case .nrv2e: match2e(length: length, offset: offset, reuseLast: reuseLast)
        }
    }
}

