import SwiftUI
import THORShared

struct TransferHistoryView: View {
    let deviceID: Int64
    @Environment(AppState.self) private var appState
    @State private var records: [TransferRecord] = []
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Transfer History", systemImage: "clock.arrow.2.circlepath")
                    .font(.system(size: 14, weight: .medium))
                Spacer()
                Button {
                    Task { await loadRecords() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
            }

            if records.isEmpty && !isLoading {
                Text("No transfers recorded")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                recordTable
            }
        }
        .task { await loadRecords() }
    }

    private var recordTable: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Source").frame(width: 200, alignment: .leading)
                Text("Target").frame(width: 200, alignment: .leading)
                Text("Size").frame(width: 80, alignment: .trailing)
                Text("Verified").frame(width: 60, alignment: .center)
                Text("Date").frame(width: 120, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(records) { record in
                        HStack {
                            Text(shortenPath(record.sourcePath))
                                .frame(width: 200, alignment: .leading)
                            Text(shortenPath(record.targetPath))
                                .frame(width: 200, alignment: .leading)
                            Text(formatBytes(record.bytesTransferred))
                                .frame(width: 80, alignment: .trailing)
                            Image(systemName: record.verified ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(record.verified ? .green : .gray)
                                .frame(width: 60, alignment: .center)
                            Text(record.createdAt, style: .date)
                                .frame(width: 120, alignment: .trailing)
                        }
                        .font(.system(size: 11, design: .monospaced))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        Divider().padding(.leading, 12)
                    }
                }
            }
        }
        .background(Color(.secondarySystemFill).opacity(0.3))
        .clipShape(.rect(cornerRadius: 10))
    }

    private func loadRecords() async {
        guard let db = appState.db else { return }
        isLoading = true
        do {
            records = try await db.reader.read { dbConn in
                try TransferRecord
                    .filter(Column("deviceID") == deviceID)
                    .order(Column("createdAt").desc)
                    .limit(50)
                    .fetchAll(dbConn)
            }
        } catch {
            records = []
        }
        isLoading = false
    }

    private func shortenPath(_ path: String) -> String {
        let components = path.components(separatedBy: "/")
        if components.count > 3 {
            return ".../" + components.suffix(2).joined(separator: "/")
        }
        return path
    }

    private func formatBytes(_ bytes: Int64?) -> String {
        guard let b = bytes, b > 0 else { return "—" }
        if b < 1024 { return "\(b) B" }
        if b < 1024 * 1024 { return "\(b / 1024) KB" }
        return "\(b / (1024 * 1024)) MB"
    }
}
