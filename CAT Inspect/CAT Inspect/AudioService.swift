// AudioService.swift
// Cat AI Live API — streams raw PCM audio to/from Cat AI assistant.
// Architecture:
//   Mic → 16 kHz PCM → base64 → realtimeInput → Cat AI
//   Cat AI → 24 kHz PCM → AVAudioPlayerNode → speaker

import Foundation
import UIKit
import AVFoundation
import Speech

// MARK: - Cat AI Live Service

@MainActor
final class AudioModalCaller: NSObject, ObservableObject {

    // ── Public state ─────────────────────────────────────────────────────────
    @Published var isRecording       = false
    @Published var isLiveListening   = false
    @Published var isImageProcessing = false

    // ── Commands ─────────────────────────────────────────────────────────────
    enum LiveVoiceCommand {
        case capturePhoto
        case capturePhotoWithContext(String)
        case assistantText(String)
        case assistantAudioText(String)
        case userText(String)
        case finalUserText(String)
        case imageFeedback(String)
        case soundAnomaly(String)
        case submitTask
    }

    // ── Config ───────────────────────────────────────────────────────────────
    private let apiKey: String = {
        let key = ProcessInfo.processInfo.environment["GEMINI_API_KEY"] ?? ""
        if key.isEmpty {
            print("[CatAI] ⚠️ GEMINI_API_KEY not set in scheme environment variables")
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
    private var currentTurnTextBuffer = ""
    private var lastServerOutputTranscript = ""

    // FIX: Track which tag types have already been dispatched in the current
    // turn to prevent duplicate commands from partial-chunk processing.
    private var dispatchedTagsThisTurn: Set<String> = []

    private lazy var wsSession: URLSession = {
        URLSession(
            configuration: .default,
            delegate: WebSocketDelegate(),
            delegateQueue: .main
        )
    }()

    // ── Audio engine ─────────────────────────────────────────────────────────
    private let audioEngine  = AVAudioEngine()
    private let playerNode   = AVAudioPlayerNode()
    private var pcmConverter: AVAudioConverter?

    private let sendFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true
    )!
    private let recvFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16, sampleRate: 24000, channels: 1, interleaved: true
    )!

    // ── Playback state ───────────────────────────────────────────────────────
    private var isPlayingAudio        = false
    private var scheduledBufferCount  = 0
    private var aiTurnComplete    = true
    private var playbackEndWorkItem: DispatchWorkItem?

    // ── STT (UI transcript only) ─────────────────────────────────────────────
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

    // ── Backward-compat recording ────────────────────────────────────────────
    private var recorder: AVAudioRecorder?
    private var currentFileName: String?

    // ── WS send queue ────────────────────────────────────────────────────────
    private var wsSendQueue: [String] = []
    private var wsSendInFlight = false
    private let wsSendQueueMax = 60   // FIX: cap to prevent unbounded growth

    // ── Acoustic Analysis (Modal API) ────────────────────────────────────────
    private static let acousticAnalysisURL = "https://manav-sharma-yeet--inspex-core-fastapi-app.modal.run/analyze-sound"
    private var acousticPCMBuffer = Data()           // accumulates 16 kHz Int16 PCM
    private let acousticSampleRate: Int = 16000
    private let acousticAnalysisIntervalSec: Double = 4.0
    private var acousticAnalysisTimer: DispatchWorkItem?
    private var isAcousticAnalysisInFlight = false
    private var acousticAnalysisCount = 0

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Init
    // ─────────────────────────────────────────────────────────────────────────

    override init() {
        super.init()
        audioEngine.attach(playerNode)
        print("[CatAI] AudioModalCaller initialized")
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
        commandHandler = { cmd in
            DispatchQueue.main.async { onCommand(cmd) }
        }
        taskContextTitle       = taskTitle
        taskContextDescription = taskDescription
        sessionInspectionID    = inspectionID
        sessionTaskID          = taskID

        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            guard let self else { return }
            guard granted else {
                DispatchQueue.main.async {
                    onCommand(.assistantText("Microphone permission required."))
                }
                return
            }
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                guard let self else { return }
                Task { @MainActor in
                    if status != .authorized {
                        print("[CatAI] Speech auth not granted — transcript display disabled")
                    }
                    guard self.configureAudioSession() else { return }
                    self.connectWebSocket(inspectionID: inspectionID, taskID: taskID)
                }
            }
        }
    }

    func stopLiveListening() {
        print("[CatAI] stopLiveListening")
        print("[CATLive] stopLiveListening")

        // STT
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        lastServerOutputTranscript = ""

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

        // FIX: Clear send queue and release command handler to break retain cycle
        wsSendQueue.removeAll()
        wsSendInFlight = false
        commandHandler = nil

        // Acoustic analysis
        acousticAnalysisTimer?.cancel()
        acousticAnalysisTimer = nil
        acousticPCMBuffer = Data()
        isAcousticAnalysisInFlight = false
        acousticAnalysisCount = 0

        // Reset state
        currentTurnTextBuffer = ""
        dispatchedTagsThisTurn.removeAll()
        isPlayingAudio = false
        scheduledBufferCount = 0
        aiTurnComplete = true
        playbackEndWorkItem?.cancel()
        playbackEndWorkItem = nil
        isImageProcessing = false
        isLiveListening = false
        liveSessionKey = nil
        taskContextTitle = ""
        taskContextDescription = ""
    }

    // ── Backward compat ──────────────────────────────────────────────────────

    func startRecording(inspectionID: UUID, taskID: UUID) {
        // FIX: Don't reconfigure audio session if live session is active —
        // that would break the live pipeline.
        guard !isLiveListening else {
            print("[CatAI] startRecording ignored: live session is active")
            print("[CATLive] startRecording ignored: live session is active")
            return
        }
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

    /// Send a captured image to Cat AI via the live WebSocket.
    func sendCapturedImageToWebSocket(fileName: String, note: String) {
        // FIX: Guard both isLiveListening AND websocketTask existence
        guard isLiveListening, websocketTask != nil else {
            print("[CatAI] sendCapturedImageToWebSocket: no active session")
            print("[CATLive] sendCapturedImageToWebSocket: no active session")
            return
        }
        guard !isImageProcessing else {
            print("[CatAI] sendCapturedImageToWebSocket: image already processing")
            print("[CATLive] sendCapturedImageToWebSocket: image already processing")
            return
        }
        isImageProcessing = true

        let imageURL = storageDir().appendingPathComponent(fileName)

        // FIX: Capture self weakly before the detached task to avoid retain cycles
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            guard let base64 = Self.prepareImageBase64(imageURL: imageURL) else {
                await MainActor.run { self.isImageProcessing = false }
                print("[CatAI] sendCapturedImageToWebSocket: failed to encode image")
                print("[CATLive] sendCapturedImageToWebSocket: failed to encode image")
                return
            }
            let payload: [String: Any] = [
                "clientContent": [
                    "turns": [[
                        "role": "user",
                        "parts": [
                            ["text": note.isEmpty ? "Please analyze this image." : note],
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
    // MARK: Audio session
    // ─────────────────────────────────────────────────────────────────────────

    private func configureAudioSession() -> Bool {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord, mode: .voiceChat,
                options: [.defaultToSpeaker, .allowBluetooth]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            print("[CatAI] ✅ Audio session configured")
            print("[CATLive] ✅ Audio session configured")
            return true
        } catch {
            print("[CatAI] ❌ Audio session error: \(error)")
            print("[CATLive] ❌ Audio session error: \(error)")
            commandHandler?(.assistantText("Audio session error: \(error.localizedDescription)"))
            return false
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Audio pipeline
    // ─────────────────────────────────────────────────────────────────────────

    private func startAudioPipeline() {
        let inputNode = audioEngine.inputNode
        let hwFormat  = inputNode.outputFormat(forBus: 0)
        print("[CatAI] Mic hardware format: \(hwFormat)")
        print("[CATLive] Mic hardware format: \(hwFormat)")

        // FIX: Guard against zero sample rate which would crash AVAudioConverter
        guard hwFormat.sampleRate > 0 else {
            print("[CatAI] ❌ Invalid hardware format — sample rate is 0")
            print("[CATLive] ❌ Invalid hardware format — sample rate is 0")
            commandHandler?(.assistantText("Audio hardware unavailable."))
            return
        }

        guard let converter = AVAudioConverter(from: hwFormat, to: sendFormat) else {
            print("[CatAI] ❌ Failed to create AVAudioConverter")
            print("[CATLive] ❌ Failed to create AVAudioConverter")
            commandHandler?(.assistantText("Audio conversion unavailable."))
            return
        }
        pcmConverter = converter

        // Connect player to mixer
        // FIX: Disconnect first to avoid "already connected" assertion crashes
        audioEngine.disconnectNodeOutput(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: recvFormat)

        // STT request
        let sttRequest = SFSpeechAudioBufferRecognitionRequest()
        sttRequest.shouldReportPartialResults = true
        sttRequest.taskHint = .dictation
        recognitionRequest = sttRequest

        inputNode.removeTap(onBus: 0)

        let targetFormat = sendFormat

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] buffer, _ in
            guard let self, buffer.frameLength > 0 else { return }
            guard !self.isPlayingAudio else { return }   // echo suppression

            sttRequest.append(buffer)
            guard self.setupAcknowledged else { return }

            // FIX: Correct AVAudioConverter input block pattern.
            // The previous "consumed" flag approach could stall the converter
            // on subsequent calls. Use a single-use closure captured per call.
            let ratio = 16000.0 / hwFormat.sampleRate
            let outFrameCount = AVAudioFrameCount(max(1, Double(buffer.frameLength) * ratio))

            guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outFrameCount) else {
                return
            }

            var inputConsumed = false
            var convError: NSError?

            self.pcmConverter?.convert(to: converted, error: &convError) { _, outStatus in
                if inputConsumed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                inputConsumed = true
                outStatus.pointee = .haveData
                return buffer
            }

            guard convError == nil, converted.frameLength > 0 else { return }

            let byteCount = Int(converted.frameLength) * MemoryLayout<Int16>.size
            let pcmData   = Data(bytes: converted.int16ChannelData![0], count: byteCount)
            let base64    = pcmData.base64EncodedString()

            // Accumulate PCM for acoustic analysis
            DispatchQueue.main.async { [weak self] in
                self?.acousticPCMBuffer.append(pcmData)
                self?.scheduleAcousticAnalysisIfNeeded()
            }

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
            print("[CatAI] ✅ Audio engine started")
        } catch {
            print("[CatAI] ❌ Audio engine start failed: \(error)")
            print("[CATLive] ❌ Audio engine start failed: \(error)")
            commandHandler?(.assistantText("Audio engine failed: \(error.localizedDescription)"))
        }

        // STT recognition (UI only)
        if speechRecognizer?.isAvailable == true {
            recognitionTask = speechRecognizer?.recognitionTask(with: sttRequest) { [weak self] result, error in
                guard let self else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    DispatchQueue.main.async {
                        self.commandHandler?(.userText(String(text.suffix(120))))
                    }
                }
                if let error {
                    print("[CatAI] STT error (non-fatal): \(error.localizedDescription)")
                }
            }
        }

    }

    /// Decode Cat AI 24 kHz PCM audio and schedule on playerNode.
    private func playCatAudio(_ base64Data: String) {
        guard let rawData = Data(base64Encoded: base64Data), !rawData.isEmpty else { return }

        // 16-bit samples = 2 bytes each
        let frameCount = UInt32(rawData.count / MemoryLayout<Int16>.size)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: recvFormat, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount

        rawData.withUnsafeBytes { src in
            guard let baseAddr = src.baseAddress else { return }
            memcpy(buffer.int16ChannelData![0], baseAddr, rawData.count)
        }

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

    /// Unmute mic only after all buffers finish AND Cat AI's turn is complete.
    private func scheduleUnmuteIfReady() {
        playbackEndWorkItem?.cancel()
        guard scheduledBufferCount == 0, aiTurnComplete else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.scheduledBufferCount == 0 && self.aiTurnComplete {
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
        print("[CatAI] Connecting WebSocket…")
        websocketTask = wsSession.webSocketTask(with: wsEndpoint)
        websocketTask?.resume()

        let systemText = buildSystemPrompt(inspectionID: inspectionID, taskID: taskID)

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
                "outputAudioTranscription": [:],
                "systemInstruction": [
                    "parts": [["text": systemText]]
                ]
            ]
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: setupMessage),
              let str  = String(data: data, encoding: .utf8) else {
            print("[CatAI] ❌ Failed to serialize setup message")
            return
        }

        print("[CatAI] Sending setup (\(str.count) chars)")
        print("[CATLive] Sending setup (\(str.count) chars)")
        websocketTask?.send(.string(str)) { [weak self] error in
            if let error {
                print("[CatAI] ❌ Setup send failed: \(error)")
                print("[CATLive] ❌ Setup send failed: \(error)")
                DispatchQueue.main.async {
                    self?.commandHandler?(.assistantText("Connection failed: \(error.localizedDescription)"))
                }
            } else {
                print("[CatAI] ✅ Setup sent, waiting for setupComplete…")
                print("[CATLive] ✅ Setup sent, waiting for setupComplete…")
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
                    // FIX: Don't report errors after intentional teardown
                    guard self.websocketTask != nil else { return }
                    print("[CatAI] ❌ WS receive error: \(error)")
                    print("[CATLive] ❌ WS receive error: \(error)")
                    self.commandHandler?(.assistantText("Connection dropped."))

                case .success(let msg):
                    let raw: String?
                    switch msg {
                    case .string(let s): raw = s
                    case .data(let d):   raw = String(data: d, encoding: .utf8)
                    @unknown default:    raw = nil
                    }
                    if let raw { self.handleServerMessage(raw) }
                    // Only continue receiving if session is still active
                    if self.websocketTask != nil {
                        self.receiveMessages()
                    }
                }
            }
        }
    }

    private func handleServerMessage(_ raw: String) {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("[CatAI] ⚠️ Unparseable server message")
            print("[CATLive] ⚠️ Unparseable server message")
            return
        }

        // setupComplete → start audio pipeline
        if json["setupComplete"] != nil {
            print("[CatAI] ✅ setupComplete — starting audio pipeline")
            print("[CATLive] ✅ setupComplete — starting audio pipeline")
            setupAcknowledged = true
            isLiveListening = true
            startAudioPipeline()
            commandHandler?(.assistantText("AI ready. Speak now."))
            return
        }

        // serverContent
        if let content = json["serverContent"] as? [String: Any] {
            isImageProcessing = false

            if let outputTx = content["outputTranscription"] as? [String: Any],
               let txText = outputTx["text"] as? String {
                let delta = deltaFromServerOutputTranscript(txText)
                if !delta.isEmpty {
                    commandHandler?(.assistantAudioText(delta))
                }
            }

            if let turn = content["modelTurn"] as? [String: Any],
               let parts = turn["parts"] as? [[String: Any]] {

                aiTurnComplete = false  // keep mic muted while Cat AI speaks

                for part in parts {
                    // Audio
                    if let inline = part["inlineData"] as? [String: Any],
                       let mime   = inline["mimeType"] as? String,
                       mime.contains("audio"),
                       let b64    = inline["data"] as? String {
                        playCatAudio(b64)
                    }
                    // Text
                    if let text = part["text"] as? String {
                        currentTurnTextBuffer += text
                        parseTextCommands(isFinal: false)
                    }
                }
            }

            // turnComplete
            if let turnComplete = content["turnComplete"] as? Bool, turnComplete {
                aiTurnComplete = true

                // FIX: If Cat AI responded with text only (no audio), we must
                // still clear isPlayingAudio to re-enable the mic.
                if scheduledBufferCount == 0 {
                    isPlayingAudio = false
                } else {
                    scheduleUnmuteIfReady()
                }

                // Final parse sweep of any dangling text
                parseTextCommands(isFinal: true)

                currentTurnTextBuffer = ""
                dispatchedTagsThisTurn.removeAll()
                lastServerOutputTranscript = ""
            }

            // User speech transcription
            if let inputTx = content["inputTranscription"] as? [String: Any],
               let txText  = inputTx["text"] as? String,
               !txText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                commandHandler?(.finalUserText(txText))
                commandHandler?(.userText(txText))
            }

            // Interruption — flush audio, unmute immediately
            if let interrupted = content["interrupted"] as? Bool, interrupted {
                print("[CatAI] Interrupted by user")
                playerNode.stop()
                // FIX: Reconnect playerNode after stop so future audio plays
                audioEngine.disconnectNodeOutput(playerNode)
                audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: recvFormat)
                playerNode.play()

                scheduledBufferCount = 0
                aiTurnComplete = true
                isPlayingAudio = false
                playbackEndWorkItem?.cancel()
                currentTurnTextBuffer = ""
                dispatchedTagsThisTurn.removeAll()
                lastServerOutputTranscript = ""
            }
        }
    }

    private func deltaFromServerOutputTranscript(_ fullText: String) -> String {
        let cleaned = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "" }

        let delta: String
        if cleaned.hasPrefix(lastServerOutputTranscript) {
            delta = String(cleaned.dropFirst(lastServerOutputTranscript.count))
        } else if lastServerOutputTranscript.isEmpty {
            delta = cleaned
        } else if cleaned.count > lastServerOutputTranscript.count {
            delta = String(cleaned.suffix(cleaned.count - lastServerOutputTranscript.count))
        } else {
            delta = cleaned
        }

        lastServerOutputTranscript = cleaned
        return delta.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Parse text action tags
    // ─────────────────────────────────────────────────────────────────────────

    private func parseTextCommands(isFinal: Bool = false) {
        // FIX: Use dispatchedTagsThisTurn to prevent duplicate commands when
        // parseTextCommands is called repeatedly on partial text chunks.

        // [submit_task]
        if !dispatchedTagsThisTurn.contains("submit_task"),
           currentTurnTextBuffer.range(of: "\\[submit_task\\]",
               options: [.regularExpression, .caseInsensitive]) != nil {
            dispatchedTagsThisTurn.insert("submit_task")
            commandHandler?(.submitTask)
        }

        // [capture_photo: <context>]  or  [capture_photo]
        if !dispatchedTagsThisTurn.contains("capture_photo") {
            let lowerBuffer = currentTurnTextBuffer.lowercased()
            if let range = lowerBuffer.range(of: "capture_photo:") {
                let startIndex = currentTurnTextBuffer.index(currentTurnTextBuffer.startIndex, offsetBy: range.upperBound.utf16Offset(in: lowerBuffer))
                var context = String(currentTurnTextBuffer[startIndex...])
                let hasClosingBracket = context.contains("]")
                
                if hasClosingBracket || isFinal {
                    dispatchedTagsThisTurn.insert("capture_photo")
                    if let closeIdx = context.firstIndex(of: "]") {
                        context = String(context[..<closeIdx])
                    }
                    context = context.trimmingCharacters(in: .whitespacesAndNewlines)
                    if context.isEmpty {
                        commandHandler?(.capturePhoto)
                    } else {
                        commandHandler?(.capturePhotoWithContext(context))
                    }
                }
            } else if lowerBuffer.contains("capture_photo") {
                dispatchedTagsThisTurn.insert("capture_photo")
                commandHandler?(.capturePhoto)
            }
        }

        // [image_feedback: <bullets>]
        if !dispatchedTagsThisTurn.contains("image_feedback") {
            let lowerBuffer = currentTurnTextBuffer.lowercased()
            if let range = lowerBuffer.range(of: "image_feedback:") {
                // Extract everything after the colon
                let startIndex = currentTurnTextBuffer.index(currentTurnTextBuffer.startIndex, offsetBy: range.upperBound.utf16Offset(in: lowerBuffer))
                var feedback = String(currentTurnTextBuffer[startIndex...])
                let hasClosingBracket = feedback.contains("]")
                
                // Only process if we've seen the closing bracket or the stream is officially finished
                if hasClosingBracket || isFinal {
                    dispatchedTagsThisTurn.insert("image_feedback")
                    if let closeIdx = feedback.firstIndex(of: "]") {
                        feedback = String(feedback[..<closeIdx])
                    }
                    feedback = feedback.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !feedback.isEmpty {
                        commandHandler?(.imageFeedback(feedback))
                    }
                }
            }
        }

        // Strip all dispatched tags from buffer so they don't pollute
        // the assistantText output, then emit any remaining plain text.
        var cleaned = currentTurnTextBuffer
        
        let lowerClean = cleaned.lowercased()
        if let idx = lowerClean.range(of: "image_feedback:") {
            if let openIdx = cleaned[..<idx.lowerBound].lastIndex(of: "[") {
                cleaned = String(cleaned[..<openIdx])
            } else {
                cleaned = String(cleaned[..<idx.lowerBound])
            }
        } else if let idx = lowerClean.range(of: "capture_photo") {
            if let openIdx = cleaned[..<idx.lowerBound].lastIndex(of: "[") {
                cleaned = String(cleaned[..<openIdx])
            } else {
                cleaned = String(cleaned[..<idx.lowerBound])
            }
        } else if let idx = lowerClean.range(of: "submit_task") {
            if let openIdx = cleaned[..<idx.lowerBound].lastIndex(of: "[") {
                cleaned = String(cleaned[..<openIdx])
            } else {
                cleaned = String(cleaned[..<idx.lowerBound])
            }
        }
        
        // Final fallback regex strip
        let tagPatterns = [
            "\\[submit_task\\]",
            "\\[capture_photo:[^\\]]*\\]",
            "\\[capture_photo\\]",
            "\\[image_feedback:[^\\]]*\\]"
        ]
        for pattern in tagPatterns {
            cleaned = cleaned.replacingOccurrences(
                of: pattern, with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            commandHandler?(.assistantText(trimmed))
        }
    }

    /// Extract the value after the colon in a `[tag: value]` string.
    private func extractTagValue(from match: String) -> String {
        guard let colonIdx = match.firstIndex(of: ":") else { return "" }
        return match[match.index(after: colonIdx)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "]", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: WebSocket send queue
    // ─────────────────────────────────────────────────────────────────────────

    private func enqueueWSSend(_ payload: String) {
        // FIX: Drop oldest audio frames (not control messages) if queue is full.
        // Audio realtimeInput messages are safe to drop; control messages are not.
        if wsSendQueue.count >= wsSendQueueMax {
            if let dropIdx = wsSendQueue.firstIndex(where: { $0.contains("realtimeInput") }) {
                wsSendQueue.remove(at: dropIdx)
            } else {
                // Queue is full of control messages — drop new payload to protect ordering
                print("[CatAI] ⚠️ WS send queue full, dropping payload")
                print("[CATLive] ⚠️ WS send queue full, dropping payload")
                return
            }
        }
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
                if let error {
                    print("[CatAI] ❌ WS send error: \(error) — clearing queue")
                    print("[CATLive] ❌ WS send error: \(error) — clearing queue")
                    self.wsSendQueue.removeAll()
                } else {
                    self.drainSendQueue()
                }
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: System prompt
    // ─────────────────────────────────────────────────────────────────────────

    private func buildSystemPrompt(inspectionID: UUID, taskID: UUID) -> String {
        """
        You are Cat, the AI inspection assistant for Caterpillar heavy equipment.
        The inspector calls you "Hey Cat" — respond to that naturally.
        You are an AI audio-visual inspection assistant for Caterpillar heavy equipment.
        You perform real-time audio-visual inspections: you listen for mechanical sounds AND analyze images.
        Current task: \(taskContextTitle).
        Task description: \(taskContextDescription).
        Inspection ID: \(inspectionID.uuidString). Task ID: \(taskID.uuidString).

        RULES:
        - Keep responses concise and practical. Speak naturally.
        - ACTION INTENT ENGINE: Detect the user's underlying intent regardless of phrasing. Map action expressions to the correct macro tag.
        - You have a companion ACOUSTIC ANALYSIS system that listens to mechanical sounds in real time.
          When it detects an anomaly (grinding, knocking, vibration), it will send you an alert.
          Acknowledge these alerts concisely, e.g. "Acoustic alert: grinding detected. Let me capture a photo to verify."

        VOICE MENU — read aloud when the user says "menu", "help", "what can I do", or seems stuck:
          "You can say:
           1. Capture an image — to take and analyze a photo.
           2. Submit the task — to save findings and go to the next task.
           3. Menu — to hear these options again."
          If the user just captured an image:
           "Your findings have been saved. You can capture another image or submit the task."

        ACTION MACROS:
        1. CAPTURE PHOTO: Detect intent to photograph, analyze, view, or 'look at' something.
           Tag: [capture_photo: <context>]  (context = what they are pointing out, or 'general inspection')
           Examples: "Check this rusting" → [capture_photo: rusting], "Take a pic" → [capture_photo: general inspection]
        2. SUBMIT TASK: Detect intent to finish, complete, submit, or move on.
           Tag: [submit_task]

        IMAGE ANALYSIS (when an image is received):
        1. Detect anomalies, rank EACH as: Moderate, Pass, or Normal.
        2. Speak findings as: "Finding 1: [rank] — [one-line description]."
        3. CRITICAL: Always output a structured text tag EXACTLY like this:
           [image_feedback: Moderate — Visible rust on bracket\\nNormal — Tire acceptable]
        - Use \\n between findings inside the tag. Do NOT use • in the tag.
        - This tag is mandatory for every image analyzed.

        ACOUSTIC ANALYSIS (when a [sound_alert] message is received):
        - Acknowledge the acoustic finding briefly in speech.
        - Incorporate it into your overall inspection assessment.
        - If the finding is FAIL or MONITOR, recommend visual confirmation via photo capture.

        TEXT TAGS ([image_feedback:...], [capture_photo:...], [submit_task]) must appear in text output only, never spoken aloud.
        """
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
        // FIX: Log recorder creation errors instead of silently swallowing them
        do {
            recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder?.record()
            isRecording = true
        } catch {
            print("[CatAI] ❌ Failed to create recorder: \(error)")
            print("[CATLive] ❌ Failed to create recorder: \(error)")
            isRecording = false
        }
    }

    private func storageDir() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Image helper
    // ─────────────────────────────────────────────────────────────────────────

    nonisolated private static func prepareImageBase64(imageURL: URL) -> String? {
        guard let image = UIImage(contentsOfFile: imageURL.path) else {
            print("[CatAI] prepareImageBase64: no image at \(imageURL.lastPathComponent)")
            print("[CATLive] prepareImageBase64: no image at \(imageURL.lastPathComponent)")
            return nil
        }
        var quality: CGFloat = 0.6
        var data = image.jpegData(compressionQuality: quality)
        while let current = data, current.count > 350_000, quality > 0.2 {
            quality -= 0.1
            data = image.jpegData(compressionQuality: quality)
        }
        guard let final = data, !final.isEmpty, final.count <= 700_000 else {
            print("[CatAI] prepareImageBase64: image too large or empty")
            print("[CATLive] prepareImageBase64: image too large or empty")
            return nil
        }
        return final.base64EncodedString()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Acoustic Analysis (Modal API)
    // ─────────────────────────────────────────────────────────────────────────

    /// Schedule acoustic analysis if we've accumulated enough audio.
    private func scheduleAcousticAnalysisIfNeeded() {
        guard acousticAnalysisTimer == nil else { return }
        let bytesNeeded = acousticSampleRate * 2 * Int(acousticAnalysisIntervalSec) // Int16 = 2 bytes
        guard acousticPCMBuffer.count >= bytesNeeded else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.acousticAnalysisTimer = nil
            self.performAcousticAnalysis()
        }
        acousticAnalysisTimer = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
    }

    /// Extract accumulated audio, convert to WAV, send to Modal API.
    private func performAcousticAnalysis() {
        guard !isAcousticAnalysisInFlight else { return }
        guard !acousticPCMBuffer.isEmpty else { return }

        isAcousticAnalysisInFlight = true
        let pcmData = acousticPCMBuffer
        acousticPCMBuffer = Data() // reset buffer
        acousticAnalysisCount += 1
        let analysisNum = acousticAnalysisCount

        print("[CATLive] 🔊 Sending acoustic analysis #\(analysisNum) (\(pcmData.count) bytes)")

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }

            // Build WAV from raw PCM
            let wavData = Self.buildWAV(pcmData: pcmData, sampleRate: 16000, channels: 1, bitsPerSample: 16)

            // Send to Modal API
            let result = await Self.sendAcousticToModal(wavData: wavData, equipmentID: "CAT-LIVE-\(analysisNum)")

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isAcousticAnalysisInFlight = false

                guard let result else {
                    print("[CATLive] 🔊 Acoustic analysis #\(analysisNum): no result")
                    return
                }

                let status = result["overall_status"] as? String ?? "UNKNOWN"
                print("[CATLive] 🔊 Acoustic analysis #\(analysisNum): \(status)")

                // Only dispatch anomaly if MONITOR or FAIL
                if status == "FAIL" || status == "MONITOR" {
                    let faults = result["faults"] as? [[String: Any]] ?? []
                    let metrics = result["metrics"] as? [String: Any] ?? [:]

                    var findings: [String] = []
                    for fault in faults {
                        let issue = fault["issue"] as? String ?? "Unknown issue"
                        let severity = fault["severity"] as? String ?? "UNKNOWN"
                        let confidence = fault["confidence"] as? Double ?? 0.0
                        let reason = fault["technical_reason"] as? String ?? ""
                        findings.append("\(severity): \(issue) (\(Int(confidence * 100))%) — \(reason)")
                    }

                    let centroid = metrics["avg_centroid_hz"] as? Double ?? 0
                    let crestFactor = metrics["crest_factor"] as? Double ?? 0

                    let summaryText = findings.isEmpty
                        ? "Acoustic \(status): anomaly detected (centroid: \(Int(centroid))Hz, crest: \(String(format: "%.1f", crestFactor)))"
                        : findings.joined(separator: "\n")

                    // Dispatch to UI
                    self.commandHandler?(.soundAnomaly(summaryText))

                    // Also inject into Gemini conversation so it can respond
                    self.sendAcousticAlertToGemini(status: status, findings: findings)
                }
            }
        }
    }

    /// Build a WAV file from raw PCM Int16 data.
    nonisolated private static func buildWAV(pcmData: Data, sampleRate: Int, channels: Int, bitsPerSample: Int) -> Data {
        var wav = Data()
        let dataSize = UInt32(pcmData.count)
        let fileSize = UInt32(36 + pcmData.count)
        let byteRate = UInt32(sampleRate * channels * bitsPerSample / 8)
        let blockAlign = UInt16(channels * bitsPerSample / 8)

        // RIFF header
        wav.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        wav.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        wav.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"

        // fmt sub-chunk
        wav.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        wav.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) }) // sub-chunk size
        wav.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })  // PCM format
        wav.append(contentsOf: withUnsafeBytes(of: UInt16(channels).littleEndian) { Array($0) })
        wav.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        wav.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        wav.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        wav.append(contentsOf: withUnsafeBytes(of: UInt16(bitsPerSample).littleEndian) { Array($0) })

        // data sub-chunk
        wav.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        wav.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })
        wav.append(pcmData)

        return wav
    }

    /// Send WAV audio to the Modal /analyze-sound endpoint.
    nonisolated private static func sendAcousticToModal(wavData: Data, equipmentID: String) async -> [String: Any]? {
        guard let url = URL(string: acousticAnalysisURL) else { return nil }

        let boundary = "AcousticBoundary\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        var body = Data()

        // audio file field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"live_capture.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wavData)
        body.append("\r\n".data(using: .utf8)!)

        // equipment_id field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"equipment_id\"\r\n\r\n".data(using: .utf8)!)
        body.append(equipmentID.data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                print("[CATLive] 🔊 Modal API returned non-200: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return nil
            }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            return json
        } catch {
            print("[CATLive] 🔊 Modal API error: \(error.localizedDescription)")
            return nil
        }
    }

    /// Inject an acoustic alert into the Gemini WebSocket conversation.
    private func sendAcousticAlertToGemini(status: String, findings: [String]) {
        guard isLiveListening, websocketTask != nil else { return }

        let findingsText = findings.isEmpty ? "Anomaly detected" : findings.joined(separator: "; ")
        let alertMessage = "[sound_alert] Acoustic analysis result: \(status). \(findingsText). Please acknowledge this acoustic finding and recommend next steps."

        let payload: [String: Any] = [
            "clientContent": [
                "turns": [[
                    "role": "user",
                    "parts": [["text": alertMessage]]
                ]],
                "turnComplete": true
            ]
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let str = String(data: data, encoding: .utf8) else { return }

        enqueueWSSend(str)
        print("[CATLive] 🔊 Sent acoustic alert to Gemini: \(status)")
    }
}

// MARK: - WebSocket Delegate

private final class WebSocketDelegate: NSObject, URLSessionWebSocketDelegate {
    func urlSession(_ s: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol p: String?) {
        print("[CatAI] ✅ WebSocket opened")
        print("[CATLive] ✅ WebSocket opened")
    }
    func urlSession(_ s: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith code: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let r = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "none"
        print("[CatAI] ⚠️ WebSocket closed — code: \(code.rawValue), reason: \(r)")
        print("[CATLive] ⚠️ WebSocket closed — code: \(code.rawValue), reason: \(r)")
    }
    func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            print("[CatAI] ❌ Task error: \(error)")
            print("[CATLive] ❌ Task error: \(error)")
        }
        if let http = task.response as? HTTPURLResponse {
            print("[CatAI] HTTP upgrade status: \(http.statusCode)")
            print("[CATLive] HTTP upgrade status: \(http.statusCode)")
        }
    }
}
