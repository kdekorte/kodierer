import SwiftUI
import UniformTypeIdentifiers
import KodiererCore

/// Tab 2 — the BimmerCode-style coding screen: a searchable tree of
/// Category → Option → Choice, plus the backup controls and cheat sheets.
struct CodingView: View {
    @EnvironmentObject var model: AppModel
    @State private var searchText = ""
    @State private var showCheatImporter = false
    @State private var showCAFDImporter = false
    @State private var showNamesImporter = false
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

            if let cafd = model.cafd {
                optionSections(cafd)
            } else {
                Section {
                    Text("Load a CAFD + community names to browse named coding options here.")
                        .foregroundColor(.secondary)
                } header: {
                    Text("Coding options")
                } footer: {
                    HStack {
                        Button("Open CAFD…") { showCAFDImporter = true }
                        Button("Names…") { showNamesImporter = true }
                        Button("Load demo definitions") { model.loadDemoDefinitions() }
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
        .fileImporter(isPresented: $showCAFDImporter, allowedContentTypes: [.xml, .gzip, .data]) { result in
            if case .success(let url) = result { model.loadCAFD(url: url) }
        }
        .fileImporter(isPresented: $showNamesImporter, allowedContentTypes: [UTType.tsvFile, .plainText]) { result in
            if case .success(let url) = result { model.loadNames(url: url) }
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

    // MARK: Option tree

    /// The BimmerCode-style tree: one section per category, one row per option.
    @ViewBuilder private func optionSections(_ cafd: CAFD) -> some View {
        let categories = OptionTree.filter(
            OptionTree.categories(cafd: cafd, names: model.names, backup: model.backup),
            matching: searchText)
        ForEach(categories) { category in
            Section {
                ForEach(category.options) { option in
                    OptionRowView(option: option)
                }
            } header: {
                HStack {
                    Text(category.name)
                    Spacer()
                    Text("\(category.options.count) options")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
        }
        Section {
            HStack {
                TextField("Search options", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                TextField("Series", text: $model.cafdSeries)
                    .textFieldStyle(.roundedBorder).frame(width: 80)
                    .onSubmit { model.reloadCAFD() }
                Button("Resolve") { model.reloadCAFD() }
                Spacer()
                Text("\(cafd.functionCount) functions · \(model.cafdFileName)")
                    .font(.caption).foregroundColor(.secondary)
            }
        } header: {
            Text("Coding options")
        } footer: {
            HStack {
                Button("Open CAFD…") { showCAFDImporter = true }
                Button("Names…") { showNamesImporter = true }
                Button("Load demo definitions") { model.loadDemoDefinitions() }
                Spacer()
                Text("Pick a value to queue the change; Apply to car writes the queue.")
            }
        }
    }

    private func defaultName(_ backup: CodingBackup) -> String {
        "\(backup.ecuName ?? "ecu")-\(String(format: "%02X", backup.ecuAddress))-backup.json"
    }
}
