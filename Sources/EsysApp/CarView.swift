import SwiftUI
import EsysCore

/// Tab 1 — connect (virtual demo car or the real one), scan, read coding.
struct CarView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            StatusBanner()
            Picker("Mode", selection: $model.mode) {
                ForEach(AppModel.Mode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 380)
            .padding([.top, .horizontal])
            if model.isConnected {
                connectedPanel
            } else if model.mode == .demo {
                demoPanel
            } else {
                realPanel
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Demo

    private var demoPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Runs the whole stack against an in-process virtual F25 — no car, no risk: connect, identify, scan, read coding, write with security unlock and verification.")
                .font(.callout).foregroundColor(.secondary)
                .frame(maxWidth: 560, alignment: .leading)
            Button("Start demo car") { Task { await model.startDemo() } }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    // MARK: Real car

    private var realPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let hint = model.linkLocalHint {
                Label(hint, systemImage: "bolt.slash.fill").font(.callout).foregroundColor(.orange)
            }
            HStack {
                TextField("Gateway IP (169.254.x.x)", text: $model.host)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
                Button("Discover") { Task { await model.discover() } }
                    .disabled(model.discovering)
                Button("Connect & Scan") { Task { await model.connectAndScan() } }
                    .disabled(model.host.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if model.discovering { ProgressView("Searching for cars…") }
            if !model.advertisements.isEmpty {
                Text("Cars that answered:").font(.caption).foregroundColor(.secondary)
                ForEach(model.advertisements, id: \.host) { ad in
                    Button {
                        model.host = ad.host
                    } label: {
                        Label("\(ad.host) — VIN \(ad.vin ?? "?")", systemImage: "car")
                    }
                    .buttonStyle(.borderless)
                }
            }
            if !model.probedHosts.isEmpty {
                Text("Open diagnostic ports (no identification reply):")
                    .font(.caption).foregroundColor(.secondary)
                ForEach(model.probedHosts, id: \.self) { host in
                    Button(host) { model.host = host }.buttonStyle(.borderless)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    // MARK: Connected

    private var connectedPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.mode == .demo ? "Virtual car" : model.host).font(.title3)
                    Text("VIN \(model.identity?.vin ?? "?") · I-Step \(model.identity?.iStepText.first ?? "?")")
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                if model.busy.isEmpty && !model.scanning {
                    Button("Disconnect", role: .destructive) { model.disconnect() }
                } else {
                    ProgressView(model.scanning ? "scanning" : model.busy)
                }
            }
            .padding(.horizontal)
            if model.scanning {
                ProgressView("Found \(model.modules.count) modules…").padding(.horizontal)
            }
            List {
                ForEach(model.modules, id: \.address) { module in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(module.displayName)
                            if let cafd = module.svk?.primaryCAFD {
                                Text(cafd.fileName).font(.caption.monospaced()).foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        if model.reading {
                            ProgressView()
                        } else {
                            Button("Read coding") { Task { await model.readCoding(module) } }
                                .disabled(!model.busy.isEmpty && !model.scanning)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.inset)
            if let backup = model.backup {
                Text("Backup in memory: \(backup.ecuName ?? "ECU"), \(backup.sections.count) sections — continue in the Coding tab.")
                    .font(.caption).foregroundColor(.secondary)
                    .padding(.horizontal).padding(.bottom, 8)
            }
        }
    }
}
