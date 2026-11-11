import Foundation
import Compression

/// Minimal gzip (RFC 1952) reader on top of Apple's raw-DEFLATE `Compression`
/// stream — enough to read the `.xml.gz` files the community tools produce
/// (e.g. OpenCAFDMap's decrypted CAFD cache) without linking zlib.
public enum Gzip {
    public enum GzipError: Error, CustomStringConvertible, Sendable {
        case malformed(String)

        public var description: String { "gzip: \(_caseDescription)" }
    }

    /// Returns `data` unchanged unless it starts with the gzip magic, in which
    /// case it is decompressed.
    public static func unwrapIfGzip(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count >= 2, bytes[0] == 0x1F, bytes[1] == 0x8B else { return data }
        return Data(try gunzip(bytes))
    }

    /// Decompresses a full gzip file: header, raw DEFLATE body, 8-byte trailer.
    public static func gunzip(_ bytes: [UInt8]) throws -> [UInt8] {
        guard bytes.count > 18 else { throw GzipError.malformed("file too short") }
        guard bytes[2] == 8 else { throw GzipError.malformed("unknown method \(bytes[2])") }
        let flags = bytes[3]
        var offset = 10
        if flags & 0x04 != 0 {                                    // FEXTRA
            guard offset + 2 <= bytes.count else { throw GzipError.malformed("bad FEXTRA") }
            let xlen = Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
            offset += 2 + xlen
        }
        for mask in [UInt8(0x08), UInt8(0x10)] {                  // FNAME, FCOMMENT
            if flags & mask != 0 {
                while offset < bytes.count, bytes[offset] != 0 { offset += 1 }
                offset += 1
            }
        }
        if flags & 0x02 != 0 { offset += 2 }                      // FHCRC
        guard offset < bytes.count - 8 else { throw GzipError.malformed("truncated body") }
        let body = Array(bytes[offset..<(bytes.count - 8)])
        return try inflateRawDeflate(body)
    }

    /// Raw DEFLATE (RFC 1951) via Apple's COMPRESSION_ZLIB decoder, which —
    /// despite the name — expects the stream without a zlib header.
    static func inflateRawDeflate(_ input: [UInt8]) throws -> [UInt8] {
        var output = [UInt8]()
        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }
        guard compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
                == COMPRESSION_STATUS_OK else {
            throw GzipError.malformed("cannot start inflate")
        }
        defer { compression_stream_destroy(stream) }
        try input.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else {
                throw GzipError.malformed("empty deflate stream")
            }
            stream.pointee.src_ptr = base.assumingMemoryBound(to: UInt8.self)
            stream.pointee.src_size = raw.count
            var finished = false
            while !finished {
                let capacity = 64 * 1024
                let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
                defer { destination.deallocate() }
                stream.pointee.dst_ptr = destination
                stream.pointee.dst_size = capacity
                let status = compression_stream_process(stream, 0)
                let produced = capacity - stream.pointee.dst_size
                output.append(contentsOf: UnsafeBufferPointer(start: destination, count: produced))
                switch status {
                case COMPRESSION_STATUS_END: finished = true
                case COMPRESSION_STATUS_OK: break
                default: throw GzipError.malformed("deflate stream error")
                }
            }
        }
        return output
    }
}

extension Gzip.GzipError {
    var _caseDescription: String {
        switch self {
        case .malformed(let detail): return detail
        }
    }
}
