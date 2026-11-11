import SwiftUI
import KodiererCore

/// One BimmerCode-style option row: a named function with a toggle (on/off),
/// segmented picker (few choices) or menu (many choices). Picking a value
/// queues it; picking the current value reverts the option. The pencil button
/// opens a raw-hex editor for values that are not named choices.
struct OptionRowView: View {
    @EnvironmentObject var model: AppModel
    let option: CodingOption
    @State private var showHexEditor = false
    @State private var hexDraft = ""

    /// The choice queued for this option, if any.
    private var queuedChoice: CodingChoice? {
        guard let queuedID = model.queue.first(where: { $0.key == option.key })?.choiceID else { return nil }
        return option.choices.first { $0.id == queuedID }
    }

    /// True when a raw (non-choice) value is queued for this option.
    private var customQueued: Bool {
        model.queue.contains { $0.key == option.key && $0.choiceID == nil }
    }

    /// What the control shows: the queued choice, else the car's current value.
    private var selectedChoice: CodingChoice? {
        queuedChoice ?? option.currentChoice
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(option.title)
                if let description = option.description {
                    Text(description)
                        .font(.caption).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 6) {
                    Text(option.subtitle)
                        .font(.caption.monospaced()).foregroundColor(.secondary)
                    if let queued = queuedChoice {
                        badge("→ \(queued.name)", .orange)
                    } else if customQueued {
                        badge("→ custom", .orange)
                    } else if option.currentChoice == nil {
                        badge("not set", .secondary)
                    }
                }
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                control
                if model.backup != nil {
                    Button {
                        hexDraft = selectedChoice?.value.hex ?? ""
                        showHexEditor = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .buttonStyle(.borderless)
                    .help("Set a raw hex value (edit Werte)")
                }
            }
        }
        .padding(.vertical, 2)
        .alert("Raw value for \(option.title)", isPresented: $showHexEditor) {
            TextField("Hex bytes, e.g. 0A or 00FF", text: $hexDraft)
            Button("Set") { model.setRaw(hex: hexDraft, for: option) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(option.subtitle) — current: \(option.currentChoice?.value.hex ?? "?")")
        }
    }

    // MARK: Controls

    @ViewBuilder private var control: some View {
        if model.backup == nil {
            Text("read a backup to change").font(.caption2).foregroundColor(.secondary)
        } else if option.choices.count == 2 {
            toggle
        } else if option.choices.count <= 5 {
            segmented
        } else {
            menu
        }
    }

    /// On/off: the non-default choice is "on".
    private var toggle: some View {
        let off = option.choices.first { $0.isDefault } ?? option.choices.first!
        let on = option.choices.first { !$0.isDefault } ?? option.choices.last!
        return Toggle(isOn: Binding(
            get: { selectedChoice?.id == on.id },
            set: { model.setChoice($0 ? on : off, for: option) })) {
                Text(option.title)
            }
            .toggleStyle(.switch)
            .labelsHidden()
            .frame(width: 90, alignment: .trailing)
    }

    private var segmented: some View {
        Picker(option.title, selection: Binding(
            get: { selectedChoice?.id ?? "" },
            set: { newID in
                if let choice = option.choices.first(where: { $0.id == newID }) {
                    model.setChoice(choice, for: option)
                }
            })) {
            ForEach(option.choices) { choice in
                Text(choice.name).tag(choice.id)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 300)
    }

    private var menu: some View {
        Picker(option.title, selection: Binding(
            get: { selectedChoice?.id ?? "" },
            set: { newID in
                if let choice = option.choices.first(where: { $0.id == newID }) {
                    model.setChoice(choice, for: option)
                }
            })) {
            Text("—").tag("")
            ForEach(option.choices) { choice in
                Text(choice.name).tag(choice.id)
            }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: 260)
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text).font(.caption2)
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.12)))
            .foregroundColor(color)
    }
}
