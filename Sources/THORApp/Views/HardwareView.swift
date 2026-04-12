import SwiftUI
import THORShared

struct HardwareView: View {
    let deviceID: Int64
    @Environment(AppState.self) private var appState
    @State private var cameras: CameraListResponse?
    @State private var gpioState: GPIOResponse?
    @State private var i2cState: I2CResponse?
    @State private var usbState: USBDevicesResponse?
    @State private var serialState: SerialPortsResponse?
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label("Hardware & Peripherals", systemImage: "cpu")
                    .font(.system(size: 14, weight: .medium))
                Spacer()
                Button("Camera Studio") {
                    appState.openCameraStudio(for: deviceID)
                }
                .buttonStyle(.bordered)
                Button { Task { await loadAll() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
            }

            if isLoading && cameras == nil {
                ProgressView("Scanning hardware...").frame(maxWidth: .infinity, minHeight: 100)
            } else {
                camerasCard
                gpioCard
                i2cCard
                usbCard
                serialCard
            }
        }
        .task { await loadAll() }
    }

    private var camerasCard: some View {
        GroupBox("Cameras (\(cameras?.count ?? 0))") {
            if let cams = cameras, !cams.cameras.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(cams.cameras) { cam in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: cam.type == "ZED" ? "video.fill" : cam.type == "CSI" ? "camera.fill" : "web.camera")
                                    .foregroundStyle(cam.type == "ZED" ? .purple : cam.type == "CSI" ? .blue : .green)
                                    .frame(width: 16)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(cam.name).font(.system(size: 12, weight: .medium))
                                    Text(cam.device)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    if let details = cam.details, !details.isEmpty {
                                        Text(details)
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                HStack(spacing: 6) {
                                    cameraBadge(cam.type, color: badgeColor(for: cam.type))
                                    if cam.isBridged {
                                        cameraBadge(cam.source?.uppercased() ?? "BRIDGE", color: .orange)
                                    }
                                    if let bridgeState = cam.bridgeState {
                                        cameraBadge(bridgeState.uppercased(), color: .pink)
                                    }
                                    if let width = cam.width, let height = cam.height {
                                        cameraBadge("\(width)×\(height)", color: .secondary)
                                    }
                                }
                            }

                            if cam.isBridged {
                                BridgedCameraSnapshotView(deviceID: deviceID, camera: cam)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.secondarySystemFill).opacity(0.25))
                        .clipShape(.rect(cornerRadius: 10))
                    }
                }
            } else {
                Text("No cameras detected").foregroundStyle(.secondary).font(.system(size: 13)).padding(8)
            }
        }
    }

    private var gpioCard: some View {
        GroupBox("GPIO Pins (\(gpioState?.count ?? 0))") {
            if let gpio = gpioState, !gpio.pins.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 70))], spacing: 4) {
                    ForEach(gpio.pins) { pin in
                        VStack(spacing: 2) {
                            Text("GPIO\(pin.number)")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                            Circle()
                                .fill(pin.value == 1 ? Color.green : Color.gray.opacity(0.3))
                                .frame(width: 12, height: 12)
                            Text(pin.direction)
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .padding(4)
                        .background(Color(.secondarySystemFill).opacity(0.3))
                        .clipShape(.rect(cornerRadius: 6))
                    }
                }
                .padding(8)
            } else {
                Text("No GPIO pins exported").foregroundStyle(.secondary).font(.system(size: 13)).padding(8)
            }
        }
    }

    private var i2cCard: some View {
        GroupBox("I2C Buses (\(i2cState?.buses.count ?? 0))") {
            if let i2c = i2cState, !i2c.buses.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(i2c.buses) { bus in
                        HStack {
                            Text("Bus \(bus.bus)")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                            Text("—")
                            ForEach(bus.devices, id: \.address) { dev in
                                Text(dev.address)
                                    .font(.system(size: 10, design: .monospaced))
                                    .padding(.horizontal, 4).padding(.vertical, 1)
                                    .background(dev.status == "in_use" ? Color.orange.opacity(0.2) : Color.green.opacity(0.2))
                                    .clipShape(.rect(cornerRadius: 3))
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12).padding(.vertical, 2)
                    }
                }
            } else {
                Text("No I2C buses found").foregroundStyle(.secondary).font(.system(size: 13)).padding(8)
            }
        }
    }

    private var usbCard: some View {
        GroupBox("USB Devices (\(usbState?.count ?? 0))") {
            if let usb = usbState, !usb.devices.isEmpty {
                VStack(spacing: 0) {
                    ForEach(usb.devices) { dev in
                        HStack {
                            Text(dev.vendorProduct)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(width: 80, alignment: .leading)
                            Text(dev.description).font(.system(size: 11)).lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 12).padding(.vertical, 3)
                    }
                }
            } else {
                Text("No USB devices").foregroundStyle(.secondary).font(.system(size: 13)).padding(8)
            }
        }
    }

    private var serialCard: some View {
        GroupBox("Serial Ports (\(serialState?.count ?? 0))") {
            if let serial = serialState, !serial.ports.isEmpty {
                VStack(spacing: 0) {
                    ForEach(serial.ports) { port in
                        HStack {
                            Image(systemName: "cable.connector").foregroundStyle(.secondary).font(.system(size: 10))
                            Text(port.path).font(.system(size: 12, design: .monospaced))
                            Spacer()
                            Text(port.type).font(.system(size: 10)).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 3)
                    }
                }
            } else {
                Text("No serial ports").foregroundStyle(.secondary).font(.system(size: 13)).padding(8)
            }
        }
    }

    private func loadAll() async {
        guard let client = appState.connector?.agentClient(for: deviceID) else { return }
        isLoading = true
        do {
            async let c = client.cameras()
            async let g = client.gpio()
            async let i = client.i2cScan()
            async let u = client.usbDevices()
            async let s = client.serialPorts()
            (cameras, gpioState, i2cState, usbState, serialState) = try await (c, g, i, u, s)
        } catch {}
        isLoading = false
    }

    private func badgeColor(for cameraType: String) -> Color {
        switch cameraType {
        case "CSI":
            .blue
        case "ZED":
            .purple
        case "USB":
            .green
        default:
            .secondary
        }
    }

    private func cameraBadge(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .clipShape(.rect(cornerRadius: 4))
    }
}

private struct BridgedCameraSnapshotView: View {
    let deviceID: Int64
    let camera: CameraDevice

    @Environment(AppState.self) private var appState
    @State private var image: NSImage?
    @State private var snapshotUnavailable = false

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, minHeight: 150, maxHeight: 180)
                    .background(Color.black.opacity(0.85))
                    .clipShape(.rect(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.secondarySystemFill))
                    .frame(maxWidth: .infinity, minHeight: 150, maxHeight: 180)
                    .overlay {
                        VStack(spacing: 6) {
                            Image(systemName: snapshotUnavailable ? "wifi.exclamationmark" : "photo.badge.arrow.down")
                                .font(.system(size: 20))
                                .foregroundStyle(.secondary)
                            Text(snapshotUnavailable ? "Waiting for live snapshot" : "Loading bridged snapshot")
                                .font(.system(size: 11, weight: .medium))
                            if let lastFrameAt = camera.lastFrameAt {
                                Text(lastFrameAt)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
            }
        }
        .task(id: "\(deviceID)-\(camera.device)") {
            await pollSnapshot()
        }
    }

    private func pollSnapshot() async {
        guard camera.isBridged,
              let client = appState.connector?.agentClient(for: deviceID) else {
            return
        }

        while !Task.isCancelled {
            do {
                let data = try await client.cameraSnapshot(cameraID: camera.rawCameraID)
                image = NSImage(data: data)
                snapshotUnavailable = image == nil
            } catch {
                snapshotUnavailable = true
            }

            try? await Task.sleep(for: .milliseconds(900))
        }
    }
}

private extension CameraDevice {
    var isBridged: Bool {
        source == "bridge" || device.hasPrefix("bridge:")
    }

    var rawCameraID: String {
        if device.hasPrefix("bridge:") {
            return String(device.dropFirst("bridge:".count))
        }
        return device
    }
}
