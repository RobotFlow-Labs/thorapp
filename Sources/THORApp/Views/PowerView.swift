import SwiftUI
import THORShared

struct PowerView: View {
    let deviceID: Int64
    @Environment(AppState.self) private var appState
    @State private var powerMode: PowerModeResponse?
    @State private var clocks: PowerClocksResponse?
    @State private var fan: FanStatusResponse?
    @State private var metrics: AgentMetricsResponse?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            headerRow
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.orange).font(.system(size: 12))
            }
            if isLoading && powerMode == nil {
                ProgressView("Loading power info...").frame(maxWidth: .infinity, minHeight: 100)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 16) { powerModeCard; clocksCard; fanCard }
                    VStack(spacing: 16) { thermalCard }
                }
            }
        }
        .task { await loadAll() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                await refreshMetrics()
            }
        }
    }

    private var headerRow: some View {
        HStack {
            Label("Power & Thermal", systemImage: "bolt.fill")
                .font(.system(size: 14, weight: .medium))
            Spacer()
            Button { Task { await loadAll() } } label: {
                Image(systemName: "arrow.clockwise")
            }.buttonStyle(.borderless)
        }
    }

    // MARK: - Power Mode

    private var powerModeCard: some View {
        GroupBox("Power Mode") {
            if let pm = powerMode, let modes = pm.modes {
                VStack(spacing: 8) {
                    ForEach(modes) { mode in
                        Button {
                            Task { await setMode(mode.modeId) }
                        } label: {
                            HStack {
                                Image(systemName: pm.currentMode == mode.modeId ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(pm.currentMode == mode.modeId ? .green : .secondary)
                                Text(mode.name)
                                    .font(.system(size: 13, weight: pm.currentMode == mode.modeId ? .semibold : .regular))
                                Spacer()
                                if let desc = mode.description {
                                    Text(desc)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12).padding(.vertical, 4)
                    }
                }
            } else {
                Text("No power mode data").foregroundStyle(.secondary).font(.system(size: 13)).padding(8)
            }
        }
    }

    // MARK: - Clocks

    private var clocksCard: some View {
        GroupBox("Jetson Clocks") {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(clocks?.enabled == true ? "Clocks Locked" : "Clocks Normal")
                        .font(.system(size: 13, weight: .medium))
                    Text(clocks?.enabled == true ? "All frequencies at maximum" : "Dynamic frequency scaling active")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { clocks?.enabled ?? false },
                    set: { newValue in Task { await toggleClocks(newValue) } }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
            .padding(8)
        }
    }

    // MARK: - Fan

    private var fanCard: some View {
        GroupBox("Fan Control") {
            VStack(spacing: 8) {
                HStack {
                    Text("Speed: \(Int(fan?.speedPercent ?? 0))%")
                        .font(.system(size: 13, design: .monospaced))
                    Spacer()
                    Text("PWM: \(fan?.currentPwm ?? 0)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { Double(fan?.targetPwm ?? 128) },
                        set: { newValue in Task { await setFan(Int(newValue)) } }
                    ),
                    in: 0...255,
                    step: 1
                )
            }
            .padding(8)
        }
    }

    // MARK: - Thermal

    private var thermalCard: some View {
        GroupBox("Thermal") {
            if let m = metrics, !m.temperatures.isEmpty {
                VStack(spacing: 4) {
                    ForEach(Array(m.temperatures.keys.sorted()), id: \.self) { key in
                        let temp = m.temperatures[key] ?? 0
                        HStack {
                            Text(key.components(separatedBy: "/").last ?? key)
                                .font(.system(size: 12))
                                .frame(width: 100, alignment: .leading)
                            ProgressView(value: min(temp, 100), total: 100)
                                .tint(temp > 80 ? .red : temp > 60 ? .orange : .green)
                            Text("\(Int(temp))°C")
                                .font(.system(size: 12, design: .monospaced))
                                .frame(width: 45, alignment: .trailing)
                        }
                    }
                }
                .padding(8)
            } else {
                VStack(spacing: 8) {
                    if let m = metrics {
                        HStack {
                            Text("CPU").font(.system(size: 12))
                            ProgressView(value: m.cpu.percent, total: 100)
                                .tint(m.cpu.percent > 80 ? .red : .blue)
                            Text("\(String(format: "%.0f", m.cpu.percent))%")
                                .font(.system(size: 12, design: .monospaced))
                        }
                        HStack {
                            Text("MEM").font(.system(size: 12))
                            ProgressView(value: m.memory.percent, total: 100)
                                .tint(m.memory.percent > 80 ? .red : .blue)
                            Text("\(String(format: "%.0f", m.memory.percent))%")
                                .font(.system(size: 12, design: .monospaced))
                        }
                    }
                    Text("No thermal sensors detected")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .padding(8)
            }
        }
    }

    // MARK: - Actions

    private func loadAll() async {
        guard let client = appState.connector?.agentClient(for: deviceID) else { return }
        isLoading = true
        do {
            async let pm = client.powerMode()
            async let cl = client.powerClocks()
            async let fn = client.fanStatus()
            async let mt = client.metrics()
            (powerMode, clocks, fan, metrics) = try await (pm, cl, fn, mt)
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }

    private func refreshMetrics() async {
        guard let client = appState.connector?.agentClient(for: deviceID) else { return }
        metrics = try? await client.metrics()
    }

    private func setMode(_ mode: Int) async {
        guard let client = appState.connector?.agentClient(for: deviceID) else { return }
        powerMode = try? await client.setPowerMode(mode)
    }

    private func toggleClocks(_ enable: Bool) async {
        guard let client = appState.connector?.agentClient(for: deviceID) else { return }
        clocks = try? await client.setPowerClocks(enable: enable)
    }

    private func setFan(_ pwm: Int) async {
        guard let client = appState.connector?.agentClient(for: deviceID) else { return }
        fan = try? await client.setFanSpeed(pwm)
    }
}
