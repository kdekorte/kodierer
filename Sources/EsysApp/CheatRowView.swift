import SwiftUI
import EsysCore

/// One expandable cheat-sheet code row: operations, current bytes, Apply.
struct CheatRowView: View {
    @EnvironmentObject var model: AppModel
    let entry: CheatEntry
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(entry.code.operations.enumerated()), id: \.offset) { _, op in
                    operationLine(op).font(.callout.monospaced())
                }
                applyControl.padding(.top, 2)
            }
            .padding(.vertical, 2)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.code.description)
                Text(entry.code.cafdName ?? entry.code.cafdID ?? "—")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private func operationLine(_ op: FDLOperation) -> some View {
        HStack {
            Text(String(format: "§%04X byte %d–%d mask %02X → %@",
                        op.group, op.start, op.end, op.mask, valueText(op.value)))
            Spacer()
            if let bytes = model.backup?.sectionBytes(op.group),
               op.start < bytes.count, op.end < bytes.count {
                let current = (op.start...max(op.start, op.end))
                    .compactMap { bytes[$0] & op.mask }
                    .map { String(format: "%02X", $0) }
                    .joined()
                Text("current \(current)").foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder private var applyControl: some View {
        switch model.applicability(of: entry.code) {
        case .alreadyActive:
            Label("Already active", systemImage: "checkmark.circle")
                .foregroundColor(.green).font(.callout)
        case .wouldChange:
            if model.isConnected {
                Button("Apply to car") { Task { await model.applyCode(entry) } }
                    .disabled(model.applying)
            } else {
                Label("Not connected — connect to apply", systemImage: "wifi.slash")
                    .foregroundColor(.orange).font(.callout)
            }
        case .notApplicable(let why):
            Label(why, systemImage: "xmark.circle")
                .foregroundColor(.orange).font(.callout)
        }
    }

    private func valueText(_ value: FDLValue) -> String {
        switch value {
        case .bytes(let bytes): return bytes.map { String(format: "%02X", $0) }.joined()
        case .symbolic(let symbol): return symbol
        }
    }
}
