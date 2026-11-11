import Foundation

/// A PSdZData SWE file name: `cafd_00000F07.caf.013_001_009` —
/// `<kind>_<id 8 hex>.<ext>.<main>_<sub>_<patch>`.
///
/// Source: LeonB1ham/svt-psdzdata-export `engine.py` (SWE_NAME_RE); the same
/// layout fake-car's `SGBMID.toFileName` produces.
public struct SWEFileName: Equatable, Sendable {
    /// Process class as folder name: "cafd", "swfl", "btld", "fafp", ...
    public let kind: String
    /// SGBM id, e.g. 0x00000F07.
    public let id: UInt32
    /// "caf", "bin", "xml", "fap", ...
    public let ext: String
    public let main: Int
    public let sub: Int
    public let patch: Int

    public init(kind: String, id: UInt32, ext: String, main: Int, sub: Int, patch: Int) {
        self.kind = kind
        self.id = id
        self.ext = ext
        self.main = main
        self.sub = sub
        self.patch = patch
    }

    public var version: String { String(format: "%03d_%03d_%03d", main, sub, patch) }

    /// The file name as it appears on disk.
    public var fileName: String {
        String(format: "%@_%08X.%@.%03d_%03d_%03d", kind, id, ext, main, sub, patch)
    }

    /// SVK-style name: "CAFD_00000F07_013_001_009".
    public var longName: String {
        String(format: "%@_%08X_%03d_%03d_%03d", kind.uppercased(), id, main, sub, patch)
    }

    /// Parses names like "cafd_00004146.caf.003_037_004" (case-insensitive id).
    public static func parse(_ fileName: String) -> SWEFileName? {
        let parts = fileName.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3 else { return nil }
        let versionParts = parts[2].split(separator: "_").map(String.init)
        guard versionParts.count == 3,
              let main = Int(versionParts[0]), let sub = Int(versionParts[1]),
              let patch = Int(versionParts[2]) else { return nil }
        let head = parts[0].split(separator: "_").map(String.init)
        guard head.count == 2, head[1].count == 8, let id = UInt32(head[1], radix: 16) else { return nil }
        return SWEFileName(kind: head[0].lowercased(), id: id, ext: parts[1].lowercased(),
                           main: main, sub: sub, patch: patch)
    }
}

/// A PSdZData folder on disk (the `psdzdata` folder itself, its parent, or a
/// `swe` folder): locates SWE files under `swe/<kind>/`.
public struct PSdZDataStore: Sendable {
    public let root: URL

    public init(path: String) {
        root = URL(fileURLWithPath: path)
    }

    /// Kinds that carry data, per svt-psdzdata-export's SWE_KIND_DIRS.
    public static let kinds = ["blup", "btld", "cafd", "fafp", "flsl", "flup",
                               "gwtb", "ibad", "swfk", "swfl", "tlrt"]

    /// The `swe` folder, if this root is (or contains) a PSdZData tree.
    public var sweRoot: URL? {
        if root.lastPathComponent.lowercased() == "swe" { return root }
        let candidates = [root.appendingPathComponent("swe"),
                          root.appendingPathComponent("psdzdata").appendingPathComponent("swe")]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// SWE files of one kind, optionally restricted to an id, newest last.
    public func files(kind: String = "cafd", id: UInt32? = nil) -> [(name: SWEFileName, url: URL)] {
        guard let sweRoot else { return [] }
        let folder = sweRoot.appendingPathComponent(kind)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return [] }
        return names.compactMap { rawName in
            guard let parsed = SWEFileName.parse(rawName) else { return nil }
            guard id == nil || parsed.id == id else { return nil }
            return (parsed, folder.appendingPathComponent(rawName))
        }.sorted {
            ($0.name.main, $0.name.sub, $0.name.patch) < ($1.name.main, $1.name.sub, $1.name.patch)
        }
    }

    /// The CAFD file for an SVK entry, or the newest version of that id.
    public func cafdFile(id: UInt32, version: (Int, Int, Int)? = nil) -> (name: SWEFileName, url: URL)? {
        let all = files(kind: "cafd", id: id)
        if let version {
            return all.first {
                $0.name.main == version.0 && $0.name.sub == version.1 && $0.name.patch == version.2
            }
        }
        return all.last
    }
}

/// What a `.caf` / CAFD-XML file actually contains, so tooling can explain
/// why a file will or will not parse.
public struct CAFDProbe: Sendable {
    public enum Kind: String, Sendable {
        case cafdXML = "CAFD XML (plaintext)"
        case gzipCAFDXML = "CAFD XML (gzip-wrapped)"
        case uclCAFDXML = "CAFD XML (UCL-compressed)"
        case notCAFD = "XML, but not CAFD data"
        case encrypted = "encrypted or unknown format"
    }

    public let kind: Kind
    public let cafd: CAFD?
    /// Extra diagnostics: UCL algorithm found, first bytes, why XML failed...
    public let detail: String

    /// Identifies the content: CAFD XML directly, gzip-wrapped, UCL-compressed,
    /// or — as with current PSdZData `.caf` files — encrypted in a way only
    /// BMW's own PsdZ library (inside E-Sys) can undo.
    public static func probe(data: Data, series: String? = nil) -> CAFDProbe {
        let bytes = [UInt8](data)
        guard !bytes.isEmpty else {
            return CAFDProbe(kind: .encrypted, cafd: nil, detail: "empty file")
        }
        if bytes[0] == 0x1F && bytes[1] == 0x8B {
            if let inner = try? Gzip.gunzip(bytes) {
                switch classify(inner, series: series) {
                case .cafd(let cafd):
                    return CAFDProbe(kind: .gzipCAFDXML, cafd: cafd, detail: "gzip container")
                case .xmlNotCAFD:
                    return CAFDProbe(kind: .notCAFD, cafd: nil,
                                     detail: "gzip container, but the contents are not CAFD XML")
                case .notXML:
                    return CAFDProbe(kind: .notCAFD, cafd: nil,
                                     detail: "gzip container with non-XML contents")
                }
            }
            return CAFDProbe(kind: .encrypted, cafd: nil, detail: "gzip header, but the deflate stream is broken")
        }
        if case .cafd(let cafd) = classify(bytes, series: series) {
            return CAFDProbe(kind: .cafdXML, cafd: cafd, detail: "plaintext")
        }
        if case .xmlNotCAFD = classify(bytes, series: series) {
            return CAFDProbe(kind: .notCAFD, cafd: nil, detail: "parses as XML but has no CAFD <data> element")
        }
        if let decompressed = UCL.decompressAuto(bytes),
           case .cafd(let cafd) = classify(decompressed.bytes, series: series) {
            return CAFDProbe(kind: .uclCAFDXML, cafd: cafd,
                             detail: "\(decompressed.algorithm.rawValue) / \(decompressed.bitStream.rawValue)")
        }
        return CAFDProbe(kind: .encrypted, cafd: nil, detail: """
            not XML, not gzip, not UCL — most likely a PSdZ-encrypted .caf. \
            Decryption lives in BMW's own PsdZ library inside E-Sys; see Docs/PROTOCOL.md. \
            First bytes: \(Bytes.hex(Array(bytes.prefix(8))))
            """)
    }

    private enum Classification: Sendable {
        case cafd(CAFD)
        case xmlNotCAFD
        case notXML
    }

    private static func classify(_ bytes: [UInt8], series: String?) -> Classification {
        guard let first = bytes.first(where: { $0 != 0x20 && $0 != 0x09 && $0 != 0x0A && $0 != 0x0D }),
              first == UInt8(ascii: "<") else { return .notXML }
        if let cafd = try? CAFD.parse(data: Data(bytes), series: series) { return .cafd(cafd) }
        return .xmlNotCAFD
    }
}

