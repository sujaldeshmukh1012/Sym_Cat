import AVFoundation
import SwiftUI

// MARK: - LiveInspectionView

/// Full-screen view: live camera preview + Gemini voice assistant
/// The inspector talks to Gemini; when Gemini calls `take_photo`,
/// the camera captures a frame and sends it to Modal /inspect.
struct LiveInspectionView: View {
    let onClose: () -> Void
    
    @StateObject private var service = RelayLiveInspectionService()
    @StateObject private var cameraService = LiveCameraService()
    @State private var showTranscript = false
    
    var body: some View {
        ZStack {
            // Camera preview — full screen
            LiveCameraPreview(session: cameraService.session)
                .ignoresSafeArea()
            
            // Gradient overlays for readability
            VStack {
                LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 120)
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 260)
            }
            .ignoresSafeArea()
            
            // UI overlay
            VStack(spacing: 0) {
                topBar
                Spacer()
                statusBanner
                transcriptOverlay
                bottomControls
            }
            .padding(.bottom, 16)
        }
        .onAppear {
            cameraService.start()
            service.cameraDelegate = cameraService
            service.startPassiveListening()
        }
        .onDisappear {
            service.disconnect()
            cameraService.stop()
        }
        .statusBarHidden()
    }
    
    // MARK: - Top bar
    
    private var topBar: some View {
        HStack {
            Button { onClose() } label: {
                Image(systemName: "xmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
            
            Spacer()
            
            VStack(spacing: 2) {
                Text("AI Inspection")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Text(service.equipmentId)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }
            
            Spacer()
            
            // Mute toggle
            Button { service.toggleMute() } label: {
                Image(systemName: service.isMuted ? "mic.slash.fill" : "mic.fill")
                    .font(.title3)
                    .foregroundStyle(service.isMuted ? .red : .white)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
    
    // MARK: - Status banner
    
    private var statusBanner: some View {
        HStack(spacing: 8) {
            statusDot
            Text(service.state.label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.bottom, 8)
    }
    
    @ViewBuilder
    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 10, height: 10)
            .overlay {
                if case .connected = service.state {
                    Circle()
                        .fill(statusColor.opacity(0.4))
                        .frame(width: 20, height: 20)
                        .animation(.easeInOut(duration: 1).repeatForever(), value: service.state)
                }
            }
    }
    
    private var statusColor: Color {
        switch service.state {
        case .idle: return .gray
        case .passiveListening: return .blue
        case .connecting: return .orange
        case .connected: return .green
        case .runningTool: return .yellow
        case .error: return .red
        }
    }
    
    // MARK: - Transcript overlay
    
    private var transcriptOverlay: some View {
        VStack(spacing: 0) {
            if showTranscript {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(service.transcript) { entry in
                                transcriptRow(entry)
                                    .id(entry.id)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .frame(maxHeight: 180)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 16)
                    .onChange(of: service.transcript.count) {
                        if let last = service.transcript.last {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
        .padding(.bottom, 8)
    }
    
    private func transcriptRow(_ entry: TranscriptEntry) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: entryIcon(entry.type))
                .font(.caption2)
                .foregroundStyle(entryColor(entry.type))
                .frame(width: 16)
            
            Text(entry.text)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    private func entryIcon(_ type: TranscriptEntry.EntryType) -> String {
        switch type {
        case .system: return "gear"
        case .user: return "person.fill"
        case .assistant: return "sparkles"
        }
    }
    
    private func entryColor(_ type: TranscriptEntry.EntryType) -> Color {
        switch type {
        case .system: return .yellow
        case .user: return .cyan
        case .assistant: return .green
        }
    }
    
    // MARK: - Bottom controls
    
    private var bottomControls: some View {
        HStack(spacing: 24) {
            // Transcript toggle
            Button {
                withAnimation(.spring(response: 0.3)) {
                    showTranscript.toggle()
                }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "text.bubble.fill")
                        .font(.title2)
                    Text("Log")
                        .font(.caption2)
                }
                .foregroundStyle(.white.opacity(0.8))
            }
            
            // Main action button (connect / disconnect)
            Button {
                switch service.state {
                case .idle, .error:
                    service.startPassiveListening()
                case .passiveListening:
                    service.connect()
                case .connected, .connecting, .runningTool:
                    service.disconnect()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(mainButtonColor)
                        .frame(width: 72, height: 72)
                    
                    if case .connecting = service.state {
                        ProgressView()
                            .tint(.black)
                    } else {
                        Image(systemName: mainButtonIcon)
                            .font(.title.weight(.bold))
                            .foregroundStyle(.black)
                    }
                }
                .shadow(color: mainButtonColor.opacity(0.4), radius: 12)
            }
            
            // Manual photo capture (optional)
            Button {
                Task { await manualCapture() }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "camera.fill")
                        .font(.title2)
                    Text("Photo")
                        .font(.caption2)
                }
                .foregroundStyle(.white.opacity(0.8))
            }
            .disabled(service.state != .connected)
            .opacity(service.state == .connected ? 1 : 0.4)
        }
        .padding(.horizontal, 32)
    }
    
    private var mainButtonColor: Color {
        switch service.state {
        case .idle, .error: return Color(red: 1.0, green: 0.804, blue: 0.067) // CAT Yellow
        case .passiveListening: return .blue
        case .connecting: return .orange
        case .connected: return .red
        case .runningTool: return .yellow
        }
    }
    
    private var mainButtonIcon: String {
        switch service.state {
        case .idle, .error: return "waveform"
        case .passiveListening: return "ear.fill"
        case .connecting: return "antenna.radiowaves.left.and.right"
        case .connected, .runningTool: return "stop.fill"
        }
    }
    
    private func manualCapture() async {
        guard let data = try? await cameraService.capturePhotoData() else { return }
        // Send as a text message to Gemini to trigger tool call
        // In practice the inspector would just say "take a photo"
        print("[LiveView] Manual capture: \(data.count) bytes")
    }
}

// MARK: - LiveCameraService (simplified, returns Data)

@MainActor
final class LiveCameraService: NSObject, ObservableObject, LiveInspectionCameraDelegate, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private var photoContinuation: CheckedContinuation<Data, Error>?
    
    override init() {
        super.init()
        configure()
    }
    
    func start() {
        if !session.isRunning { session.startRunning() }
    }
    
    func stop() {
        if session.isRunning { session.stopRunning() }
    }
    
    /// Async photo capture — returns JPEG Data
    func capturePhotoData() async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            self.photoContinuation = continuation
            let settings = AVCapturePhotoSettings()
            output.capturePhoto(with: settings, delegate: self)
        }
    }
    
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                photoContinuation?.resume(throwing: error)
            } else if let data = photo.fileDataRepresentation() {
                photoContinuation?.resume(returning: data)
            } else {
                photoContinuation?.resume(throwing: InspectionError.noImage)
            }
            photoContinuation = nil
        }
    }
    
    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .photo
        defer { session.commitConfiguration() }
        
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else { return }
        
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(output) { session.addOutput(output) }
    }
}

// MARK: - Camera preview (UIViewRepresentable)

struct LiveCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> LivePreviewUIView {
        let view = LivePreviewUIView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }
    
    func updateUIView(_ uiView: LivePreviewUIView, context: Context) {
        uiView.videoPreviewLayer.session = session
    }
}

final class LivePreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}
