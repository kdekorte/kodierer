import SwiftUI
import EsysCore

/// One CAFD function row: expand for its values; Set queues a change.
struct CAFDFunctionRowView: View {
    @EnvironmentObject var model: AppModel
    let row: CAFDFunctionRow
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(Array(row.function.values.enumerated()), id: \.offset) { _, value in
                valueRow(value)
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.matchedName)
                    Text(subtitle).font(.caption.monospaced()).foregroundColor(.secondary)
                }
                Spacer()
                currentBadge
            }
        }
    }

    private var subtitle: String {
        let mask = row.function.maskText
            ?? row.function.mask.map { String(format: "%02X", $0) } ?? "—"
        return String(format: "§%04X · bytes %d–%d · mask %@",
                      row.datagroup.address, row.function.start, row.function.end, mask)
    }

    @ViewBuilder private var currentBadge: some View {
        if let current = model.currentValue(datagroup: row.datagroup, function: row.function) {
            let label = model.names?.valueName(datagroup: row.datagroup, function: row.function, value: current)
                ?? "wert_\(String(format: "%02d", current.index))"
            Text(label).font(.caption)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.accentColor.opacity(0.12)))
        } else if model.backup != nil {
            Text("—").font(.caption).foregroundColor(.secondary)
        }
    }

    private func valueRow(_ value: CAFD.Value) -> some View {
        let isCurrent = model.currentValue(datagroup: row.datagroup, function: row.function) == value
        let valueLabel = model.names?.valueName(datagroup: row.datagroup, function: row.function, value: value)
            ?? "wert_\(String(format: "%02d", value.index))"
        return HStack {
            Text(valueLabel)
            Text(value.hex).font(.callout.monospaced()).foregroundColor(.secondary)
            if value.isDefault { badge("default", .secondary) }
            if value.rule == .notApplicable { badge("n/a for series", .red) }
            Spacer()
            if model.backup == nil {
                Text("read a backup to set").font(.caption2).foregroundColor(.secondary)
            } else if isCurrent {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
            } else {
                Button("Set") {
                    model.queueSet(value: value, function: row.function, datagroup: row.datagroup)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text).font(.caption2)
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.12)))
            .foregroundColor(color)
    }
}
