import SwiftUI
import THORShared

struct SystemInfoView: View {
    let deviceID: Int64
    @Environment(AppState.self) private var appState
    @State private var sysInfo: SystemInfoResponse?
    @State private var disksInfo: DisksResponse?
    @State private var swapInfo: SwapResponse?
    @State private var networkInfo: NetworkInterfacesResponse?
    @State private var usersInfo: UsersResponse?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label("System Information", systemImage: "info.circle")
                    .font(.system(size: 14, weight: .medium))
                Spacer()
                Button { Task { await loadAll() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
            }

            if isLoading && sysInfo == nil {
                ProgressView("Loading...").frame(maxWidth: .infinity, minHeight: 100)
            } else {
                systemCard
                storageCard
                networkCard
                usersCard
            }
        }
        .task { await loadAll() }
    }

    private var systemCard: some View {
        GroupBox("System") {
            if let s = sysInfo {
                VStack(spacing: 0) {
                    infoRow("Model", s.model)
                    Divider().padding(.leading, 16)
                    infoRow("Hostname", s.hostname)
                    Divider().padding(.leading, 16)
                    infoRow("OS", s.osRelease)
                    Divider().padding(.leading, 16)
                    infoRow("Kernel", s.kernel)
                    Divider().padding(.leading, 16)
                    infoRow("Architecture", s.architecture)
                    Divider().padding(.leading, 16)
                    infoRow("L4T / JetPack", s.l4tVersion ?? "N/A")
                    Divider().padding(.leading, 16)
                    infoRow("Uptime", s.uptime)
                }
            }
        }
    }

    private var storageCard: some View {
        GroupBox("Storage") {
            if let d = disksInfo {
                VStack(spacing: 0) {
                    ForEach(d.filesystems) { fs in
                        HStack {
                            Text(fs.mount)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(width: 120, alignment: .leading)
                            ProgressView(value: percentValue(fs.percent), total: 100)
                                .tint(percentValue(fs.percent) > 90 ? .red : percentValue(fs.percent) > 70 ? .orange : .blue)
                            Text("\(fs.used)/\(fs.size)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(fs.percent)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .frame(width: 40, alignment: .trailing)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 4)
                    }
                }
                if let swap = swapInfo?.swap {
                    Divider()
                    HStack {
                        Text("Swap").font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(swap.used) / \(swap.total)")
                            .font(.system(size: 12, design: .monospaced))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 4)
                }
            } else {
                Text("No storage data").foregroundStyle(.secondary).font(.system(size: 13)).padding(8)
            }
        }
    }

    private var networkCard: some View {
        GroupBox("Network") {
            if let n = networkInfo {
                VStack(spacing: 0) {
                    ForEach(n.interfaces.filter { $0.state == "UP" || $0.name == "lo" }) { iface in
                        HStack {
                            Circle()
                                .fill(iface.state == "UP" ? Color.green : .gray)
                                .frame(width: 6, height: 6)
                            Text(iface.name)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .frame(width: 80, alignment: .leading)
                            if let addrs = iface.addresses {
                                let ipv4 = addrs.first { $0.family == "inet" }
                                Text(ipv4?.address ?? "—")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let mac = iface.mac, mac != "00:00:00:00:00:00" {
                                Text(mac)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 3)
                    }
                }
            }
        }
    }

    private var usersCard: some View {
        GroupBox("Users") {
            if let u = usersInfo {
                VStack(spacing: 0) {
                    ForEach(u.users) { user in
                        HStack {
                            Image(systemName: "person.fill")
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                            Text(user.name)
                                .font(.system(size: 12, weight: .medium))
                            Text("uid:\(user.uid)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Text(user.shell)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 3)
                    }
                }
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
            Text(value).font(.system(size: 13, design: .monospaced))
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
    }

    private func percentValue(_ s: String) -> Double {
        Double(s.replacingOccurrences(of: "%", with: "")) ?? 0
    }

    private func loadAll() async {
        guard let client = appState.connector?.agentClient(for: deviceID) else { return }
        isLoading = true
        do {
            async let si = client.systemInfo()
            async let di = client.disks()
            async let sw = client.swap()
            async let ni = client.networkInterfaces()
            async let ui = client.users()
            (sysInfo, disksInfo, swapInfo, networkInfo, usersInfo) = try await (si, di, sw, ni, ui)
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }
}
