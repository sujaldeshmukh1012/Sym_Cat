import AVFoundation
import Combine
import Foundation
import UIKit

// MARK: - Session state

enum LiveSessionState: Equatable {
    case idle
    case connecting
    case connected
    case runningTool(String)
    case error(String)
    
    var label: String {
        switch self {
        case .idle:               return "Tap to start"
        case .connecting:         return "Connecting…"
        case .connected:          return "Listening"
        case .runningTool(let t): return "Running \(t)…"
        case .error(let e):       return "Error: \(e.prefix(60))"
        }
    }
}

// MARK: - Protocol for camera capture (provided by the View)

protocol LiveInspectionCameraDelegate: AnyObject {
    /// Capture a photo and return JPEG data
    func capturePhotoData() async throws -> Data
}

// MARK: - LiveInspectionService

@MainActor
final class LiveInspectionService: NSObject, ObservableObject {
    
    // MARK: Published state
    @Published var state: LiveSessionState = .idle
    @Published var transcript: [TranscriptEntry] = []
    @Published var isPlaying = false
    @Published var isMuted = false
    @Published var feedbackText: String = ""
    @Published var annotatedImage: UIImage?
    @Published var matchedErrorCodes: [[String: String]] = []
    
    // MARK: Config
    private let geminiAPIKey = AppRuntimeConfig.string("GEMINI_API_KEY")
    private let model = AppRuntimeConfig.string("GEMINI_LIVE_MODEL", default: "gemini-2.5-flash-native-audio-preview-12-2025")
    private let voiceName = "Charon"
    
    var taskId: Int = 1
    var inspectionId: Int = 5
    var equipmentId: String = "CAT-320-002"
    var equipmentModel: String = "CAT 320 Excavator"
    
    weak var cameraDelegate: LiveInspectionCameraDelegate?
    
    // MARK: Internal
    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private let audioEngine = AVAudioEngine()
    private let audioPlayer = AVAudioPlayerNode()
    private var playerFormat: AVAudioFormat?
    private let audioLock = NSLock()
    private var aiBufferCount = 0
    private var _isMutedAtomic = false
    
    /// Last inspection result for report/order/edit
    private var lastInspectionResult: [String: Any]?
    
    /// Last captured photo for bounding box annotations
    private var lastCapturedImageData: Data?
    
    /// Error code database loaded from error_data.json
    private var errorDatabase: [[String: Any]] = []
    
    /// Network service
    private let network = InspectionNetworkService.shared
    
    // MARK: - Lifecycle
    
    func connect() {
        guard state == .idle || state.isError else { return }
        state = .connecting
        loadErrorDatabase()
        
        Task {
            do {
                try await setupAudioSession()
                try await openWebSocket()
                try await sendSetup()
                startMicStream()
                state = .connected
                addTranscript(.system("Connected — speak to begin inspection"))
                receiveLoop()
            } catch {
                state = .error(error.localizedDescription)
                addTranscript(.system("Connection failed: \(error.localizedDescription)"))
            }
        }
    }
    
    func disconnect() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        state = .idle
        audioStreamContinuation?.finish()
        audioLock.lock()
        aiBufferCount = 0
        audioLock.unlock()
        addTranscript(.system("Disconnected"))
    }
    
    func toggleMute() {
        isMuted.toggle()
        audioLock.lock()
        _isMutedAtomic = isMuted
        audioLock.unlock()
    }
    
    // MARK: - Audio session
    
    private func setupAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setPreferredSampleRate(16000)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }
    
    // MARK: - WebSocket
    
    private func openWebSocket() async throws {
        let key = geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw LiveError.missingConfig("GEMINI_API_KEY")
        }
        let wsURL = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=\(key)"
        guard let url = URL(string: wsURL) else {
            throw LiveError.invalidURL
        }
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = 600
        urlSession = URLSession(configuration: config)
        webSocket = urlSession?.webSocketTask(with: url)
        webSocket?.resume()
    }

    // MARK: - Setup message
    
    private func sendSetup() async throws {
        let setup: [String: Any] = [
            "setup": [
                "model": "models/\(model)",
                "generation_config": [
                    "response_modalities": ["AUDIO"],
                    "speech_config": [
                        "voice_config": [
                            "prebuilt_voice_config": [
                                "voice_name": voiceName
                            ]
                        ]
                    ]
                ],
                "system_instruction": [
                    "parts": [
                        ["text": systemPrompt]
                    ]
                ],
                "tools": [toolDeclarations]
            ]
        ]
        
        let data = try JSONSerialization.data(withJSONObject: setup)
        try await webSocket?.send(.data(data))
        
        // Wait for setup complete
        let msg = try await webSocket?.receive()
        if case .data(let d) = msg {
            print("[WS] Setup response: \(String(data: d, encoding: .utf8)?.prefix(200) ?? "?")")
        } else if case .string(let s) = msg {
            print("[WS] Setup response: \(s.prefix(200))")
        }
    }
    
    // MARK: - Mic streaming
    
    private var audioStreamContinuation: AsyncStream<Data>.Continuation?

    private func startMicStream() {
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // Target: PCM 16-bit, 16kHz, mono
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: true
        ) else {
            state = .error("Cannot create audio format")
            return
        }
        
        guard let converter = AVAudioConverter(from: recordingFormat, to: targetFormat) else {
            state = .error("Cannot create audio converter")
            return
        }
        
        // Setup audio player for Cat AI responses (24kHz PCM16 mono)
        playerFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 24000,
            channels: 1,
            interleaved: true
        )
        audioEngine.attach(audioPlayer)
        if let pf = playerFormat {
            audioEngine.connect(audioPlayer, to: audioEngine.mainMixerNode, format: pf)
        }
        
        // Create a stream to serialize WebSocket sends
        let stream = AsyncStream<Data> { continuation in
            self.audioStreamContinuation = continuation
        }
        
        Task {
            for await data in stream {
                try? await sendAudioChunk(data)
            }
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self else { return }
            
            self.audioLock.lock()
            let suppress = self.aiBufferCount > 0 || self._isMutedAtomic
            self.audioLock.unlock()
            
            if suppress { return }
            
            let frameCount = AVAudioFrameCount(
                Double(buffer.frameLength) * 16000.0 / recordingFormat.sampleRate
            )
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else { return }
            
            var error: NSError?
            let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            
            guard status != .error, error == nil else { return }
            
            // Send raw PCM bytes
            let byteCount = Int(convertedBuffer.frameLength) * 2 // 16-bit = 2 bytes per sample
            guard let channelData = convertedBuffer.int16ChannelData else { return }
            let data = Data(bytes: channelData[0], count: byteCount)
            
            self.audioStreamContinuation?.yield(data)
        }
        
        do {
            try audioEngine.start()
        } catch {
            state = .error("Mic start failed: \(error.localizedDescription)")
        }
    }

    private func sendAudioChunk(_ data: Data) async throws {
        let base64Audio = data.base64EncodedString()
        let msg: [String: Any] = [
            "realtime_input": [
                "media_chunks": [
                    [
                        "data": base64Audio,
                        "mime_type": "audio/pcm;rate=16000"
                    ]
                ]
            ]
        ]
        let jsonData = try JSONSerialization.data(withJSONObject: msg)
        try await webSocket?.send(.data(jsonData))
    }
    
    // MARK: - Receive loop
    
    private func receiveLoop() {
        Task { [weak self] in
            guard let self else { return }
            
            while self.webSocket != nil {
                do {
                    guard let msg = try await self.webSocket?.receive() else { break }
                    
                    let data: Data
                    switch msg {
                    case .data(let d): data = d
                    case .string(let s): data = s.data(using: .utf8) ?? Data()
                    @unknown default: continue
                    }
                    
                    await self.handleServerMessage(data)
                    
                } catch {
                    if self.webSocket != nil {
                        await MainActor.run {
                            self.state = .error("Connection lost")
                            self.addTranscript(.system("Connection lost: \(error.localizedDescription)"))
                        }
                    }
                    break
                }
            }
        }
    }
    
    // MARK: - Handle server messages
    
    private func handleServerMessage(_ data: Data) async {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        
        let serverContent = json["serverContent"] as? [String: Any]
        let toolCall = json["toolCall"] as? [String: Any]
        
        // Handle audio response
        if let modelTurn = serverContent?["modelTurn"] as? [String: Any],
           let parts = modelTurn["parts"] as? [[String: Any]] {
            for part in parts {
                if let inlineData = part["inlineData"] as? [String: String],
                   let b64 = inlineData["data"],
                   let audioData = Data(base64Encoded: b64) {
                    playAudio(audioData)
                }
            }
        }
        
        // Handle turn complete
        if let turnComplete = serverContent?["turnComplete"] as? Bool, turnComplete {
            print("[WS] Turn complete")
        }
        
        // Handle tool calls
        if let functionCalls = toolCall?["functionCalls"] as? [[String: Any]] {
            for fc in functionCalls {
                guard let name = fc["name"] as? String,
                      let args = fc["args"] as? [String: Any],
                      let callId = fc["id"] as? String else { continue }
                
                await handleToolCall(name: name, args: args, callId: callId)
            }
        }
    }
    
    // MARK: - Audio playback
    
    private func playAudio(_ pcmData: Data) {
        guard let format = playerFormat else { return }
        
        let frameCount = UInt32(pcmData.count / 2) // 16-bit samples
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount
        
        pcmData.withUnsafeBytes { rawBuf in
            if let src = rawBuf.baseAddress, let dst = buffer.int16ChannelData?[0] {
                memcpy(dst, src, pcmData.count)
            }
        }
        
        if !audioPlayer.isPlaying {
            audioPlayer.play()
        }

        audioLock.lock()
        aiBufferCount += 1
        audioLock.unlock()
        
        Task { @MainActor in isPlaying = true }
        
        audioPlayer.scheduleBuffer(buffer) { [weak self] in
            guard let self else { return }
            self.audioLock.lock()
            self.aiBufferCount -= 1
            let count = self.aiBufferCount
            self.audioLock.unlock()
            if count == 0 {
                Task { @MainActor in self.isPlaying = false }
            }
        }
    }
    
    // MARK: - Tool call handler
    
    private func handleToolCall(name: String, args: [String: Any], callId: String) async {
        state = .runningTool(name)
        addTranscript(.system("Running tool: \(name)"))
        
        let result: [String: Any]
        
        switch name {
        case "take_photo":
            result = await executeTakePhoto(args: args)
        case "run_inspection":
            result = await executeRunInspection(args: args)
        case "report_anomalies":
            result = await executeReportAnomalies(args: args)
        case "order_parts":
            result = await executeOrderParts(args: args)
        case "edit_findings":
            result = executeEditFindings(args: args)
        case "write_feedback":
            result = executeWriteFeedback(args: args)
        case "lookup_error_codes":
            result = executeLookupErrorCodes(args: args)
        default:
            result = ["error": "Unknown tool: \(name)"]
        }
        
        // Send tool response
        await sendToolResponse(callId: callId, name: name, result: result)
        state = .connected
    }
    
    private func sendToolResponse(callId: String, name: String, result: [String: Any]) async {
        let response: [String: Any] = [
            "tool_response": [
                "function_responses": [
                    [
                        "id": callId,
                        "name": name,
                        "response": result
                    ]
                ]
            ]
        ]
        
        guard let data = try? JSONSerialization.data(withJSONObject: response) else { return }
        try? await webSocket?.send(.data(data))
    }
    
    // MARK: - Tool: take_photo
    
    private func executeTakePhoto(args: [String: Any]) async -> [String: Any] {
        guard let delegate = cameraDelegate else {
            return ["error": "Camera not available"]
        }
        
        addTranscript(.system("Capturing photo…"))
        
        do {
            let imageData = try await delegate.capturePhotoData()
            lastCapturedImageData = imageData
            addTranscript(.system("Photo captured (\(imageData.count / 1024)KB)"))
            
            // Now immediately run inspection with the captured image
            let voiceText = args["voice_text"] as? String ?? "Inspector requested photo capture for visual inspection"
            return await callModalInspect(imageData: imageData, voiceText: voiceText)
        } catch {
            return ["error": "Photo capture failed: \(error.localizedDescription)"]
        }
    }
    
    // MARK: - Tool: run_inspection
    
    private func executeRunInspection(args: [String: Any]) async -> [String: Any] {
        let voiceText = args["voice_text"] as? String ?? ""
        
        // If we have a camera delegate, capture a live photo
        if let delegate = cameraDelegate {
            do {
                let imageData = try await delegate.capturePhotoData()
                lastCapturedImageData = imageData
                addTranscript(.system("Photo captured for inspection"))
                return await callModalInspect(imageData: imageData, voiceText: voiceText)
            } catch {
                return ["error": "Camera capture failed: \(error.localizedDescription)"]
            }
        }
        
        return ["error": "No camera available for inspection"]
    }
    
    // Shared: Call Modal /inspect
    private func callModalInspect(imageData: Data, voiceText: String) async -> [String: Any] {
        addTranscript(.system("Sending to AI vision (30-60s)…"))
        
        do {
            let response = try await network.runInspection(
                imageData: imageData,
                voiceText: voiceText,
                equipmentId: equipmentId,
                equipmentModel: equipmentModel
            )
            
            // Store full result for later report/order tools
            let fullDict = encodeToDictionary(response)
            lastInspectionResult = fullDict
            
            // Draw bounding boxes on the captured image
            drawBoundingBoxes(on: imageData, anomalies: fullDict["anomalies"] as? [[String: Any]] ?? [])
            
            // Auto-lookup error codes for the detected anomalies
            autoMatchErrorCodes(from: fullDict)
            
            // Trim for speech (< 2KB)
            let trimmed = trimForSpeech(fullDict)
            
            let anomalyCount = (fullDict["anomalies"] as? [[String: Any]])?.count ?? 0
            addTranscript(.system("Inspection complete: \(anomalyCount) findings"))
            
            return trimmed
            
        } catch {
            return ["error": "Inspection failed: \(error.localizedDescription)"]
        }
    }
    
    // MARK: - Tool: report_anomalies
    
    private func executeReportAnomalies(args: [String: Any]) async -> [String: Any] {
        let confirmed = args["confirmed"] as? Bool ?? false
        if !confirmed {
            return ["status": "skipped", "message": "Inspector declined to report"]
        }
        
        guard let result = lastInspectionResult else {
            return ["error": "No inspection results available. Run an inspection first."]
        }
        
        let anomalies = result["anomalies"] as? [[String: Any]] ?? []
        let overallStatus = result["overall_status"] as? String ?? "monitor"
        let operationalImpact = result["operational_impact"] as? String ?? ""
        
        addTranscript(.system("Saving \(anomalies.count) findings…"))
        
        // Convert to AnyCodableValue dicts
        let codableAnomalies = anomalies.map { convertToCodableDict($0) }
        
        do {
            let resp = try await network.reportAnomalies(
                taskId: taskId,
                inspectionId: inspectionId,
                overallStatus: overallStatus,
                operationalImpact: operationalImpact,
                anomalies: codableAnomalies
            )
            
            addTranscript(.system("Findings saved: \(resp.anomaliesCount) anomalies"))
            return [
                "task_updated": resp.taskUpdated,
                "anomalies_count": resp.anomaliesCount,
                "error": resp.error
            ]
        } catch {
            return ["error": "Report failed: \(error.localizedDescription)"]
        }
    }
    
    // MARK: - Tool: order_parts
    
    private func executeOrderParts(args: [String: Any]) async -> [String: Any] {
        let confirmed = args["confirmed"] as? Bool ?? false
        if !confirmed {
            return ["status": "skipped", "message": "Inspector declined to order parts"]
        }
        
        guard let result = lastInspectionResult else {
            return ["error": "No inspection results. Run an inspection first."]
        }
        
        let parts = result["parts"] as? [[String: Any]] ?? []
        addTranscript(.system("Ordering \(parts.count) parts…"))
        
        let codableParts = parts.map { convertToCodableDict($0) }
        
        do {
            let resp = try await network.orderParts(
                inspectionId: inspectionId,
                parts: codableParts
            )
            
            addTranscript(.system("Orders created: \(resp.ordersCreated)"))
            return [
                "orders_created": resp.ordersCreated,
                "details": resp.details,
                "errors": resp.errors
            ]
        } catch {
            return ["error": "Order failed: \(error.localizedDescription)"]
        }
    }
    
    // MARK: - Tool: edit_findings
    
    private func executeEditFindings(args: [String: Any]) -> [String: Any] {
        guard var result = lastInspectionResult else {
            return ["error": "No inspection results to edit."]
        }
        
        var anomalies = result["anomalies"] as? [[String: Any]] ?? []
        let action = args["action"] as? String ?? "update"
        let findingNumber = (args["finding_number"] as? Int ?? 0)
        let idx = findingNumber - 1  // 1-based → 0-based
        
        guard idx >= 0 && idx < anomalies.count else {
            return ["error": "Finding #\(findingNumber) does not exist. There are \(anomalies.count) findings."]
        }
        
        if action == "remove" {
            let removed = anomalies.remove(at: idx)
            result["anomalies"] = anomalies
            lastInspectionResult = result
            refreshParts()
            
            return [
                "status": "removed",
                "removed": removed["issue"] as? String ?? "",
                "remaining_findings": anomalies.enumerated().map { "#\($0.offset+1) \($0.element["severity"] as? String ?? "?"): \($0.element["issue"] as? String ?? "?")" }
            ]
        } else if action == "update" {
            var finding = anomalies[idx]
            var changes: [String] = []
            
            if let newIssue = args["new_issue"] as? String, !newIssue.isEmpty {
                let old = finding["issue"] as? String ?? ""
                finding["issue"] = newIssue
                changes.append("issue: '\(old)' → '\(newIssue)'")
            }
            if let newSev = args["new_severity"] as? String, !newSev.isEmpty {
                let old = finding["severity"] as? String ?? ""
                finding["severity"] = newSev
                changes.append("severity: '\(old)' → '\(newSev)'")
            }
            if let newDesc = args["new_description"] as? String, !newDesc.isEmpty {
                finding["description"] = newDesc
                changes.append("description updated")
            }
            
            anomalies[idx] = finding
            result["anomalies"] = anomalies
            lastInspectionResult = result
            refreshParts()
            
            addTranscript(.system("Edited finding #\(findingNumber): \(changes.joined(separator: ", "))"))
            
            return [
                "status": "updated",
                "changes": changes,
                "updated_findings": anomalies.enumerated().map { "#\($0.offset+1) \($0.element["severity"] as? String ?? "?"): \($0.element["issue"] as? String ?? "?")" }
            ]
        }
        
        return ["error": "Unknown action: \(action). Use 'update' or 'remove'."]
    }
    
    private func refreshParts() {
        guard var result = lastInspectionResult else { return }
        let anomalies = result["anomalies"] as? [[String: Any]] ?? []
        let anomalyComponents = Set(anomalies.compactMap { $0["component"] as? String })
        let originalParts = result["parts"] as? [[String: Any]] ?? []
        let filtered = originalParts.filter { anomalyComponents.contains($0["component_tag"] as? String ?? "") }
        result["parts"] = filtered
        lastInspectionResult = result
    }
    
    // MARK: - Tool: write_feedback
    
    private func executeWriteFeedback(args: [String: Any]) -> [String: Any] {
        let text = args["feedback_text"] as? String ?? ""
        guard !text.isEmpty else {
            return ["error": "No feedback text provided"]
        }
        feedbackText = text
        addTranscript(.system("Feedback: \(text.prefix(100))"))
        return ["status": "written", "feedback": text]
    }
    
    // MARK: - Tool: lookup_error_codes
    
    private func executeLookupErrorCodes(args: [String: Any]) -> [String: Any] {
        let query = (args["query"] as? String ?? "").lowercased()
        let component = (args["component"] as? String ?? "").lowercased()
        
        guard !query.isEmpty || !component.isEmpty else {
            return ["error": "Provide a query or component to search error codes"]
        }
        
        let queryWords = Set(query.split(separator: " ").map { String($0) }.filter { $0.count >= 3 })
        let componentWords = Set(component.split(separator: " ").map { String($0) }.filter { $0.count >= 2 })
        
        var scored: [(entry: [String: Any], score: Int)] = []
        
        for entry in errorDatabase {
            let entryComponent = (entry["component"] as? String ?? "").lowercased()
            let entryDescription = (entry["description"] as? String ?? "").lowercased()
            let entryKeywords = (entry["keywords"] as? [String] ?? []).map { $0.lowercased() }
            var score = 0
            
            // Exact component match
            if !component.isEmpty && entryComponent.contains(component) {
                score += 10
            }
            // Component word overlap
            for w in componentWords {
                if entryComponent.contains(w) { score += 5 }
            }
            // Query keywords vs entry keywords
            for keyword in entryKeywords {
                if query.contains(keyword) { score += 8 }
                for w in queryWords {
                    if keyword.contains(w) { score += 4 }
                }
            }
            // Query words in description
            for w in queryWords {
                if entryDescription.contains(w) { score += 3 }
            }
            
            if score > 0 {
                scored.append((entry: entry, score: score))
            }
        }
        
        scored.sort { $0.score > $1.score }
        let topMatches = scored.prefix(5).map { item -> [String: String] in
            [
                "code": item.entry["code"] as? String ?? "",
                "description": item.entry["description"] as? String ?? "",
                "component": item.entry["component"] as? String ?? "",
                "severity": item.entry["severity"] as? String ?? ""
            ]
        }
        
        matchedErrorCodes = topMatches
        
        if topMatches.isEmpty {
            return ["matches": 0, "message": "No matching error codes found"]
        }
        
        return [
            "matches": topMatches.count,
            "error_codes": topMatches.map { "\($0["code"] ?? ""): \($0["description"] ?? "")" }
        ]
    }
    
    // MARK: - Bounding box drawing
    
    private func drawBoundingBoxes(on imageData: Data, anomalies: [[String: Any]]) {
        guard let originalImage = UIImage(data: imageData), !anomalies.isEmpty else {
            annotatedImage = nil
            return
        }
        
        let size = originalImage.size
        let renderer = UIGraphicsImageRenderer(size: size)
        
        let result = renderer.image { context in
            originalImage.draw(at: .zero)
            let ctx = context.cgContext
            
            let colors: [String: UIColor] = [
                "fail": .systemRed,
                "critical": .systemRed,
                "monitor": .systemOrange,
                "normal": .systemGreen,
                "pass": .systemGreen
            ]
            
            let count = anomalies.count
            let boxHeight = size.height / CGFloat(count + 1)
            
            for (index, anomaly) in anomalies.enumerated() {
                let severity = (anomaly["severity"] as? String ?? "monitor").lowercased()
                let issue = anomaly["issue"] as? String ?? "Issue \(index + 1)"
                let color = colors[severity] ?? .systemYellow
                
                // If the anomaly has bounding_box data, use it; otherwise distribute evenly
                let rect: CGRect
                if let bbox = anomaly["bounding_box"] as? [String: Any] {
                    let x = CGFloat(bbox["x"] as? Double ?? 0)
                    let y = CGFloat(bbox["y"] as? Double ?? 0)
                    let w = CGFloat(bbox["width"] as? Double ?? Double(size.width * 0.6))
                    let h = CGFloat(bbox["height"] as? Double ?? Double(boxHeight))
                    rect = CGRect(x: x, y: y, width: w, height: h)
                } else {
                    // Distribute boxes vertically across the image
                    let margin = size.width * 0.05
                    let y = margin + CGFloat(index) * (boxHeight + 10)
                    rect = CGRect(
                        x: margin,
                        y: y,
                        width: size.width - margin * 2,
                        height: boxHeight * 0.8
                    )
                }
                
                // Draw border rectangle
                ctx.setStrokeColor(color.cgColor)
                ctx.setLineWidth(max(3, size.width * 0.005))
                ctx.stroke(rect)
                
                // Draw label background
                let labelHeight: CGFloat = max(24, size.height * 0.035)
                let labelRect = CGRect(
                    x: rect.origin.x,
                    y: max(0, rect.origin.y - labelHeight),
                    width: rect.width,
                    height: labelHeight
                )
                ctx.setFillColor(color.withAlphaComponent(0.85).cgColor)
                ctx.fill(labelRect)
                
                // Draw label text
                let label = "#\(index + 1) \(severity.uppercased()): \(issue)"
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: max(14, size.height * 0.02)),
                    .foregroundColor: UIColor.white
                ]
                let nsLabel = label as NSString
                nsLabel.draw(
                    in: labelRect.insetBy(dx: 4, dy: 2),
                    withAttributes: attrs
                )
            }
        }
        
        annotatedImage = result
        addTranscript(.system("Annotated image with \(anomalies.count) bounding boxes"))
    }
    
    // MARK: - Auto-match error codes from inspection results
    
    private func autoMatchErrorCodes(from result: [String: Any]) {
        let anomalies = result["anomalies"] as? [[String: Any]] ?? []
        guard !anomalies.isEmpty, !errorDatabase.isEmpty else {
            matchedErrorCodes = []
            return
        }
        
        var allMatches: [[String: String]] = []
        
        for anomaly in anomalies {
            let issue = (anomaly["issue"] as? String ?? "").lowercased()
            let component = (anomaly["component"] as? String ?? "").lowercased()
            let description = (anomaly["description"] as? String ?? "").lowercased()
            let combinedText = "\(issue) \(component) \(description)"
            let words = Set(combinedText.split(separator: " ").map { String($0) }.filter { $0.count >= 3 })
            
            var bestScore = 0
            var bestEntry: [String: Any]?
            
            for entry in errorDatabase {
                let entryComponent = (entry["component"] as? String ?? "").lowercased()
                let entryKeywords = (entry["keywords"] as? [String] ?? []).map { $0.lowercased() }
                var score = 0
                
                if entryComponent.contains(component) || component.contains(entryComponent) {
                    score += 10
                }
                for keyword in entryKeywords {
                    for w in words {
                        if keyword.contains(w) || w.contains(keyword) { score += 4 }
                    }
                    if combinedText.contains(keyword) { score += 6 }
                }
                
                if score > bestScore {
                    bestScore = score
                    bestEntry = entry
                }
            }
            
            if bestScore >= 8, let entry = bestEntry {
                allMatches.append([
                    "code": entry["code"] as? String ?? "",
                    "description": entry["description"] as? String ?? "",
                    "component": entry["component"] as? String ?? "",
                    "severity": entry["severity"] as? String ?? "",
                    "matched_issue": anomaly["issue"] as? String ?? ""
                ])
            }
        }
        
        matchedErrorCodes = allMatches
        if !allMatches.isEmpty {
            addTranscript(.system("Matched \(allMatches.count) error code(s) from database"))
        }
    }
    
    // MARK: - Error database loading
    
    private func loadErrorDatabase() {
        guard let url = Bundle.main.url(forResource: "error_data", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let errors = json["errors"] as? [[String: Any]] else {
            print("[ErrorDB] Could not load error_data.json from bundle")
            return
        }
        
        errorDatabase = errors.map { entry in
            [
                "code": entry["error_code"] as? String ?? "",
                "description": entry["error_description"] as? String ?? "",
                "component": entry["component"] as? String ?? "",
                "severity": entry["severity"] as? String ?? "",
                "keywords": entry["keywords"] as? [String] ?? []
            ]
        }
        print("[ErrorDB] Loaded \(errorDatabase.count) error codes")
    }
    
    // MARK: - Trim for speech (< 2KB, numbered findings)
    
    private func trimForSpeech(_ result: [String: Any]) -> [String: Any] {
        var trimmed: [String: Any] = [
            "overall_status": result["overall_status"] as? String ?? "",
            "component_identified": result["component_identified"] as? String ?? "",
        ]
        
        if let impact = result["operational_impact"] as? String {
            // Truncate long descriptions
            trimmed["operational_impact"] = String(impact.prefix(120))
        }
        
        if let anomalies = result["anomalies"] as? [[String: Any]] {
            let numbered: [[String: Any]] = anomalies.enumerated().map { idx, a in
                [
                    "number": idx + 1,
                    "severity": a["severity"] as? String ?? "?",
                    "issue": String((a["issue"] as? String ?? "?").prefix(80)),
                ]
            }
            trimmed["findings"] = numbered
        }
        
        if let parts = result["parts"] as? [[String: Any]] {
            trimmed["parts_needed"] = parts.prefix(5).map { p in
                [
                    "part_name": p["part_name"] as? String ?? "?",
                    "urgency": p["urgency"] as? String ?? "?"
                ]
            }
        }
        
        return trimmed
    }
    
    // MARK: - Helpers
    
    private func convertToCodableDict(_ dict: [String: Any]) -> [String: AnyCodableValue] {
        var result: [String: AnyCodableValue] = [:]
        for (key, value) in dict {
            if let s = value as? String { result[key] = .string(s) }
            else if let i = value as? Int { result[key] = .int(i) }
            else if let d = value as? Double { result[key] = .double(d) }
            else if let b = value as? Bool { result[key] = .bool(b) }
            else { result[key] = .string(String(describing: value)) }
        }
        return result
    }
    
    private func encodeToDictionary(_ response: InspectResponse) -> [String: Any] {
        var dict: [String: Any] = [:]
        dict["component_identified"] = response.componentIdentified
        dict["component_route"] = response.componentRoute
        dict["overall_status"] = response.overallStatus
        dict["operational_impact"] = response.operationalImpact
        dict["inspection_id"] = response.inspectionId
        dict["task_id"] = response.taskId
        dict["machine"] = response.machine
        dict["flagged_for_review"] = response.flaggedForReview
        
        if let anomalies = response.anomalies {
            dict["anomalies"] = anomalies.map { anomaly in
                var d: [String: Any] = [:]
                for (k, v) in anomaly { d[k] = v.stringValue }
                return d
            }
        }
        if let parts = response.parts {
            dict["parts"] = parts.map { part in
                var d: [String: Any] = [:]
                for (k, v) in part { d[k] = v.stringValue }
                return d
            }
        }
        return dict
    }
    
    private func addTranscript(_ entry: TranscriptEntry) {
        transcript.append(entry)
        // Keep last 50
        if transcript.count > 50 {
            transcript.removeFirst(transcript.count - 50)
        }
    }
    
    // MARK: - System prompt
    
    private var systemPrompt: String {
        """
        You are Cat, an AI inspection assistant for CAT heavy equipment on the inspector's mobile device.
        The inspector calls you "Hey Cat" — respond to that naturally.
        
        INSPECTION FLOW:
        1. When the user describes damage or asks to inspect something, call take_photo to capture \
        from the device camera and analyze it. The photo is sent to an AI vision model on GPU. \
        Tell the user "Taking a photo and running the inspection now, this will take about 30 seconds" \
        and WAIT patiently for the tool response. Do NOT call the tool again.
        
        2. After getting inspection results, read each finding with its NUMBER, severity, and issue. \
        Example: "Finding 1: FAIL — severe rim corrosion. Finding 2: MONITOR — missing lug nut." \
        Then call lookup_error_codes for each significant finding to identify matching CAT diagnostic codes. \
        After that, ask: "Would you like to correct or remove any findings before I save them?"
        
        3. If the inspector wants to change something, call edit_findings for each change. \
        After editing, read back the updated findings and ask again if they look correct.
        
        4. When the inspector confirms the findings are correct, ask: \
        "Should I save these findings to the task database?" \
        If yes, call report_anomalies with confirmed=true.
        
        5. After reporting, tell the user what parts are needed and ask: \
        "Should I check inventory and order replacement parts?" \
        If yes, call order_parts with confirmed=true.
        
        6. Use write_feedback to display important summaries or action items on the inspector's screen.
        
        7. Use lookup_error_codes whenever the inspector asks about error codes, diagnostic trouble \
        codes, or when you want to match detected anomalies to known CAT CID codes.
        
        Keep responses short and clear. You are speaking through a phone speaker.
        Current equipment: \(equipmentId), task_id=\(taskId), inspection_id=\(inspectionId).
        """
    }
    
    // MARK: - Tool declarations (JSON for Cat AI)
    
    private var toolDeclarations: [String: Any] {
        [
            "function_declarations": [
                [
                    "name": "take_photo",
                    "description": "Capture a photo from the device camera and run AI inspection on it. Call this when the inspector asks to take a photo or wants to inspect a component.",
                    "parameters": [
                        "type": "OBJECT",
                        "properties": [
                            "voice_text": [
                                "type": "STRING",
                                "description": "What the inspector said about the damage or component"
                            ]
                        ],
                        "required": ["voice_text"]
                    ]
                ],
                [
                    "name": "run_inspection",
                    "description": "Run an AI inspection using the device camera. Call this when the user describes damage or asks to inspect something.",
                    "parameters": [
                        "type": "OBJECT",
                        "properties": [
                            "voice_text": [
                                "type": "STRING",
                                "description": "What the inspector said about the damage"
                            ]
                        ],
                        "required": ["voice_text"]
                    ]
                ],
                [
                    "name": "report_anomalies",
                    "description": "Save the inspection findings to the task database. Call AFTER run_inspection when the inspector confirms.",
                    "parameters": [
                        "type": "OBJECT",
                        "properties": [
                            "confirmed": [
                                "type": "BOOLEAN",
                                "description": "True if the inspector confirmed reporting"
                            ]
                        ],
                        "required": ["confirmed"]
                    ]
                ],
                [
                    "name": "edit_findings",
                    "description": "Modify an inspection finding. Use when the inspector wants to correct, change severity, or remove a finding.",
                    "parameters": [
                        "type": "OBJECT",
                        "properties": [
                            "action": [
                                "type": "STRING",
                                "description": "'update' to change a finding, 'remove' to delete it"
                            ],
                            "finding_number": [
                                "type": "INTEGER",
                                "description": "Which finding to edit (1, 2, 3, etc.)"
                            ],
                            "new_issue": [
                                "type": "STRING",
                                "description": "New issue text (for update action)"
                            ],
                            "new_severity": [
                                "type": "STRING",
                                "description": "New severity: fail, monitor, normal, or pass"
                            ],
                            "new_description": [
                                "type": "STRING",
                                "description": "New description text (for update action)"
                            ]
                        ],
                        "required": ["action", "finding_number"]
                    ]
                ],
                [
                    "name": "order_parts",
                    "description": "Check inventory and order replacement parts. Call AFTER report_anomalies when the inspector confirms.",
                    "parameters": [
                        "type": "OBJECT",
                        "properties": [
                            "confirmed": [
                                "type": "BOOLEAN",
                                "description": "True if the inspector confirmed ordering parts"
                            ]
                        ],
                        "required": ["confirmed"]
                    ]
                ],
                [
                    "name": "write_feedback",
                    "description": "Write a feedback summary or note to the inspector's screen. Use this to display important findings, recommendations, or action items as text on the device.",
                    "parameters": [
                        "type": "OBJECT",
                        "properties": [
                            "feedback_text": [
                                "type": "STRING",
                                "description": "The text to display as feedback on the inspector's device"
                            ]
                        ],
                        "required": ["feedback_text"]
                    ]
                ],
                [
                    "name": "lookup_error_codes",
                    "description": "Search the CAT error code database for diagnostic trouble codes matching the detected issues. Use this after inspection to find relevant CID/FMI codes for the anomalies found.",
                    "parameters": [
                        "type": "OBJECT",
                        "properties": [
                            "query": [
                                "type": "STRING",
                                "description": "Description of the issue to look up (e.g. 'hydraulic pressure low', 'engine oil leak')"
                            ],
                            "component": [
                                "type": "STRING",
                                "description": "Component name to filter (e.g. 'hydraulic system', 'engine', 'fuel system')"
                            ]
                        ],
                        "required": ["query"]
                    ]
                ]
            ]
        ]
    }
}

// MARK: - Error

private extension LiveSessionState {
    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}

enum LiveError: LocalizedError {
    case invalidURL
    case setupFailed(String)
    case missingConfig(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid WebSocket URL"
        case .setupFailed(let s): return "Setup failed: \(s)"
        case .missingConfig(let key): return "Missing config: \(key)"
        }
    }
}

// MARK: - Transcript model

struct TranscriptEntry: Identifiable {
    let id = UUID()
    let timestamp = Date()
    let type: EntryType
    let text: String
    
    enum EntryType {
        case system, user, assistant
    }
    
    static func system(_ text: String) -> TranscriptEntry {
        TranscriptEntry(type: .system, text: text)
    }
}
