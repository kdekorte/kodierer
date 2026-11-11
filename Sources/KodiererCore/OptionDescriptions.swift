import Foundation

/// Community option descriptions — plain-language text for coding functions,
/// keyed by the function's BMW/community name (e.g. `KOMFORTSCHLIESSUNG_FB`).
///
/// Sources like the F10/F25/F30 cheat-sheet PDFs publish
/// `Module · Section · Function · New Value · Default · Description` tables:
/// real names and what they do, but **no byte offsets**. This format captures
/// what they can give: a name → description (+ optional category) overlay that
/// joins the option tree once a CAFD + names TSV supply the offsets.
///
/// TSV format (tab-separated; only NAME and DESCRIPTION are required):
///
///     NAME	DESCRIPTION	CATEGORY	MODULE	SECTION
///     KOMFORTSCHLIESSUNG_FB	Close mirrors + windows + moon roof via key fob	Comfort	CAS	3003
public struct OptionDescriptions: Sendable {
    public struct Entry: Equatable, Sendable {
        public let name: String
        public let description: String
        public let category: String?
        public let module: String?
        public let section: String?
    }

    public let entries: [Entry]
    private let byName: [String: Entry]

    public init(entries: [Entry]) {
        self.entries = entries
        var map: [String: Entry] = [:]
        for entry in entries where map[entry.name.uppercased()] == nil {
            map[entry.name.uppercased()] = entry
        }
        self.byName = map
    }

    public static func parse(text: String) -> OptionDescriptions {
        var entries: [Entry] = []
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 2 else { continue }
            let name = fields[0].trimmingCharacters(in: .whitespaces)
            let description = fields[1].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !description.isEmpty,
                  name.uppercased() != "NAME" else { continue }   // header row
            let category = fields.count > 2 ? nilIfEmpty(fields[2]) : nil
            let module = fields.count > 3 ? nilIfEmpty(fields[3]) : nil
            let section = fields.count > 4 ? nilIfEmpty(fields[4]) : nil
            entries.append(Entry(name: name, description: description,
                                 category: category, module: module, section: section))
        }
        return OptionDescriptions(entries: entries)
    }

    public static func parse(url: URL) throws -> OptionDescriptions {
        try parse(text: String(contentsOf: url, encoding: .utf8))
    }

    private static func nilIfEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The description entry for a function name (case-insensitive), if any.
    public func entry(named name: String) -> Entry? {
        byName[name.uppercased()]
    }

    /// Combines two lists; entries of `self` win on name clashes.
    public func merged(with other: OptionDescriptions) -> OptionDescriptions {
        var seen = Set(entries.map { $0.name.uppercased() })
        var combined = entries
        for entry in other.entries where !seen.contains(entry.name.uppercased()) {
            seen.insert(entry.name.uppercased())
            combined.append(entry)
        }
        return OptionDescriptions(entries: combined)
    }
}
