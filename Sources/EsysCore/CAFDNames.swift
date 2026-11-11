import Foundation

/// Community parameter names for CAFDs — the OpenCAFDMap `names/*.tsv` format
/// (CC0-licensed data): one row per group / function / value name, keyed by
/// CAFD id + datagroup address + start + end + mask (+ value hex).
///
///     cafd_id  address  start  end  mask  value_hex  name              comment
///     ANY      3000     96     96   255              CARPLAY_FULLSCREEN
///     ANY      3000     96     96   255   01         Fullscreen
///
/// Rows with an empty start/end name the datagroup, rows with an empty
/// value_hex name the function. An id of `ANY` (or empty) matches every CAFD —
/// a function's (address, start, end, mask) is stable across versions.
public struct CAFDNames: Sendable {
    public struct Entry: Equatable, Sendable {
        public let cafdID: String?
        public let address: Int
        public let start: Int?
        public let end: Int?
        public let mask: UInt8?
        public let valueHex: String?
        public let name: String
        public let comment: String?
    }

    public let entries: [Entry]

    public init(entries: [Entry]) {
        self.entries = entries
    }

    public static func parse(text: String) -> CAFDNames {
        var entries: [Entry] = []
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 7 else { continue }
            let idText = fields[0].trimmingCharacters(in: .whitespaces).uppercased()
            guard idText != "CAFD_ID", idText != "CAFD" else { continue }   // header row
            let id = (idText == "ANY" || idText.isEmpty) ? nil : idText
            let address = CAFD.parseAddress(fields[1]) ?? 0
            let start = Int(fields[2].trimmingCharacters(in: .whitespaces))
            let end = Int(fields[3].trimmingCharacters(in: .whitespaces))
            let maskText = fields[4].trimmingCharacters(in: .whitespaces)
            let mask = maskText.isEmpty ? nil : (UInt8(maskText) ?? CAFD.parseMask(maskText))
            let valueHex = fields[5].trimmingCharacters(in: .whitespaces).uppercased()
            let name = fields[6].trimmingCharacters(in: .whitespaces)
            let comment = fields.count > 7 ? fields[7].trimmingCharacters(in: .whitespaces) : nil
            guard !name.isEmpty else { continue }
            entries.append(Entry(cafdID: id, address: address, start: start, end: end, mask: mask,
                                 valueHex: valueHex.isEmpty ? nil : valueHex,
                                 name: name, comment: comment))
        }
        return CAFDNames(entries: entries)
    }

    public static func parse(url: URL) throws -> CAFDNames {
        try parse(text: String(contentsOf: url, encoding: .utf8))
    }
}

// MARK: - Name lookup

extension CAFDNames {
    private func matches(_ entry: Entry, cafdID: String?, address: Int,
                         start: Int?, end: Int?, mask: UInt8?, valueHex: String? = nil) -> Bool {
        if let entryID = entry.cafdID, let cafdID, entryID != cafdID.uppercased() { return false }
        guard entry.address == address else { return false }
        // Group rows (no start/end) only answer group lookups; function rows
        // only answer function lookups.
        guard (entry.start == nil) == (start == nil) else { return false }
        if let entryStart = entry.start, let start, entryStart != start { return false }
        if let entryEnd = entry.end, let end, entryEnd != end { return false }
        if let entryMask = entry.mask, mask == nil || entryMask != mask { return false }
        if entry.valueHex != nil || valueHex != nil {
            guard let entryValue = entry.valueHex, let valueHex,
                  CAFD.parseHexBytes(entryValue) == CAFD.parseHexBytes(valueHex) else { return false }
        }
        return true
    }

    /// Name for a datagroup, if the list has one.
    public func groupName(datagroup: CAFD.Datagroup, cafdID: String? = nil) -> String? {
        entries.first {
            matches($0, cafdID: cafdID, address: datagroup.address, start: nil, end: nil, mask: nil)
        }?.name
    }

    /// Name for a function (community name or nil).
    public func functionName(datagroup: CAFD.Datagroup, function: CAFD.Function, cafdID: String? = nil) -> String? {
        entries.first {
            matches($0, cafdID: cafdID, address: datagroup.address,
                    start: function.start, end: function.end, mask: function.mask)
        }?.name
    }

    /// Name for one value of a function (community name or nil).
    public func valueName(datagroup: CAFD.Datagroup, function: CAFD.Function,
                          value: CAFD.Value, cafdID: String? = nil) -> String? {
        entries.first {
            matches($0, cafdID: cafdID, address: datagroup.address,
                    start: function.start, end: function.end, mask: function.mask, valueHex: value.hex)
        }?.name
    }
}

// MARK: - Joining CAFDs with backups

extension CAFD {
    /// The declared value a backup currently has for this function, if the
    /// masked bytes match one.
    public func currentValue(of function: Function, in datagroup: Datagroup,
                             backup: CodingBackup) -> Value? {
        guard let section = backup.section(datagroup.address),
              let hex = CAFD.maskedHex(sectionBytes: section.bytes, function: function) else { return nil }
        return function.values.first {
            guard let canonical = CAFD.parseHexBytes($0.hex) else { return false }
            return Bytes.hexCompact(canonical) == hex
        }
    }

    /// The write operation that sets a function to one of its declared values.
    /// This is the CAFD-backed replacement for a cheat-sheet entry.
    public func operation(setting value: Value, of function: Function,
                          in datagroup: Datagroup) -> FDLOperation? {
        guard let bytes = value.bytes, !bytes.isEmpty else { return nil }
        return FDLOperation(group: datagroup.address, start: function.start, end: function.end,
                            mask: function.mask ?? 0xFF, value: .bytes(bytes))
    }
}

