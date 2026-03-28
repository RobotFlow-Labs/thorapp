import SwiftUI
import THORShared

struct EventTimelineView: View {
    let deviceID: Int64
    @Environment(AppState.self) private var appState
    @State private var events: [TimelineEvent] = []
    @State private var isLoading = false
    @State private var filterType: TimelineEventType?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerRow
            filterBar
            eventList
        }
        .task { await loadEvents() }
    }

    private var headerRow: some View {
        HStack {
            Label("Event Timeline", systemImage: "clock.arrow.circlepath")
                .font(.system(size: 14, weight: .medium))
            Spacer()
            Button {
                Task { await loadEvents() }
            } label: {
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
        }
    }

    private var filterBar: some View {
        HStack(spacing: 4) {
            filterButton(nil, label: "All")
            filterButton(.job, label: "Jobs")
            filterButton(.connection, label: "Connections")
            filterButton(.deploy, label: "Deploys")
            filterButton(.transfer, label: "Transfers")
            Spacer()
        }
    }

    private func filterButton(_ type: TimelineEventType?, label: String) -> some View {
        Button(label) {
            filterType = type
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .tint(filterType == type ? .accentColor : .secondary)
    }

    private var eventList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                let filtered = filterType == nil ? events : events.filter { $0.type == filterType }
                if filtered.isEmpty {
                    Text("No events")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 13))
                        .frame(maxWidth: .infinity, minHeight: 60)
                } else {
                    ForEach(filtered) { event in
                        eventRow(event)
                        Divider().padding(.leading, 40)
                    }
                }
            }
        }
        .background(Color(.secondarySystemFill).opacity(0.3))
        .clipShape(.rect(cornerRadius: 10))
    }

    private func eventRow(_ event: TimelineEvent) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: event.icon)
                .font(.system(size: 12))
                .foregroundStyle(event.color)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(event.title)
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text(event.timestamp, style: .relative)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                if let detail = event.detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func loadEvents() async {
        guard let db = appState.db else { return }
        isLoading = true
        do {
            let jobs = try await db.reader.read { dbConn in
                try Job
                    .filter(Column("deviceID") == deviceID)
                    .order(Column("createdAt").desc)
                    .limit(50)
                    .fetchAll(dbConn)
            }
            events = jobs.map { job in
                TimelineEvent(
                    type: job.jobType == .fileSync || job.jobType == .fileUpload ? .transfer :
                          job.jobType == .animaDeploy || job.jobType == .deploy ? .deploy :
                          .job,
                    title: "\(job.jobType.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)",
                    detail: job.status == .failed ? job.errorSummary : nil,
                    timestamp: job.createdAt,
                    status: job.status
                )
            }
        } catch {
            events = []
        }
        isLoading = false
    }
}

struct TimelineEvent: Identifiable {
    let id = UUID()
    let type: TimelineEventType
    let title: String
    let detail: String?
    let timestamp: Date
    let status: JobStatus

    var icon: String {
        switch type {
        case .job: status == .success ? "checkmark.circle" : status == .failed ? "xmark.circle" : "circle"
        case .connection: "link"
        case .deploy: "play.rectangle"
        case .transfer: "arrow.up.doc"
        }
    }

    var color: Color {
        switch status {
        case .success: .green
        case .failed: .red
        case .running: .blue
        case .cancelled: .gray
        default: .secondary
        }
    }
}

enum TimelineEventType: Equatable {
    case job
    case connection
    case deploy
    case transfer
}
