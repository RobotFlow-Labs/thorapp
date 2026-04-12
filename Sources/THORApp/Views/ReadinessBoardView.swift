import SwiftUI
import THORShared

struct ReadinessBoardView: View {
    let deviceID: Int64
    @Environment(AppState.self) private var appState

    var body: some View {
        let report = appState.readinessReport(for: deviceID)

        GroupBox("Readiness Board") {
            if report.items.isEmpty {
                Text("No readiness data yet. Connect the device or run setup.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(report.items) { item in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(color(for: item.status))
                                .frame(width: 10, height: 10)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.system(size: 13, weight: .medium))
                                Text(item.summary)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(item.status.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(color(for: item.status))
                        }
                        .padding(.vertical, 8)

                        if item.id != report.items.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func color(for status: ReadinessStatus) -> Color {
        switch status {
        case .ready: .green
        case .warning: .orange
        case .blocked: .red
        case .unknown: .secondary
        }
    }
}
