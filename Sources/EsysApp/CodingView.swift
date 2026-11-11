import SwiftUI
import EsysCore

/// Tab 2 — the coding backup: sections, cheat-sheet options, apply/restore.
struct CodingView: View {
    @EnvironmentObject var model: AppModel
    @State private var showCheatImporter = false
    @State private var showBackupImporter = false
    @State private var showBackupExporter = false
    @State private var confirmRestore = false

    var body: some View {
        VStack(spacing: 0) {
            StatusBanner()
            if let backup = model.backup {
                content(backup)
            } else {
                emptyState
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "externaldrive.badge.timemachine")
                .font(.system(size: 40)).foregroundColor(.secondary)
            Text("No coding backup yet").font(.title3)
            Text("Connect on the Car tab and press “Read coding”, or load a backup JSON saved earlier.")
                .font(.callout).foregroundColor(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 460)
            Button("Load backup JSON…") { showBackupImporter = true }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fileImporter(isPresented: $showBackupImporter, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result { model.loadBackup(url: url) }
        }
    }

    private func content(_ backup: CodingBackup) -> some View {
        List {
            Section("Backup") {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(backup.ecuName ?? String(format: "ECU 0x%02X", backup.ecuAddress))
                            .font(.headline)
                        Text("\(backup.sections.count) sections · \(backup.sections.reduce(0) { $0 + $1.bytes.count }) bytes · VIN \(backup.vin ?? "?")")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Save…") { showBackupExporter = true }
                    Button("Re-read") { Task { await model.rereadCoding() } }
                        .disabled(!model.isConnected)
                    Button("Restore") { confirmRestore = true }
                        .disabled(!model.isConnected)
                }
                .padding(.vertical, 2)
            }

            Section("Sections") {
                ForEach(backup.sections, id: \.did) { section in
                    HStack {
                        Text(String(format: "§ %04X", section.did)).font(.callout.monospaced())
                        Text("\(section.bytes.count) bytes").font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Text(hexPreview(section.bytes)).font(.caption.monospaced()).foregroundColor(.secondary)
                    }
                }
            }

            if !model.queue.isEmpty {
                Section("Queued changes") {
                    QueueBar().listRowInsets(EdgeInsets())
                }
            }

            Section {
                ForEach(model.cheatEntries) { entry in
                    CheatRowView(entry: entry)
                }
                if model.cheatEntries.isEmpty {
                    Text("No cheat-sheet codes loaded.").foregroundColor(.secondary)
                }
            } header: {
                Text("Coding options (cheat sheets)")
            } footer: {
                HStack {
                    Button("Open FDLCodes.xml…") { showCheatImporter = true }
                    Button("Load demo definitions") { model.loadDemoDefinitions() }
                    Spacer()
                    Text("\(model.cheatEntries.count) codes").foregroundColor(.secondary)
                }
            }
        }
        .listStyle(.inset)
        .fileImporter(isPresented: $showCheatImporter, allowedContentTypes: [.xml]) { result in
            if case .success(let url) = result { model.loadCheatSheet(url: url) }
        }
        .fileExporter(isPresented: $showBackupExporter, document: BackupDocument(backup),
                      contentType: .json, defaultFilename: defaultName(backup)) { result in
            if case .success(let url) = result {
                model.showMessage("Saved \(url.lastPathComponent)")
            }
        }
        .confirmationDialog("Restore the saved snapshot to the ECU?",
                            isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("Restore", role: .destructive) { Task { await model.restoreOriginal() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Writes every section of the backup back to the car. On a real HU_NBT this needs the security algorithm, which is not implemented yet — the write will be refused.")
        }
    }

    private func defaultName(_ backup: CodingBackup) -> String {
        "\(backup.ecuName ?? "ecu")-\(String(format: "%02X", backup.ecuAddress))-backup.json"
    }
}
