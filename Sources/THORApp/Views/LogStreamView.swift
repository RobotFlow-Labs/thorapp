import SwiftUI
import THORShared

struct LogStreamView: View {
    let deviceID: Int64
    @Environment(AppState.self) private var appState
    @State private var logLines: [String] = []
    @State private var isStreaming = false
    @State private var selectedSource = LogSource.system
    @State private var filterText = ""
    @State private var autoScroll = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            controlBar
            logContent
        }
    }

    private var controlBar: some View {
        HStack(spacing: 12) {
            Label("Logs", systemImage: "doc.text")
                .font(.system(size: 14, weight: .medium))

            Picker("Source", selection: $selectedSource) {
                ForEach(LogSource.allCases, id: \.self) { source in
                    Text(source.label).tag(source)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 250)

            TextField("Filter...", text: $filterText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 150)

            Spacer()

            Toggle("Auto-scroll", isOn: $autoScroll)
                .toggleStyle(.switch)
                .controlSize(.small)

            Button {
                Task { await fetchLogs() }
            } label: {
                if isStreaming {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
        }
    }

    private var logContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(filteredLines.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(lineColor(for: line))
                            .textSelection(.enabled)
                            .id(index)
                    }
                }
                .padding(8)
            }
            .background(Color(.textBackgroundColor))
            .clipShape(.rect(cornerRadius: 8))
            .onChange(of: logLines.count) {
                if autoScroll, let last = filteredLines.indices.last {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        }
        .overlay {
            if logLines.isEmpty && !isStreaming {
                Text("No logs. Click refresh to fetch.")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))
            }
        }
        .task(id: selectedSource) {
            await fetchLogs()
        }
    }

    private var filteredLines: [String] {
        if filterText.isEmpty { return logLines }
        return logLines.filter { $0.localizedCaseInsensitiveContains(filterText) }
    }

    private func lineColor(for line: String) -> Color {
        let lower = line.lowercased()
        if lower.contains("error") || lower.contains("fatal") { return .red }
        if lower.contains("warn") { return .orange }
        if lower.contains("debug") { return .secondary }
        return .primary
    }

    private func fetchLogs() async {
        guard let client = appState.connector?.agentClient(for: deviceID) else { return }
        isStreaming = true
        errorMessage = nil
        do {
            let response: LogStreamResponse
            switch selectedSource {
            case .system:
                response = try await client.systemLogs(lines: 200)
            case .agent:
                response = try await client.agentLogs(lines: 100)
            }
            logLines = response.lines
            if let err = response.error { errorMessage = err }
        } catch {
            errorMessage = error.localizedDescription
        }
        isStreaming = false
    }
}

private enum LogSource: String, CaseIterable {
    case system
    case agent

    var label: String {
        switch self {
        case .system: "System"
        case .agent: "Agent"
        }
    }
}
