import Foundation

/// One `<cafd>` block of a cheat sheet.
public struct CheatCAFD: Equatable, Sendable {
    public let id: String?
    public let name: String?
    public let codes: [FDLCheatCode]
}

/// Parser for the community "FDL codes" XML format used by cheat sheets:
///
///     <FDL>
///       <cafd id="00000794" name="FEM_BODY">
///         <code description="Angel Eyes Parking Light Brightness 50%">
///           <group id="3062">
///             <function start="68" end="68" mask="11111111b">32</function>
///           </group>
///         </code>
///       </cafd>
///     </FDL>
///
/// The E-Sys Launcher cheat format is a superset of this idea; supporting it is
/// a planned follow-up (see Docs/PARAMETERS.md).
public struct CheatSheet: Sendable {
    public let cafds: [CheatCAFD]

    public init(cafds: [CheatCAFD]) {
        self.cafds = cafds
    }

    public static func parse(url: URL) throws -> CheatSheet {
        try parse(data: try Data(contentsOf: url))
    }

    public static func parse(data: Data) throws -> CheatSheet {
        let delegate = CheatSheetParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw parser.parserError ?? FDLEditError.unresolvedSymbol("XML parse error")
        }
        return CheatSheet(cafds: delegate.cafds)
    }

    /// All codes, optionally filtered to one CAFD id (hex string) or ECU name.
    public func codes(cafdID: String? = nil, ecuName: String? = nil) -> [FDLCheatCode] {
        cafds.filter { cafd in
            (cafdID == nil || cafd.id?.lowercased() == cafdID?.lowercased())
                && (ecuName == nil || cafd.name?.uppercased() == ecuName?.uppercased())
        }.flatMap(\.codes)
    }

    public func cafd(named name: String) -> CheatCAFD? {
        cafds.first { $0.name?.uppercased() == name.uppercased() }
    }

    public func cafd(id: String) -> CheatCAFD? {
        cafds.first { $0.id?.lowercased() == id.lowercased() }
    }
}

final class CheatSheetParserDelegate: NSObject, XMLParserDelegate {
    var cafds: [CheatCAFD] = []

    private var cafdID: String?
    private var cafdName: String?
    private var codeDescription: String?
    private var operations: [FDLOperation] = []
    private var groupID: Int?
    private var functionStart: Int?
    private var functionEnd: Int?
    private var functionMask: UInt8?
    private var text = ""

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        text = ""
        switch element.lowercased() {
        case "cafd":
            cafdID = attributes["id"]
            cafdName = attributes["name"]
        case "code":
            codeDescription = attributes["description"] ?? ""
            operations = []
        case "group":
            // Group ids are hex block numbers ("3062" = 0x3062 = DID 12386).
            groupID = attributes["id"].flatMap { Int($0, radix: 16) }
        case "function":
            functionStart = attributes["start"].flatMap { Int($0) }
            functionEnd = attributes["end"].flatMap { Int($0) }
            functionMask = attributes["mask"].flatMap(Self.parseMask)
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?,
                qualifiedName: String?) {
        switch element.lowercased() {
        case "function":
            if let group = groupID, let start = functionStart, let end = functionEnd ?? functionStart {
                operations.append(FDLOperation(
                    group: group, start: start, end: end,
                    mask: functionMask ?? 0xFF,
                    value: FDLValue.parse(text)))
            }
        case "code":
            if codeDescription != nil, !operations.isEmpty {
                pendingCodes.append(FDLCheatCode(
                    cafdID: cafdID, cafdName: cafdName,
                    description: codeDescription!, operations: operations))
                operations = []
            }
        case "cafd":
            cafds.append(CheatCAFD(id: cafdID, name: cafdName, codes: pendingCodes))
            pendingCodes = []
        default:
            break
        }
    }

    private var pendingCodes: [FDLCheatCode] = []

    static func parseMask(_ text: String) -> UInt8? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix("b") {
            return UInt8(trimmed.dropLast(), radix: 2)
        }
        return UInt8(trimmed, radix: 16) ?? UInt8(trimmed, radix: 2)
    }
}
