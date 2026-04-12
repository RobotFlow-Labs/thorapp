import AppKit
import CoreImage
@preconcurrency import AVFoundation
import THORShared

struct LocalCameraSource: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let modelID: String
    let transportSummary: String

    var cameraType: String {
        let lowered = "\(name) \(modelID)".lowercased()
        return lowered.contains("zed") ? "ZED" : "USB"
    }
}

private struct BridgeFramePayload: Sendable {
    let jpegData: Data
    let width: Int
    let height: Int
    let fps: Double?
}

private actor CameraFrameBuffer {
    private var latestPayload: BridgeFramePayload?
    private var lastPresentationTime: Double?

    func store(jpegData: Data, width: Int, height: Int, presentationTime: Double?) {
        var fps: Double?

        if let presentationTime, presentationTime.isFinite {
            if let lastPresentationTime, presentationTime > lastPresentationTime {
                fps = 1.0 / (presentationTime - lastPresentationTime)
            }
            lastPresentationTime = presentationTime
        }

        latestPayload = BridgeFramePayload(
            jpegData: jpegData,
            width: width,
            height: height,
            fps: fps
        )
    }

    func currentPayload() -> BridgeFramePayload? {
        latestPayload
    }
}

private final class CameraSampleProcessor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let ciContext = CIContext()
    private let frameBuffer: CameraFrameBuffer

    init(frameBuffer: CameraFrameBuffer) {
        self.frameBuffer = frameBuffer
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let sourceWidth = CVPixelBufferGetWidth(pixelBuffer)
        let scale = min(1.0, 960.0 / max(Double(sourceWidth), 1.0))
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let jpegData = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.72]) else { return }

        let presentationTime = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        let normalizedPresentationTime = presentationTime.isFinite ? presentationTime : nil
        let frameBuffer = self.frameBuffer

        Task {
            await frameBuffer.store(
                jpegData: jpegData,
                width: Int(ciImage.extent.width),
                height: Int(ciImage.extent.height),
                presentationTime: normalizedPresentationTime
            )
        }
    }
}

@MainActor
final class CameraBridgeService: NSObject, ObservableObject {
    @Published var authorizationStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @Published var cameras: [LocalCameraSource] = []
    @Published var selectedCameraID: String?
    @Published var isPreviewRunning = false
    @Published var isBridging = false
    @Published var bridgeMessage = "Camera bridge idle"
    @Published var frameSummary = "No frames yet"
    @Published var measuredFPS: Double = 0
    @Published var remoteSnapshotImage: NSImage?

    let captureSession = AVCaptureSession()

    private let frameBuffer = CameraFrameBuffer()
    private let videoQueue = DispatchQueue(label: "com.robotflowlabs.thor.camera.bridge")
    private let videoOutput = AVCaptureVideoDataOutput()
    private lazy var sampleProcessor = CameraSampleProcessor(frameBuffer: frameBuffer)

    private var currentInput: AVCaptureDeviceInput?
    private var bridgeTask: Task<Void, Never>?
    private var previewMonitorTask: Task<Void, Never>?
    private var activeBridgeClient: AgentClient?
    private var activeBridgeCameraID: String?

    override init() {
        super.init()
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.setSampleBufferDelegate(sampleProcessor, queue: videoQueue)
        refreshAvailableCameras()
    }

    deinit {
        bridgeTask?.cancel()
        previewMonitorTask?.cancel()
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
    }

    var selectedCamera: LocalCameraSource? {
        cameras.first { $0.id == selectedCameraID }
    }

    func refreshAvailableCameras() {
        let discovered = availableVideoDevices()
            .map {
                LocalCameraSource(
                    id: $0.uniqueID,
                    name: $0.localizedName,
                    modelID: $0.modelID,
                    transportSummary: $0.manufacturer
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        cameras = discovered
        if selectedCameraID == nil || !discovered.contains(where: { $0.id == selectedCameraID }) {
            selectedCameraID = discovered.first?.id
        }
    }

    func ensureCameraAccess() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        authorizationStatus = status

        guard status == .notDetermined else { return }

        let granted = await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .video) { continuation.resume(returning: $0) }
        }

        authorizationStatus = granted ? .authorized : .denied
        bridgeMessage = granted ? "Camera access granted" : "Camera access denied"
    }

    func requestCameraAccess() {
        Task { await ensureCameraAccess() }
    }

    func startPreview() {
        guard let source = selectedCamera else {
            bridgeMessage = "Select a camera first"
            return
        }

        do {
            try configureSession(for: source)
            if !captureSession.isRunning {
                captureSession.startRunning()
            }
            isPreviewRunning = true
            frameSummary = "Waiting for first frame..."
            measuredFPS = 0
            bridgeMessage = "Previewing \(source.name)"
            startPreviewMonitor()
        } catch {
            bridgeMessage = "Preview failed: \(error.localizedDescription)"
        }
    }

    func stopPreview() {
        bridgeTask?.cancel()
        bridgeTask = nil
        previewMonitorTask?.cancel()
        previewMonitorTask = nil

        if captureSession.isRunning {
            captureSession.stopRunning()
        }

        isPreviewRunning = false
        isBridging = false
        frameSummary = "No frames yet"
        measuredFPS = 0
        remoteSnapshotImage = nil
    }

    func startBridge(to client: AgentClient, targetName: String) {
        guard let source = selectedCamera else {
            bridgeMessage = "Select a camera first"
            return
        }

        if !captureSession.isRunning {
            startPreview()
        }

        activeBridgeClient = client
        activeBridgeCameraID = source.id
        remoteSnapshotImage = nil
        bridgeTask?.cancel()
        isBridging = true
        bridgeMessage = "Bridging \(source.name) to \(targetName)..."

        let frameBuffer = self.frameBuffer
        bridgeTask = Task {
            while !Task.isCancelled {
                guard let payload = await frameBuffer.currentPayload() else {
                    try? await Task.sleep(for: .milliseconds(350))
                    continue
                }

                do {
                    _ = try await client.cameraBridgeFrame(
                        cameraID: source.id,
                        name: source.name,
                        type: source.cameraType,
                        width: payload.width,
                        height: payload.height,
                        fps: payload.fps,
                        jpegData: payload.jpegData
                    )

                    let snapshot = try? await client.cameraSnapshot(cameraID: source.id)
                    remoteSnapshotImage = snapshot.flatMap(NSImage.init(data:))
                    frameSummary = "\(payload.width)×\(payload.height) JPEG"
                    if let fps = payload.fps, fps.isFinite {
                        measuredFPS = fps
                    }
                    bridgeMessage = "Bridging \(source.name) to \(targetName)"
                } catch {
                    bridgeMessage = "Bridge error: \(error.localizedDescription)"
                }

                try? await Task.sleep(for: .milliseconds(650))
            }
        }
    }

    func stopBridge() {
        bridgeTask?.cancel()
        bridgeTask = nil
        isBridging = false

        let activeBridgeClient = activeBridgeClient
        let activeBridgeCameraID = activeBridgeCameraID
        self.activeBridgeClient = nil
        self.activeBridgeCameraID = nil

        bridgeMessage = "Camera bridge idle"
        remoteSnapshotImage = nil

        if let activeBridgeClient, let activeBridgeCameraID {
            Task {
                try? await activeBridgeClient.removeCameraBridge(cameraID: activeBridgeCameraID)
            }
        }
    }

    private func startPreviewMonitor() {
        previewMonitorTask?.cancel()
        let frameBuffer = self.frameBuffer

        previewMonitorTask = Task {
            while !Task.isCancelled {
                if let payload = await frameBuffer.currentPayload() {
                    frameSummary = "\(payload.width)×\(payload.height) JPEG"
                    if let fps = payload.fps, fps.isFinite {
                        measuredFPS = fps
                    }
                }

                try? await Task.sleep(for: .milliseconds(300))
            }
        }
    }

    private func configureSession(for source: LocalCameraSource) throws {
        guard let device = availableVideoDevices().first(where: { $0.uniqueID == source.id }) else {
            throw NSError(
                domain: "CameraBridgeService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Selected camera is no longer available"]
            )
        }

        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        captureSession.sessionPreset = .high

        if let currentInput {
            captureSession.removeInput(currentInput)
        }

        let input = try AVCaptureDeviceInput(device: device)
        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
            currentInput = input
        }

        if !captureSession.outputs.contains(videoOutput), captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }

        if let connection = videoOutput.connection(with: .video), connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
    }

    private func availableVideoDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        ).devices
    }
}
