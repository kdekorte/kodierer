import SwiftUI
import UniformTypeIdentifiers
import KodiererCore

extension UTType {
    /// Community names files (OpenCAFDMap `names/*.tsv`).
    static let tsvFile = UTType(filenameExtension: "tsv") ?? .plainText
}

/// One change the user lined up: an FDL operation plus a readable label.
struct PendingChange: Identifiable, Equatable {
    let id = UUID()
    let label: String
    let operation: FDLOperation
    /// Identifies the function this change belongs to, so re-picking a value
    /// replaces the earlier queued choice instead of stacking duplicates.
    var key: String? = nil
    /// Hex of the queued CAFD value — used to show which choice is pending.
    var choiceID: String? = nil

    /// Stable identity of one function inside a CAFD.
    static func key(datagroup: CAFD.Datagroup, function: CAFD.Function) -> String {
        let mask = function.mask.map { String(format: "%02X", $0) } ?? (function.maskText ?? "-")
        return "\(datagroup.address)|\(function.start)|\(function.end)|\(mask)"
    }
}

/// A cheat-sheet code with a stable identity for list rendering.
struct CheatEntry: Identifiable {
    let id: String
    let code: FDLCheatCode
}

/// First bytes of a section as hex, for one-line previews.
func hexPreview(_ bytes: [UInt8], limit: Int = 12) -> String {
    let head = bytes.prefix(limit).map { String(format: "%02X", $0) }.joined(separator: " ")
    return bytes.count > limit ? head + " …" : head
}

/// Banner for the latest error / success message.
struct StatusBanner: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if let error = model.errorText {
            banner(error, systemImage: "exclamationmark.triangle.fill", color: .red)
        } else if let message = model.message {
            banner(message, systemImage: "checkmark.circle.fill", color: .green)
        }
    }

    private func banner(_ text: String, systemImage: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage).foregroundColor(color)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Dismiss") { model.clearFeedback() }.buttonStyle(.borderless)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.08)))
        .padding(.horizontal)
        .padding(.top, 8)
    }
}

/// Shows queued changes with Apply / Clear. Renders nothing when empty.
struct QueueBar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if !model.queue.isEmpty {
            VStack(spacing: 6) {
                ForEach(model.queue) { change in
                    Text("• \(change.label)").font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    if model.applying { ProgressView() }
                    Button(model.applying ? "Applying…" : "Apply to car") {
                        Task { await model.applyQueue() }
                    }
                    .disabled(model.applying || !model.canApply)
                    Button("Clear") { model.queue = [] }.disabled(model.applying)
                    Spacer()
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.yellow.opacity(0.12)))
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }
}

/// Codable wrapper so SwiftUI's fileExporter can save a backup.
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let backup: CodingBackup

    init(_ backup: CodingBackup) { self.backup = backup }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        backup = try decoder.decode(CodingBackup.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return FileWrapper(regularFileWithContents: try encoder.encode(backup))
    }
}
