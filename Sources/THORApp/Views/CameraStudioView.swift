import AppKit
import SwiftUI
import THORShared
@preconcurrency import AVFoundation

struct CameraStudioView: View {
    @Environment(AppState.self) private var appState
    @ObservedObject private var bridge: CameraBridgeService
    @State private var selectedTargetDeviceID: Int64?

    init(bridge: CameraBridgeService) {
        _bridge = ObservedObject(wrappedValue: bridge)
    }

    private var connectedDevices: [Device] {
        appState.devices.filter {
            guard let id = $0.id else { return false }
            return appState.connectionStatus(for: id) == .connected
        }
    }

    private var selectedTargetDevice: Device? {
        connectedDevices.first { $0.id == selectedTargetDeviceID }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if bridge.authorizationStatus == .denied || bridge.authorizationStatus == .restricted {
                    permissionCard
                } else {
                    previewGrid
                    controlsCard
                }
            }
            .padding(20)
        }
        .task {
            await bridge.ensureCameraAccess()
            bridge.refreshAvailableCameras()
            syncSelectedTarget(prefer: appState.cameraStudioTargetDeviceID ?? appState.selectedDevice?.id)
        }
        .onChange(of: appState.cameraStudioTargetDeviceID) { _, newValue in
            syncSelectedTarget(prefer: newValue)
        }
        .onChange(of: selectedTargetDeviceID) { _, newValue in
            appState.cameraStudioTargetDeviceID = newValue
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Camera Studio")
                .font(.system(size: 28, weight: .bold))
            Text("Preview a camera attached to this Mac, then bridge it into a connected THOR sim so the agent reports a real live source.")
                .foregroundStyle(.secondary)
                .font(.system(size: 13))
        }
    }

    private var previewGrid: some View {
        HStack(alignment: .top, spacing: 20) {
            GroupBox("Local Camera") {
                VStack(alignment: .leading, spacing: 12) {
                    LocalCameraPreview(session: bridge.captureSession)
                        .frame(minHeight: 280)
                        .overlay(alignment: .bottomLeading) {
                            cameraOverlay(title: bridge.selectedCamera?.name ?? "No camera selected",
                                          subtitle: bridge.frameSummary)
                        }
                        .clipShape(.rect(cornerRadius: 12))

                    HStack {
                        statBadge("FPS", value: bridge.measuredFPS > 0 ? String(format: "%.1f", bridge.measuredFPS) : "—")
                        statBadge("Source", value: bridge.selectedCamera?.cameraType ?? "—")
                        statBadge("Status", value: bridge.isPreviewRunning ? "Live" : "Idle")
                        Spacer()
                    }
                }
            }

            GroupBox("THOR Sim View") {
                VStack(alignment: .leading, spacing: 12) {
                    if let image = bridge.remoteSnapshotImage {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, minHeight: 280)
                            .background(Color.black.opacity(0.8))
                            .overlay(alignment: .bottomLeading) {
                                cameraOverlay(title: selectedTargetDevice?.displayName ?? "THOR Sim",
                                              subtitle: "Snapshot served by the agent bridge")
                            }
                            .clipShape(.rect(cornerRadius: 12))
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.secondarySystemFill))
                            .frame(maxWidth: .infinity, minHeight: 280)
                            .overlay {
                                VStack(spacing: 8) {
                                    Image(systemName: "video.slash")
                                        .font(.system(size: 28))
                                        .foregroundStyle(.secondary)
                                    Text("No bridged snapshot yet")
                                        .font(.system(size: 13, weight: .medium))
                                    Text("Start the bridge, then open the target device’s Hardware panel to verify the sim sees the camera.")
                                        .foregroundStyle(.secondary)
                                        .font(.system(size: 12))
                                        .multilineTextAlignment(.center)
                                        .frame(maxWidth: 260)
                                }
                            }
                    }

                    HStack {
                        statBadge("Bridge", value: bridge.isBridging ? "Active" : "Stopped")
                        statBadge("Target", value: selectedTargetDevice?.displayName ?? "None")
                        Spacer()
                    }
                }
            }
        }
    }

    private var controlsCard: some View {
        GroupBox("Bridge Controls") {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Host Camera")
                            .font(.system(size: 12, weight: .semibold))
                        Picker("Host Camera", selection: $bridge.selectedCameraID) {
                            ForEach(bridge.cameras) { camera in
                                Text(camera.name).tag(Optional(camera.id))
                            }
                        }
                        .labelsHidden()
                        .frame(width: 260)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("THOR Target")
                            .font(.system(size: 12, weight: .semibold))
                        Picker("THOR Target", selection: $selectedTargetDeviceID) {
                            ForEach(connectedDevices) { device in
                                Text(device.displayName).tag(Optional(device.id ?? 0))
                            }
                        }
                        .labelsHidden()
                        .frame(width: 240)
                    }

                    Spacer()
                }

                HStack(spacing: 12) {
                    Button(bridge.isPreviewRunning ? "Restart Preview" : "Start Preview") {
                        bridge.startPreview()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Stop Preview") {
                        bridge.stopPreview()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!bridge.isPreviewRunning)

                    Button(bridge.isBridging ? "Restart Bridge" : "Bridge To THOR") {
                        guard let device = selectedTargetDevice,
                              let deviceID = device.id,
                              let client = appState.connector?.agentClient(for: deviceID) else { return }
                        bridge.startBridge(to: client, targetName: device.displayName)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedTargetDevice == nil || bridge.selectedCamera == nil)

                    Button("Stop Bridge") {
                        bridge.stopBridge()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!bridge.isBridging)
                }

                Text(bridge.bridgeMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Button("Show On Thor Hardware") {
                    appState.showDeviceHardware(deviceID: selectedTargetDeviceID)
                }
                .buttonStyle(.bordered)
                .disabled(selectedTargetDeviceID == nil)

                Text("Demo flow: start preview, bridge to a connected sim, then open the target device’s Hardware tab. The bridged ZED will appear in the agent-backed camera list with live snapshots.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .onChange(of: bridge.selectedCameraID) { _, _ in
                bridge.stopPreview()
                bridge.startPreview()
            }
        }
    }

    private var permissionCard: some View {
        GroupBox("Camera Permission Required") {
            VStack(alignment: .leading, spacing: 12) {
                Text("THOR needs camera access on macOS to preview and bridge the ZED 2i.")
                    .font(.system(size: 13))
                HStack(spacing: 12) {
                    Button("Request Access") {
                        bridge.requestCameraAccess()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Open Privacy Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func statBadge(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemFill))
        .clipShape(.rect(cornerRadius: 8))
    }

    private func cameraOverlay(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(.rect(cornerRadius: 10))
        .padding(12)
    }

    private func syncSelectedTarget(prefer preferredDeviceID: Int64?) {
        if let preferredDeviceID,
           connectedDevices.contains(where: { $0.id == preferredDeviceID }) {
            selectedTargetDeviceID = preferredDeviceID
        } else if let selectedTargetDeviceID,
                  connectedDevices.contains(where: { $0.id == selectedTargetDeviceID }) {
            return
        } else {
            selectedTargetDeviceID = connectedDevices.first?.id
        }
    }
}

private struct LocalCameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewContainerView {
        let view = PreviewContainerView()
        view.previewLayer.session = session
        return view
    }

    func updateNSView(_ nsView: PreviewContainerView, context: Context) {
        nsView.previewLayer.session = session
    }
}

private final class PreviewContainerView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = AVCaptureVideoPreviewLayer()
        previewLayer.videoGravity = .resizeAspectFill
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}
