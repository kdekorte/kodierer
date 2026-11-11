import Foundation

/// A parsed CAFD — BMW's coding data description for one ECU.
///
/// PSdZData ships CAFDs as encrypted `.caf` files; BMW's own PsdZ library
/// (inside E-Sys) decrypts them, and community tooling passes the decrypted
/// form around as XML with namespace `http://bmw.com/2005/psdz.data.caf`
/// (see Docs/PROTOCOL.md, "CAFD / PSdZData"). This parser reads that XML,
/// plain or gzip-wrapped (the OpenCAFDMap decrypt cache is `.xml.gz`).
///
/// Layout, per OpenCAFDMap's `ocm/build_defdb.py` (`parse_cafd`):
///
///     data → datagroup (address, datagroupClass, units)
///          → function (storageInfo: start, end, size, mask)
///          → condParam (bool rule + values/unitVal hex bytes)
///
/// Modern PSdZData trims every human-readable name to "." — names come back
/// through community lists keyed by cafd + address + start + end + mask
/// (see CAFDNames.swift).
public struct CAFD: Sendable {
    /// One coding section ("datagroup"). `address` is the hex block number
    /// written in E-Sys / cheat sheets ("3000") and doubles as the UDS DID.
    public struct Datagroup: Equatable, Sendable {
        public let addressText: String
        /// Numeric DID value, e.g. 12288 for "3000".
        public let address: Int
        public let datagroupClass: String?
        public let units: String?
        /// Which coding rule activates the whole section, resolved for `series`.
        public let activation: CAFDRule.Resolution
        public let functions: [Function]
    }

    /// One coding parameter: a byte range with a mask inside its datagroup.
    public struct Function: Equatable, Sendable {
        public let index: Int
        /// First byte offset inside the section (0-based).
        public let start: Int
        /// Last byte offset (inclusive).
        public let end: Int
        /// Raw `size` text from storageInfo, when present.
        public let sizeText: String?
        /// Raw mask text, e.g. "11111111b".
        public let maskText: String?
        /// Parsed mask (nil when absent or wider than one byte).
        public let mask: UInt8?
        public let values: [Value]

        /// The value the CAFD marks as default for this function.
        public var defaultValue: Value? { values.first { $0.isDefault } }

        /// OpenCAFDMap-style placeholder name when no community name exists.
        public var placeholderName: String {
            let mask = maskText ?? (self.mask.map { String(format: "%02X", $0) } ?? "")
            return "F_\(start)_\(end)_\(mask)"
        }
    }

    /// One choosable value of a function: its raw bytes plus the coding rule
    /// that selects it ("wert_01", "wert_02", ... in E-Sys).
    public struct Value: Equatable, Sendable {
        public let index: Int
        /// Joined `unitVal` hex text, e.g. "00", "01", "0123".
        public let hex: String
        public let isDefault: Bool
        /// The rule that selects this value, resolved for `series`.
        public let rule: CAFDRule.Resolution

        public var bytes: [UInt8]? { CAFD.parseHexBytes(hex) }
    }

    public let datagroups: [Datagroup]
    /// mainSeries names from fpInfo (e.g. ["F025", "F020"]), when present.
    public let mainSeries: [String]

    public init(datagroups: [Datagroup], mainSeries: [String] = []) {
        self.datagroups = datagroups
        self.mainSeries = mainSeries
    }

    public var functionCount: Int { datagroups.reduce(0) { $0 + $1.functions.count } }

    public func datagroup(address: Int) -> Datagroup? {
        datagroups.first { $0.address == address }
    }
}

/// A coding rule: an XPath-like expression over vehicle-order criteria, e.g.
/// `//cat[@val='3' and ...]`. CAFDs carry one per main series; the matching
/// one decides whether a datagroup or value applies to our car.
public struct CAFDRule: Equatable, Sendable {
    public let series: String?
    public let text: String
    public let isDefault: Bool

    public init(series: String?, text: String, isDefault: Bool) {
        self.series = series
        self.text = text
        self.isDefault = isDefault
    }

    /// How a rule list applies to one car — mirrors `series_rule()` in
    /// OpenCAFDMap's build_defdb.py: no rules = fixed; the rule whose
    /// mainSeries matches = applicable; rules exist but none match = n/a.
    public enum Resolution: Equatable, Sendable {
        case fixed
        case applicable(CAFDRule)
        case notApplicable
    }

    public static func resolve(_ rules: [CAFDRule], for series: String?) -> Resolution {
        if rules.isEmpty { return .fixed }
        if let series, let match = rules.first(where: { $0.series == series }) {
            return .applicable(match)
        }
        if series == nil, let fallback = rules.first(where: { $0.isDefault }) ?? rules.first {
            return .applicable(fallback)
        }
        return .notApplicable
    }
}

public enum CAFDError: Error, CustomStringConvertible, Sendable {
    case malformedXML(String)
    case notCAFDXML(String)

    public var description: String {
        switch self {
        case .malformedXML(let detail): return "CAFD XML: \(detail)"
        case .notCAFDXML(let detail): return "not a CAFD XML document (\(detail))"
        }
    }
}

// MARK: - Parsing

extension CAFD {
    /// Parses CAFD XML, gzip-wrapped or plain. `series` (e.g. "F025") selects
    /// which per-series coding rules apply; nil keeps them unresolved-by-series.
    public static func parse(data: Data, series: String? = nil) throws -> CAFD {
        let xml = try Gzip.unwrapIfGzip(data)
        let delegate = CAFDXMLDelegate(series: series)
        let parser = XMLParser(data: xml)
        parser.delegate = delegate
        guard parser.parse() else {
            throw CAFDError.malformedXML(parser.parserError?.localizedDescription ?? "parse error")
        }
        guard delegate.sawDataElement else {
            throw CAFDError.notCAFDXML("no <data> element — this is not decrypted CAFD data")
        }
        return CAFD(datagroups: delegate.datagroups, mainSeries: delegate.mainSeries)
    }

    public static func parse(url: URL, series: String? = nil) throws -> CAFD {
        try parse(data: try Data(contentsOf: url), series: series)
    }
}

// MARK: - Value helpers

extension CAFD {
    /// "3000" / "0x3000" → 12288. CAFD addresses are hex block numbers.
    public static func parseAddress(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var hex = trimmed
        if hex.hasPrefix("0x") || hex.hasPrefix("0X") { hex = String(hex.dropFirst(2)) }
        if let value = Int(hex, radix: 16) { return value }
        return Int(trimmed)
    }

    /// "11111111b" → 0xFF; also accepts plain hex like "FF". Nil when the mask
    /// is absent, malformed, or wider than one byte.
    public static func parseMask(_ text: String) -> UInt8? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("b"), trimmed.dropLast().allSatisfy({ $0 == "0" || $0 == "1" }) {
            return UInt8(trimmed.dropLast(), radix: 2)
        }
        return UInt8(trimmed, radix: 16)
    }

    /// "01", "1", "0123" → bytes. Tolerates odd-length hex by left-padding.
    public static func parseHexBytes(_ text: String) -> [UInt8]? {
        var clean = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !clean.isEmpty, clean.allSatisfy({ $0.isHexDigit }) else { return nil }
        if clean.count % 2 == 1 { clean = "0" + clean }
        return Bytes.fromHex(clean)
    }

    /// The function's bytes in a section, masked, as compact hex ("00").
    public static func maskedHex(sectionBytes: [UInt8], function: Function) -> String? {
        guard function.start >= 0, function.end < sectionBytes.count, function.start <= function.end else {
            return nil
        }
        let mask = function.mask ?? 0xFF
        let masked = sectionBytes[function.start...function.end].map { $0 & mask }
        return Bytes.hexCompact(masked)
    }
}

// MARK: - XML delegate

/// Event parser for the psdz.data.caf XML. Matches local element names and
/// ignores the namespace prefix, like OpenCAFDMap's decrypt.js does (the
/// decrypted DOM may or may not be namespace-aware).
final class CAFDXMLDelegate: NSObject, XMLParserDelegate {
    private enum Context {
        case root, data, datagroup, activatingCondition, function, storageInfo, condParam, values, other
    }

    let series: String?
    private(set) var datagroups: [CAFD.Datagroup] = []
    private(set) var mainSeries: [String] = []
    private(set) var sawDataElement = false

    private var stack: [Context] = [.root]
    private var text = ""

    // Datagroup under construction
    private var dgAddressText = "", dgClass: String?, dgUnits: String?
    private var dgActivationRules: [CAFDRule] = []
    private var dgFunctions: [CAFD.Function] = []
    // Function under construction
    private var fnStart: Int?, fnEnd: Int?, fnSize: String?, fnMask: String?
    private var fnValues: [CAFD.Value] = []
    // condParam under construction
    private var cpRules: [CAFDRule] = []
    private var cpUnitVals: [(position: Int, text: String)] = []
    // Rule element under construction
    private var pendingRuleSeries: String?
    private var pendingRuleIsDefault = false

    init(series: String?) {
        self.series = series
    }

    private func localName(_ elementName: String) -> String {
        if let range = elementName.range(of: ":") {
            return String(elementName[range.upperBound...])
        }
        return elementName
    }

    private func beginRule(_ attributes: [String: String]) {
        pendingRuleSeries = attributes["mainSeries"]
        pendingRuleIsDefault = attributes["isDefault"] == "true"
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        text = ""
        let name = localName(elementName)
        let parent = stack.last ?? .root
        switch (parent, name) {
        case (_, "mainSeries"):
            if let value = attributeDict["name"], !mainSeries.contains(value) {
                mainSeries.append(value)
            }
            stack.append(.other)
        case (_, "data"):
            sawDataElement = true
            stack.append(.data)
        case (_, "datagroup"):
            dgAddressText = (attributeDict["address"] ?? "").trimmingCharacters(in: .whitespaces).uppercased()
            dgClass = attributeDict["datagroupClass"]
            dgUnits = attributeDict["units"]
            dgActivationRules = []
            dgFunctions = []
            stack.append(.datagroup)
        case (.datagroup, "activatingCondition"):
            stack.append(.activatingCondition)
        case (.activatingCondition, "boolExpression"):
            beginRule(attributeDict)
            stack.append(.other)
        case (.datagroup, "function"):
            fnStart = nil; fnEnd = nil; fnSize = nil; fnMask = nil; fnValues = []
            stack.append(.function)
        case (.function, "storageInfo"):
            stack.append(.storageInfo)
        case (.function, "condParam"):
            cpRules = []; cpUnitVals = []
            stack.append(.condParam)
        case (.condParam, "bool"):
            beginRule(attributeDict)
            stack.append(.other)
        case (.condParam, "values"):
            stack.append(.values)
        case (.values, "unitVal"):
            cpUnitVals.append((Int(attributeDict["position"] ?? "0") ?? 0, ""))
            stack.append(.other)
        default:
            stack.append(.other)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let name = localName(elementName)
        let context = stack.popLast() ?? .root
        switch (context, name) {
        case (.other, "boolExpression"), (.other, "bool"):
            let rule = CAFDRule(series: pendingRuleSeries,
                                text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                                isDefault: pendingRuleIsDefault)
            // The enclosing container decides where the rule belongs.
            if stack.last == .condParam { cpRules.append(rule) }
            else if stack.last == .activatingCondition { dgActivationRules.append(rule) }
        case (.other, "start") where stack.last == .storageInfo:
            fnStart = Int(text.trimmingCharacters(in: .whitespaces))
        case (.other, "end") where stack.last == .storageInfo:
            fnEnd = Int(text.trimmingCharacters(in: .whitespaces))
        case (.other, "size") where stack.last == .storageInfo:
            fnSize = text.trimmingCharacters(in: .whitespaces)
        case (.other, "mask") where stack.last == .storageInfo:
            fnMask = text.trimmingCharacters(in: .whitespaces)
        case (.other, "unitVal") where stack.last == .values:
            if !cpUnitVals.isEmpty {
                cpUnitVals[cpUnitVals.count - 1].text =
                    text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            }
        case (.condParam, "condParam"):
            fnValues.append(makeValue())
        case (.function, "function"):
            appendFunction()
        case (.datagroup, "datagroup"):
            appendDatagroup()
        default:
            break
        }
    }

    private func makeValue() -> CAFD.Value {
        let sorted = cpUnitVals.sorted { $0.position < $1.position }
        let hex = sorted.map { $0.text }.joined()
        let resolution = CAFDRule.resolve(cpRules, for: series)
        let isDefault: Bool
        if case .applicable(let rule) = resolution { isDefault = rule.isDefault } else { isDefault = false }
        return CAFD.Value(index: fnValues.count, hex: hex, isDefault: isDefault, rule: resolution)
    }

    private func appendFunction() {
        let start = fnStart ?? 0
        let end = fnEnd ?? start
        fnValues.sort { $0.index < $1.index }
        dgFunctions.append(CAFD.Function(index: dgFunctions.count, start: start, end: end,
                                         sizeText: fnSize, maskText: fnMask,
                                         mask: fnMask.flatMap(CAFD.parseMask), values: fnValues))
    }

    private func appendDatagroup() {
        let address = CAFD.parseAddress(dgAddressText) ?? 0
        datagroups.append(CAFD.Datagroup(
            addressText: dgAddressText.isEmpty ? String(format: "%04X", address) : dgAddressText,
            address: address, datagroupClass: dgClass, units: dgUnits,
            activation: CAFDRule.resolve(dgActivationRules, for: series),
            functions: dgFunctions))
    }
}


