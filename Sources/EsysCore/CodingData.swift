import Foundation

/// One FDL coding section: a UDS DID and its current bytes.
///
/// FDL coding data lives in per-section DIDs: an NCD block's memory address is
/// `DID * 256 + offset`, and the section numbers shown in E-Sys / cheat sheets
/// (3000, 3001, 3062, ...) are those DID numbers in decimal.
public struct CodingSection: Codable, Equatable, Sendable {
    /// Section (= DID) number, decimal, e.g. 3062.
    public let did: Int
    public private(set) var bytes: [UInt8]

    public init(did: Int, bytes: [UInt8]) {
        self.did = did
        self.bytes = bytes
    }

    public mutating func setBytes(_ new: [UInt8]) { bytes = new }
}

/// One changed byte between two coding backups.
public struct ByteChange: Codable, Equatable, Sendable {
    public let offset: Int
    public let from: UInt8
    public let to: UInt8
}

/// Differences of one section between two backups.
public struct SectionDiff: Codable, Equatable, Sendable {
    public let did: Int
    public let changes: [ByteChange]
    public var isEmpty: Bool { changes.isEmpty }
}

/// A full snapshot of one ECU's coding data, used for backup, diffing, restore.
public struct CodingBackup: Codable, Equatable, Sendable {
    public let schema: Int
    public let created: Date
    public let vin: String?
    /// Diagnostic address of the ECU, e.g. 0x63 for HU_NBT.
    public let ecuAddress: Int
    public let ecuName: String?
    public var sections: [CodingSection]

    public init(vin: String?, ecuAddress: Int, ecuName: String?, sections: [CodingSection]) {
        self.schema = 1
        self.created = Date()
        self.vin = vin
        self.ecuAddress = ecuAddress
        self.ecuName = ecuName
        self.sections = sections.sorted { $0.did < $1.did }
    }

    public func section(_ did: Int) -> CodingSection? {
        sections.first { $0.did == did }
    }

    public func sectionBytes(_ did: Int) -> [UInt8]? {
        section(did)?.bytes
    }

    public mutating func replace(section: CodingSection) {
        if let index = sections.firstIndex(where: { $0.did == section.did }) {
            sections[index] = section
        } else {
            sections.append(section)
            sections.sort { $0.did < $1.did }
        }
    }

    /// Byte-level differences from `other` (missing sections count as changed in full).
    public func diff(to other: CodingBackup) -> [SectionDiff] {
        var diffs: [SectionDiff] = []
        let dids = Set(sections.map(\.did)).union(other.sections.map(\.did)).sorted()
        for did in dids {
            let mine = sectionBytes(did)
            let theirs = other.sectionBytes(did)
            guard mine != theirs else { continue }
            var changes: [ByteChange] = []
            let count = max(mine?.count ?? 0, theirs?.count ?? 0)
            for offset in 0..<count {
                let a: UInt8? = mine.flatMap { offset < $0.count ? $0[offset] : nil }
                let b: UInt8? = theirs.flatMap { offset < $0.count ? $0[offset] : nil }
                if a != b {
                    changes.append(ByteChange(offset: offset, from: a ?? 0, to: b ?? 0))
                }
            }
            diffs.append(SectionDiff(did: did, changes: changes))
        }
        return diffs
    }

    // MARK: Persistence

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    public static func load(from url: URL) throws -> CodingBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CodingBackup.self, from: try Data(contentsOf: url))
    }
}

/// A human-readable rendering of a diff.
public func describeDiffs(_ diffs: [SectionDiff]) -> String {
    guard !diffs.isEmpty else { return "identical" }
    var lines: [String] = []
    for diff in diffs {
        lines.append("section \(diff.did):")
        for change in diff.changes {
            lines.append(String(format: "  byte %3d: %02X -> %02X", change.offset, change.from, change.to))
        }
    }
    return lines.joined(separator: "\n")
}
