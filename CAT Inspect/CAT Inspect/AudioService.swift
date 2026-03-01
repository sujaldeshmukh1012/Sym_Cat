// AudioService.swift
// Gemini Live API — streams raw PCM audio to/from Gemini.
// Architecture mirrors the working Python backend (test_live.py):
//   Mic → 16 kHz PCM → base64 → realtimeInput → Gemini
//   Gemini → 24 kHz PCM → AVAudioPlayerNode → speaker

import Foundation
import UIKit
import AVFoundation
import Speech

// MARK: - Gemini Live Service

@MainActor
final class AudioModalCaller: NSObject, ObservableObject {

    // ── Public state ─────────────────────────────────────────────────────────
    @Published var isRecording       = false
    @Published var isLiveListening   = false
    @Published var isImageProcessing = false

    // ── Commands (same enum as before) ───────────────────────────────────────
    enum LiveVoiceCommand {
        case capturePhoto
        case assistantText(String)
        case userText(String)
        case imageFeedback(String)
    }

    // ── Config ───────────────────────────────────────────────────────────────
    private let apiKey: String = {
        let key = ProcessInfo.processInfo.environment["GEMINI_API_KEY"] ?? ""
        if key.isEmpty {
            print("[GeminiLive] ⚠️ GEMINI_API_KEY not set in scheme environment variables")
        }
        return key
    }()
    private let model = "gemini-2.5-flash-native-audio-preview-12-2025"

    private var wsEndpoint: URL {
        URL(string:
            "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=\(apiKey)"
        )!
    }

    // ── WebSocket ────────────────────────────────────────────────────────────
    private var websocketTask: URLSessionWebSocketTask?
    private var setupAcknowledged = false
    private lazy var wsSession: URLSession = {
        URLSession(
            configuration: .default,
            delegate: WebSocketDelegate(),
            delegateQueue: .main
        )
    }()

    // ── Audio engine (single engine for mic + speaker) ───────────────────────
    private let audioEngine  = AVAudioEngine()
    private let playerNode   = AVAudioPlayerNode()
    private var pcmConverter: AVAudioConverter?
    private let sendFormat   = AVAudioFormat(
        commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true
    )!
    private let recvFormat   = AVAudioFormat(
        commonFormat: .pcmFormatInt16, sampleRate: 24000, channels: 1, interleaved: true
    )!

    // ── Playback state (mute mic while Gemini speaks) ────────────────────────
    private var isPlayingAudio = false
    private var scheduledBufferCount = 0
    private var geminiTurnComplete = true
    private var playbackEndWorkItem: DispatchWorkItem?

    // ── STT for UI transcript display only (not sent to Gemini) ──────────────
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    // ── Session context ──────────────────────────────────────────────────────
    private var taskContextTitle       = ""
    private var taskContextDescription = ""
    private var sessionInspectionID: UUID?
    private var sessionTaskID: UUID?
    private var liveSessionKey: String?
    private var commandHandler: ((LiveVoiceCommand) -> Void)?

    // ── Recording (backward compat for stopAndStream) ────────────────────────
    private var recorder: AVAudioRecorder?
    private var currentFileName: String?

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Init
    // ─────────────────────────────────────────────────────────────────────────

    override init() {
        super.init()
        audioEngine.attach(playerNode)
        print("[GeminiLive] AudioModalCaller initialized")
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Public API
    // ─────────────────────────────────────────────────────────────────────────

    func startLiveListening(
        inspectionID: UUID,
        taskID: UUID,
        taskTitle: String,
        taskDescription: String,
        onCommand: @escaping (LiveVoiceCommand) -> Void
    ) {
        let key = "\(inspectionID.uuidString)-\(taskID.uuidString)"
        if liveSessionKey == key, isLiveListening { return }

        stopLiveListening()
        liveSessionKey         = key
        commandHandler         = onCommand
        taskContextTitle       = taskTitle
        taskContextDescription = taskDescription
        sessionInspectionID    = inspectionID
        sessionTaskID          = taskID

        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            guard let self, granted else {
                DispatchQueue.main.async {
                    onCommand(.assistantText("Microphone permission required."))
                }
                return
            }
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                guard let self else { return }
                Task { @MainActor in
                    // Speech auth is optional — we only use it for UI transcript
                    if status != .authorized {
                        print("[GeminiLive] Speech auth not granted — transcript display disabled")
                    }
                    guard self.configureAudioSession() else { return }
                    self.connectWebSocket(inspectionID: inspectionID, taskID: taskID)
                }
            }
        }
    }

    func stopLiveListening() {
        print("[GeminiLive] stopLiveListening")
        // STT
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil

        // Audio engine
        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            playerNode.stop()
            audioEngine.stop()
        }

        // WebSocket
        websocketTask?.cancel(with: .goingAway, reason: nil)
        websocketTask = nil
        setupAcknowledged = false

        // Reset state
        isPlayingAudio = false
        playbackEndWorkItem?.cancel()
        playbackEndWorkItem = nil
        isImageProcessing = false
        isLiveListening = false
        liveSessionKey = nil
        taskContextTitle = ""
        taskContextDescription = ""
    }

    /// Backward compat
    func startRecording(inspectionID: UUID, taskID: UUID) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try? session.setActive(true, options: .notifyOthersOnDeactivation)
        session.requestRecordPermission { [weak self] granted in
            guard granted, let self else { return }
            Task { @MainActor in self.beginFileRecording(inspectionID: inspectionID, taskID: taskID) }
        }
    }

    func stopRecording() {
        recorder?.stop()
        isRecording = false
    }

    func stopAndStream(
        inspectionID: UUID, taskID: UUID,
        feedbackText: String, photoFileName: String?
    ) async -> String? {
        if isRecording { stopRecording() }
        return currentFileName
    }

    /// Send a captured image to Gemini via the live WebSocket
    func sendCapturedImageToWebSocket(fileName: String, note: String) {
        guard isLiveListening, websocketTask != nil, !isImageProcessing else { return }
        isImageProcessing = true

        let imageURL = storageDir().appendingPathComponent(fileName)
        Task.detached(priority: .utility) {
            guard let base64 = Self.prepareImageBase64(imageURL: imageURL) else {
                await MainActor.run { self.isImageProcessing = false }
                return
            }
            let payload: [String: Any] = [
                "clientContent": [
                    "turns": [[
                        "role": "user",
                        "parts": [
                            ["text": note],
                            ["inlineData": ["mimeType": "image/jpeg", "data": base64]]
                        ]
                    ]],
                    "turnComplete": true
                ]
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: payload),
                  let str  = String(data: data, encoding: .utf8) else {
                await MainActor.run { self.isImageProcessing = false }
                return
            }
            await MainActor.run { self.enqueueWSSend(str) }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Audio session (configured ONCE)
    // ─────────────────────────────────────────────────────────────────────────

    private func configureAudioSession() -> Bool {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord, mode: .voiceChat,
                options: [.defaultToSpeaker, .allowBluetooth]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            print("[GeminiLive] ✅ Audio session configured")
            return true
        } catch {
            print("[GeminiLive] ❌ Audio session error: \(error)")
            commandHandler?(.assistantText("Audio session error: \(error.localizedDescription)"))
            return false
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Audio pipeline — mic capture + PCM playback
    // ─────────────────────────────────────────────────────────────────────────

    private func startAudioPipeline() {
        let inputNode = audioEngine.inputNode
        let hwFormat  = inputNode.outputFormat(forBus: 0)
        print("[GeminiLive] Mic hardware format: \(hwFormat)")

        // Converter: hardware format → 16 kHz mono Int16 for Gemini
        pcmConverter = AVAudioConverter(from: hwFormat, to: sendFormat)

        // Connect player node (Gemini output) to mixer for speaker playback
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: recvFormat)

        // STT request (for UI transcript only)
        let sttRequest = SFSpeechAudioBufferRecognitionRequest()
        sttRequest.shouldReportPartialResults = true
        sttRequest.taskHint = .dictation
        recognitionRequest = sttRequest

        // Install mic tap
        inputNode.removeTap(onBus: 0)

        let converter = pcmConverter!
        let targetFormat = sendFormat

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] buffer, _ in
            guard let self, buffer.frameLength > 0 else { return }

            // Feed STT for display
            sttRequest.append(buffer)

            // Skip sending audio while Gemini is speaking (echo suppression)
            guard !self.isPlayingAudio else { return }
            guard self.setupAcknowledged else { return }

            // Convert to 16 kHz Int16
            let ratio = 16000.0 / buffer.format.sampleRate
            let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
            guard frameCount > 0,
                  let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else { return }

            var error: NSError?
            var consumed = false
            converter.convert(to: converted, error: &error) { _, outStatus in
                if consumed { outStatus.pointee = .noDataNow; return nil }
                consumed = true
                outStatus.pointee = .haveData
                return buffer
            }
            guard error == nil, converted.frameLength > 0 else { return }

            // Raw Int16 bytes → base64
            let byteCount = Int(converted.frameLength) * 2
            let pcmData = Data(bytes: converted.int16ChannelData![0], count: byteCount)
            let base64 = pcmData.base64EncodedString()

            let payload: [String: Any] = [
                "realtimeInput": [
                    "mediaChunks": [
                        ["mimeType": "audio/pcm;rate=16000", "data": base64]
                    ]
                ]
            ]
            guard let json = try? JSONSerialization.data(withJSONObject: payload),
                  let str  = String(data: json, encoding: .utf8) else { return }

            DispatchQueue.main.async { [weak self] in
                self?.enqueueWSSend(str)
            }
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            playerNode.play()
            print("[GeminiLive] ✅ Audio engine started (mic + speaker)")
        } catch {
            print("[GeminiLive] ❌ Audio engine failed: \(error)")
        }

        // Start STT recognition task (for UI only)
        recognitionTask = speechRecognizer?.recognitionTask(with: sttRequest) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    self.commandHandler?(.userText(String(text.suffix(120))))
                }
            }
            if let error {
                print("[GeminiLive] STT error (non-fatal): \(error.localizedDescription)")
            }
        }
    }

    /// Decode Gemini's 24 kHz PCM audio and schedule on playerNode
    private func playGeminiAudio(_ base64Data: String) {
        guard let rawData = Data(base64Encoded: base64Data) else { return }
        let frameCount = UInt32(rawData.count / 2) // 16-bit = 2 bytes per sample
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: recvFormat, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount

        rawData.withUnsafeBytes { src in
            guard let baseAddr = src.baseAddress else { return }
            memcpy(buffer.int16ChannelData![0], baseAddr, rawData.count)
        }

        // Mute mic immediately, track how many buffers are in-flight
        isPlayingAudio = true
        scheduledBufferCount += 1
        playbackEndWorkItem?.cancel()

        playerNode.scheduleBuffer(buffer) { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.scheduledBufferCount = max(0, self.scheduledBufferCount - 1)
                self.scheduleUnmuteIfReady()
            }
        }
    }

    /// Only unmute mic after ALL buffers are done AND Gemini's turn is complete
    /// AND a cooldown period has passed (to let room reverb die out).
    private func scheduleUnmuteIfReady() {
        playbackEndWorkItem?.cancel()

        // Don't unmute yet if buffers are still playing or Gemini is still sending
        guard scheduledBufferCount == 0, geminiTurnComplete else { return }

        // 0.9s cooldown after last audio finishes — prevents echo pickup
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Double-check nothing new was scheduled during the cooldown
            if self.scheduledBufferCount == 0 && self.geminiTurnComplete {
                self.isPlayingAudio = false
            }
        }
        playbackEndWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: workItem)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: WebSocket — connect, send, receive
    // ─────────────────────────────────────────────────────────────────────────

    private func connectWebSocket(inspectionID: UUID, taskID: UUID) {
        print("[GeminiLive] Connecting WebSocket...")
        websocketTask = wsSession.webSocketTask(with: wsEndpoint)
        websocketTask?.resume()

        let systemText = """
        You are an AI assistant helping a Caterpillar field inspector complete an equipment inspection.
        Current task: \(taskContextTitle).
        Task description: \(taskContextDescription).
        Be concise. If you need a photo taken, say "[capture_photo]".
        Inspection ID: \(inspectionID.uuidString). Task ID: \(taskID.uuidString).
        """

        let setupMessage: [String: Any] = [
            "setup": [
                "model": "models/\(model)",
                "generationConfig": [
                    "responseModalities": ["AUDIO"],
                    "speechConfig": [
                        "voiceConfig": [
                            "prebuiltVoiceConfig": ["voiceName": "Charon"]
                        ]
                    ]
                ],
                "systemInstruction": [
                    "parts": [["text": systemText]]
                ]
            ]
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: setupMessage),
              let str  = String(data: data, encoding: .utf8) else { return }

        print("[GeminiLive] Sending setup (\(str.count) chars)")
        websocketTask?.send(.string(str)) { [weak self] error in
            if let error {
                print("[GeminiLive] ❌ Setup send failed: \(error)")
                DispatchQueue.main.async {
                    self?.commandHandler?(.assistantText("Connection failed: \(error.localizedDescription)"))
                }
            } else {
                print("[GeminiLive] ✅ Setup sent, waiting for setupComplete...")
            }
        }
        receiveMessages()
    }

    private func receiveMessages() {
        websocketTask?.receive { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                switch result {
                case .failure(let error):
                    print("[GeminiLive] ❌ WS receive error: \(error)")
                    self.commandHandler?(.assistantText("Connection dropped."))
                case .success(let msg):
                    let raw: String?
                    switch msg {
                    case .string(let s): raw = s
                    case .data(let d):   raw = String(data: d, encoding: .utf8)
                    @unknown default:    raw = nil
                    }
                    if let raw { self.handleServerMessage(raw) }
                    self.receiveMessages()
                }
            }
        }
    }

    private func handleServerMessage(_ raw: String) {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        // setupComplete → start audio pipeline
        if json["setupComplete"] != nil {
            print("[GeminiLive] ✅ setupComplete — starting audio pipeline")
            setupAcknowledged = true
            isLiveListening = true
            startAudioPipeline()
            commandHandler?(.assistantText("AI ready. Speak now."))
            return
        }

        // serverContent
        if let content = json["serverContent"] as? [String: Any] {
            isImageProcessing = false

            // Audio from Gemini — mark turn as in-progress (mic stays muted)
            if let turn = content["modelTurn"] as? [String: Any],
               let parts = turn["parts"] as? [[String: Any]] {
                geminiTurnComplete = false  // Gemini is talking — keep mic muted
                for part in parts {
                    // Audio data
                    if let inline = part["inlineData"] as? [String: Any],
                       let mime   = inline["mimeType"] as? String,
                       mime.contains("audio"),
                       let b64    = inline["data"] as? String {
                        playGeminiAudio(b64)
                    }
                    // Text (some models send text alongside audio)
                    if let text = part["text"] as? String,
                       !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if cleaned.lowercased().contains("[capture_photo]") {
                            commandHandler?(.capturePhoto)
                        } else {
                            commandHandler?(.assistantText(cleaned))
                        }
                    }
                }
            }

            // turnComplete — Gemini finished its response, start unmute countdown
            if content["turnComplete"] != nil {
                geminiTurnComplete = true
                scheduleUnmuteIfReady()
            }

            // Gemini's transcription of what it heard (show in UI)
            if let inputTx = content["inputTranscription"] as? [String: Any],
               let txText  = inputTx["text"] as? String,
               !txText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                commandHandler?(.userText(txText))
            }

            // Interruption — flush queued audio and unmute immediately
            if let interrupted = content["interrupted"] as? Bool, interrupted {
                playerNode.stop()
                playerNode.play()
                scheduledBufferCount = 0
                geminiTurnComplete = true
                isPlayingAudio = false
                playbackEndWorkItem?.cancel()
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: WebSocket send queue
    // ─────────────────────────────────────────────────────────────────────────

    private var wsSendQueue: [String] = []
    private var wsSendInFlight = false

    private func enqueueWSSend(_ payload: String) {
        wsSendQueue.append(payload)
        drainSendQueue()
    }

    private func drainSendQueue() {
        guard !wsSendInFlight, !wsSendQueue.isEmpty, let ws = websocketTask else {
            if websocketTask == nil { wsSendQueue.removeAll() }
            return
        }
        wsSendInFlight = true
        let payload = wsSendQueue.removeFirst()
        ws.send(.string(payload)) { [weak self] error in
            guard let self else { return }
            DispatchQueue.main.async {
                self.wsSendInFlight = false
                if error != nil { self.wsSendQueue.removeAll() }
                else            { self.drainSendQueue() }
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: File recording (backward compat)
    // ─────────────────────────────────────────────────────────────────────────

    private func beginFileRecording(inspectionID: UUID, taskID: UUID) {
        let name = "audio_\(inspectionID.uuidString.prefix(6))_\(taskID.uuidString.prefix(6))_\(Int(Date().timeIntervalSince1970)).m4a"
        let url  = storageDir().appendingPathComponent(name)
        currentFileName = name
        let settings: [String: Any] = [
            AVFormatIDKey:            Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey:          44100,
            AVNumberOfChannelsKey:    1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        recorder = try? AVAudioRecorder(url: url, settings: settings)
        recorder?.record()
        isRecording = true
    }

    private func storageDir() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Image helper
    // ─────────────────────────────────────────────────────────────────────────

    nonisolated private static func prepareImageBase64(imageURL: URL) -> String? {
        guard let image = UIImage(contentsOfFile: imageURL.path) else { return nil }
        var quality: CGFloat = 0.6
        var data = image.jpegData(compressionQuality: quality)
        while let current = data, current.count > 350_000, quality > 0.2 {
            quality -= 0.1
            data = image.jpegData(compressionQuality: quality)
        }
        guard let final = data, !final.isEmpty, final.count <= 700_000 else { return nil }
        return final.base64EncodedString()
    }
}

// MARK: - WebSocket Delegate

private final class WebSocketDelegate: NSObject, URLSessionWebSocketDelegate {
    func urlSession(_ s: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol p: String?) {
        print("[GeminiLive] ✅ WebSocket opened")
    }
    func urlSession(_ s: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith code: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let r = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "none"
        print("[GeminiLive] ⚠️ WebSocket closed — code: \(code.rawValue), reason: \(r)")
    }
    func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { print("[GeminiLive] ❌ Task error: \(error)") }
        if let http = task.response as? HTTPURLResponse {
            print("[GeminiLive] HTTP upgrade: \(http.statusCode)")
        }
    }
}
