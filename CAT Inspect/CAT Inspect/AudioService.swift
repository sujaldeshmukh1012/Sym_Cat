// AudioService.swift
// Gemini Live API — streams raw PCM audio to/from Gemini.
// Architecture:
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

    // ── Commands ─────────────────────────────────────────────────────────────
    enum LiveVoiceCommand {
        case capturePhoto
        case capturePhotoWithContext(String)
        case assistantText(String)
        case userText(String)
        case imageFeedback(String)
        case submitTask
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
    private var currentTurnTextBuffer = ""

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
    private var geminiTurnComplete    = true
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

        // FIX: Clear send queue and release command handler to break retain cycle
        wsSendQueue.removeAll()
        wsSendInFlight = false
        commandHandler = nil

        // Reset state
        currentTurnTextBuffer = ""
        dispatchedTagsThisTurn.removeAll()
        isPlayingAudio = false
        scheduledBufferCount = 0
        geminiTurnComplete = true
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
            print("[GeminiLive] startRecording ignored: live session is active")
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

    /// Send a captured image to Gemini via the live WebSocket.
    func sendCapturedImageToWebSocket(fileName: String, note: String) {
        // FIX: Guard both isLiveListening AND websocketTask existence
        guard isLiveListening, websocketTask != nil else {
            print("[GeminiLive] sendCapturedImageToWebSocket: no active session")
            return
        }
        guard !isImageProcessing else {
            print("[GeminiLive] sendCapturedImageToWebSocket: image already processing")
            return
        }
        isImageProcessing = true

        let imageURL = storageDir().appendingPathComponent(fileName)

        // FIX: Capture self weakly before the detached task to avoid retain cycles
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            guard let base64 = Self.prepareImageBase64(imageURL: imageURL) else {
                await MainActor.run { self.isImageProcessing = false }
                print("[GeminiLive] sendCapturedImageToWebSocket: failed to encode image")
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
            print("[GeminiLive] ✅ Audio session configured")
            return true
        } catch {
            print("[GeminiLive] ❌ Audio session error: \(error)")
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
        print("[GeminiLive] Mic hardware format: \(hwFormat)")

        // FIX: Guard against zero sample rate which would crash AVAudioConverter
        guard hwFormat.sampleRate > 0 else {
            print("[GeminiLive] ❌ Invalid hardware format — sample rate is 0")
            commandHandler?(.assistantText("Audio hardware unavailable."))
            return
        }

        guard let converter = AVAudioConverter(from: hwFormat, to: sendFormat) else {
            print("[GeminiLive] ❌ Failed to create AVAudioConverter")
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
            print("[GeminiLive] ✅ Audio engine started")
        } catch {
            print("[GeminiLive] ❌ Audio engine start failed: \(error)")
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
                    print("[GeminiLive] STT error (non-fatal): \(error.localizedDescription)")
                }
            }
        }
    }

    /// Decode Gemini's 24 kHz PCM audio and schedule on playerNode.
    private func playGeminiAudio(_ base64Data: String) {
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

    /// Unmute mic only after all buffers finish AND Gemini's turn is complete.
    private func scheduleUnmuteIfReady() {
        playbackEndWorkItem?.cancel()
        guard scheduledBufferCount == 0, geminiTurnComplete else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
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
        print("[GeminiLive] Connecting WebSocket…")
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
                "systemInstruction": [
                    "parts": [["text": systemText]]
                ]
            ]
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: setupMessage),
              let str  = String(data: data, encoding: .utf8) else {
            print("[GeminiLive] ❌ Failed to serialize setup message")
            return
        }

        print("[GeminiLive] Sending setup (\(str.count) chars)")
        websocketTask?.send(.string(str)) { [weak self] error in
            if let error {
                print("[GeminiLive] ❌ Setup send failed: \(error)")
                DispatchQueue.main.async {
                    self?.commandHandler?(.assistantText("Connection failed: \(error.localizedDescription)"))
                }
            } else {
                print("[GeminiLive] ✅ Setup sent, waiting for setupComplete…")
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
            print("[GeminiLive] ⚠️ Unparseable server message")
            return
        }

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

            if let turn = content["modelTurn"] as? [String: Any],
               let parts = turn["parts"] as? [[String: Any]] {

                geminiTurnComplete = false  // keep mic muted while Gemini speaks

                for part in parts {
                    // Audio
                    if let inline = part["inlineData"] as? [String: Any],
                       let mime   = inline["mimeType"] as? String,
                       mime.contains("audio"),
                       let b64    = inline["data"] as? String {
                        playGeminiAudio(b64)
                    }
                    // Text
                    if let text = part["text"] as? String {
                        currentTurnTextBuffer += text
                        parseTextCommands()
                    }
                }
            }

            // turnComplete
            if content["turnComplete"] != nil {
                geminiTurnComplete = true

                // FIX: If Gemini responded with text only (no audio), we must
                // still clear isPlayingAudio to re-enable the mic.
                if scheduledBufferCount == 0 {
                    isPlayingAudio = false
                } else {
                    scheduleUnmuteIfReady()
                }

                currentTurnTextBuffer = ""
                dispatchedTagsThisTurn.removeAll()
            }

            // User speech transcription
            if let inputTx = content["inputTranscription"] as? [String: Any],
               let txText  = inputTx["text"] as? String,
               !txText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                commandHandler?(.userText(txText))
            }

            // Interruption — flush audio, unmute immediately
            if let interrupted = content["interrupted"] as? Bool, interrupted {
                print("[GeminiLive] Interrupted by user")
                playerNode.stop()
                // FIX: Reconnect playerNode after stop so future audio plays
                audioEngine.disconnectNodeOutput(playerNode)
                audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: recvFormat)
                playerNode.play()

                scheduledBufferCount = 0
                geminiTurnComplete = true
                isPlayingAudio = false
                playbackEndWorkItem?.cancel()
                currentTurnTextBuffer = ""
                dispatchedTagsThisTurn.removeAll()
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Parse text action tags
    // ─────────────────────────────────────────────────────────────────────────

    private func parseTextCommands() {
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
            if let range = currentTurnTextBuffer.range(
                of: "\\[capture_photo:\\s*([^\\]]+)\\]",
                options: [.regularExpression, .caseInsensitive]
            ) {
                dispatchedTagsThisTurn.insert("capture_photo")
                let match   = String(currentTurnTextBuffer[range])
                let context = extractTagValue(from: match)
                if context.isEmpty {
                    commandHandler?(.capturePhoto)
                } else {
                    commandHandler?(.capturePhotoWithContext(context))
                }
            } else if currentTurnTextBuffer.range(
                of: "\\[capture_photo\\]",
                options: [.regularExpression, .caseInsensitive]
            ) != nil {
                dispatchedTagsThisTurn.insert("capture_photo")
                commandHandler?(.capturePhoto)
            }
        }

        // [image_feedback: <bullets>]
        if !dispatchedTagsThisTurn.contains("image_feedback"),
           let range = currentTurnTextBuffer.range(
               of: "\\[image_feedback:\\s*([^\\]]+)\\]",
               options: [.regularExpression, .caseInsensitive]
           ) {
            dispatchedTagsThisTurn.insert("image_feedback")
            let match    = String(currentTurnTextBuffer[range])
            let feedback = extractTagValue(from: match)
            if !feedback.isEmpty {
                commandHandler?(.imageFeedback(feedback))
            }
        }

        // Strip all dispatched tags from buffer so they don't pollute
        // the assistantText output, then emit any remaining plain text.
        var cleaned = currentTurnTextBuffer
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
                print("[GeminiLive] ⚠️ WS send queue full, dropping payload")
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
                    print("[GeminiLive] ❌ WS send error: \(error) — clearing queue")
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
        You are an AI inspection assistant for Caterpillar heavy equipment.
        Current task: \(taskContextTitle).
        Task description: \(taskContextDescription).
        Inspection ID: \(inspectionID.uuidString). Task ID: \(taskID.uuidString).

        RULES:
        - Keep responses concise and practical. Speak naturally.
        - ACTION INTENT ENGINE: Detect the user's underlying intent regardless of phrasing. Map action expressions to the correct macro tag.

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
            print("[GeminiLive] ❌ Failed to create recorder: \(error)")
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
            print("[GeminiLive] prepareImageBase64: no image at \(imageURL.lastPathComponent)")
            return nil
        }
        var quality: CGFloat = 0.6
        var data = image.jpegData(compressionQuality: quality)
        while let current = data, current.count > 350_000, quality > 0.2 {
            quality -= 0.1
            data = image.jpegData(compressionQuality: quality)
        }
        guard let final = data, !final.isEmpty, final.count <= 700_000 else {
            print("[GeminiLive] prepareImageBase64: image too large or empty")
            return nil
        }
        return final.base64EncodedString()
    }
}

// MARK: - WebSocket Delegate

private final class WebSocketDelegate: NSObject, URLSessionWebSocketDelegate {
    func urlSession(_ s: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol p: String?) {
        print("[GeminiLive] ✅ WebSocket opened")
    }
    func urlSession(_ s: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith code: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let r = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "none"
        print("[GeminiLive] ⚠️ WebSocket closed — code: \(code.rawValue), reason: \(r)")
    }
    func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            print("[GeminiLive] ❌ Task error: \(error)")
        }
        if let http = task.response as? HTTPURLResponse {
            print("[GeminiLive] HTTP upgrade status: \(http.statusCode)")
        }
    }
}