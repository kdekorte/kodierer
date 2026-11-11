import Foundation
import KodiererCore

// The BimmerCode-style view model: Category → Option → Choice.
//
// Everything is derived on demand from the loaded CAFD (what can be changed),
// the community names list (what it is called) and the coding backup (what the
// car currently has), so the tree always matches the latest state.

/// One choosable value of an option, with its community name.
struct CodingChoice: Identifiable, Equatable {
    /// The value's raw hex (stable within a function).
    let id: String
    let value: CAFD.Value
    let name: String
    let isDefault: Bool
}

/// One coding option: a named CAFD function with its choices and current state.
struct CodingOption: Identifiable, Equatable {
    /// PendingChange.key for this function.
    let key: String
    let id: String
    let category: String
    let title: String
    /// Plain-language description from the community option list, if any.
    let description: String?
    /// Human-readable context: section, byte range, mask.
    let subtitle: String
    let datagroup: CAFD.Datagroup
    let function: CAFD.Function
    let choices: [CodingChoice]
    /// Hex of the choice the backup currently has (nil when unread/unknown).
    let currentChoiceID: String?

    var currentChoice: CodingChoice? { choices.first { $0.id == currentChoiceID } }
}

/// A category with its options, in display order.
struct OptionCategory: Identifiable {
    let name: String
    let options: [CodingOption]
    var id: String { name }
}

/// Builds the option tree from the loaded definitions and the current state.
enum OptionTree {

    static func categories(cafd: CAFD, names: CAFDNames?, descriptions: OptionDescriptions? = nil,
                           backup: CodingBackup?) -> [OptionCategory] {
        var byCategory: [String: [CodingOption]] = [:]
        var order: [String] = []

        for datagroup in cafd.datagroups {
            for function in datagroup.functions {
                // Only values that apply to the resolved series and carry bytes.
                let usable = function.values.filter { $0.rule != .notApplicable && $0.bytes != nil }
                guard !usable.isEmpty else { continue }

                let title = names?.functionName(datagroup: datagroup, function: function)
                    ?? function.placeholderName
                let described = descriptions?.entry(named: title)
                let category = names?.functionCategory(datagroup: datagroup, function: function)
                    ?? described?.category
                    ?? names?.groupName(datagroup: datagroup)
                    ?? String(format: "Section %04X", datagroup.address)

                let choices = usable.map { value in
                    CodingChoice(
                        id: value.hex,
                        value: value,
                        name: names?.valueName(datagroup: datagroup, function: function, value: value)
                            ?? "wert_\(String(format: "%02d", value.index))",
                        isDefault: value.isDefault)
                }

                let current = backup.flatMap {
                    cafd.currentValue(of: function, in: datagroup, backup: $0)
                }

                let mask = function.maskText
                    ?? function.mask.map { String(format: "%02X", $0) } ?? "—"
                let subtitle = String(format: "§%04X · byte %d–%d · mask %@",
                                      datagroup.address, function.start, function.end, mask)

                let option = CodingOption(
                    key: PendingChange.key(datagroup: datagroup, function: function),
                    id: PendingChange.key(datagroup: datagroup, function: function),
                    category: category, title: title, description: described?.description,
                    subtitle: subtitle,
                    datagroup: datagroup, function: function, choices: choices,
                    currentChoiceID: current?.hex)

                if byCategory[category] == nil {
                    byCategory[category] = []
                    order.append(category)
                }
                byCategory[category]?.append(option)
            }
        }
        return order.map { OptionCategory(name: $0, options: byCategory[$0] ?? []) }
    }

    /// Options whose title or a choice name matches the query (case-insensitive).
    static func filter(_ categories: [OptionCategory], matching query: String) -> [OptionCategory] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return categories }
        return categories.compactMap { category in
            let matches = category.options.filter {
                $0.title.lowercased().contains(trimmed)
                    || $0.subtitle.lowercased().contains(trimmed)
                    || $0.choices.contains { $0.name.lowercased().contains(trimmed) }
            }
            return matches.isEmpty ? nil : OptionCategory(name: category.name, options: matches)
        }
    }
}
