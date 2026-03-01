//
//  RelayLiveInspectionService.swift
//  CAT Inspect
//
//  Orchestrates the full Gemini Live relay session:
//
//    [WakeWordManager] ──trigger──▶ [AudioEngineManager] + [GeminiRelayClient]
//         ▲                              │ mic PCM           │ WS frames
//         │ passive listen               ▼                   ▼
//                              FastAPI /ws/live ◀────▶ Gemini Live API
//
//  This replaces the direct-to-Google WebSocket in LiveInspectionService
//  with a two-hop relay through our FastAPI server.
//
//  State machine:
//    .idle → .passiveListening → .connecting → .connected → .runningTool → .connected
//                                                                            │
//                                                                  .idle (disconnect)
//

import AVFoundation
import Combine
import Foundation
import UIKit

// MARK: - Session State (reuses LiveSessionState from LiveInspectionService)

// LiveSessionState, TranscriptEntry, LiveError already declared in LiveInspectionService.swift.
// If you want to use RelayLiveInspectionService as a full replacement, move those types to a
// shared file. For now we define relay-specific aliases.

enum RelaySessionState: Equatable {
    case idle
    case passiveListening   // Mic on, wake-word detector active
    case connecting         // WebSocket handshake in progress
    case connected          // Full duplex active
    case runningTool(String)
    case error(String)

    var label: String {
        switch self {
        case .idle:                return "Tap to start"
        case .passiveListening:    return "Say \"Hey Cat\"…"
        case .connecting:          return "Connecting…"
        case .connected:           return "Listening"
        case .runningTool(let t):  return "Running \(t)…"
        case .error(let e):        return "Error: \(e.prefix(60))"
        }
    }

    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}

// MARK: - RelayLiveInspectionService

@MainActor
final class RelayLiveInspectionService: NSObject, ObservableObject {

    // MARK: Published
    @Published var state: RelaySessionState = .idle
    @Published var transcript: [TranscriptEntry] = []
    @Published var isPlaying = false
    @Published var isMuted = false
    @Published var inputLevel: Float = 0

    // MARK: Equipment context (set by the view before connecting)
    var taskId: Int = 1
    var inspectionId: Int = 5
    var equipmentId: String = "CAT-320-002"
    var equipmentModel: String = "CAT 320 Excavator"

    // MARK: Camera delegate
    weak var cameraDelegate: LiveInspectionCameraDelegate?

    // MARK: Sub-managers
    let audioEngine = AudioEngineManager()
    private let relayClient = GeminiRelayClient()
    private let wakeWord = WakeWordManager()

    // MARK: Network service (for server-side tool execution)
    private let network = InspectionNetworkService.shared

    // MARK: Last inspection result (for report/order/edit tools)
    private var lastInspectionResult: [String: Any]?

    // MARK: Combine
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    override nonisolated init() {
        super.init()
    }

    // MARK: - Lifecycle

    /// Start passive listening (wake-word mode).
    /// Porcupine manages its own mic tap, so AudioEngineManager is NOT started here.
    /// This saves battery — only the lightweight wake-word detector runs.
    func startPassiveListening() {
        guard state == .idle else { return }
        state = .passiveListening

        // Wake word triggers full session
        wakeWord.onWakeWordDetected = { [weak self] in
            Task { @MainActor in
                self?.connect()
            }
        }
        wakeWord.startListening()

        addTranscript(.system("Listening for \"Hey Cat\"…"))
    }

    /// Full connect: open the relay WebSocket and start streaming.
    /// Stops Porcupine (releases mic), then starts AudioEngineManager.
    func connect() {
        guard state == .idle || state == .passiveListening || state.isError else { return }
        state = .connecting

        // Stop Porcupine first — it owns the mic during passive listening.
        // Must release before AudioEngineManager can install its tap.
        wakeWord.activateSession()

        // Start the audio engine (mic capture + playback source node)
        if !audioEngine.isCapturing {
            do {
                try audioEngine.startCapture()
            } catch {
                state = .error("Mic: \(error.localizedDescription)")
                return
            }
        }

        // Subscribe to relay events
        subscribeToRelayEvents()

        // Build system prompt with current equipment context
        let systemPrompt = buildSystemPrompt()

        // Open relay WebSocket to FastAPI /ws/live
        relayClient.connect(
            model: "gemini-2.5-flash-native-audio-preview-12-2025",
            voice: "Charon",
            systemPrompt: systemPrompt
        )

        // Wire mic audio → relay WebSocket
        audioEngine.onAudioCaptured = { [weak self] pcmData in
            guard let self else { return }
            self.relayClient.sendAudio(pcmData)
        }

        addTranscript(.system("Connecting to inspection assistant…"))
    }

    /// Disconnect everything and return to passive listening.
    func disconnect() {
        relayClient.disconnect()
        audioEngine.stopCapture()
        cancellables.removeAll()
        state = .idle
        addTranscript(.system("Disconnected"))

        // Resume Porcupine for next "Hey Cat" trigger
        wakeWord.deactivateSession()
    }

    /// Toggle microphone mute.
    func toggleMute() {
        isMuted.toggle()
        audioEngine.isMuted = isMuted
    }

    /// Send a captured image to Gemini for visual context.
    func sendVisualContext(_ jpegData: Data) {
        relayClient.sendImage(jpegData)
        addTranscript(.system("Sent photo to assistant"))
    }

    // MARK: - Relay Event Handling

    private func subscribeToRelayEvents() {
        cancellables.removeAll()

        relayClient.eventSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleRelayEvent(event)
            }
            .store(in: &cancellables)

        // Forward audio level from engine
        audioEngine.$inputLevel
            .receive(on: DispatchQueue.main)
            .assign(to: &$inputLevel)
    }

    private func handleRelayEvent(_ event: RelayEvent) {
        switch event {
        case .sessionReady(let model, let voice):
            state = .connected
            addTranscript(.system("Connected (model: \(model), voice: \(voice))"))

            // Capture and send initial visual context
            Task {
                if let delegate = cameraDelegate,
                   let imageData = try? await delegate.capturePhotoData() {
                    // Compress to 0.5 quality JPEG
                    if let compressed = UIImage(data: imageData)?.jpegData(compressionQuality: 0.5) {
                        relayClient.sendImage(compressed)
                        addTranscript(.system("Sent initial visual context"))
                    }
                }
            }

        case .audioChunk(let pcmData):
            // Feed raw PCM into the circular buffer → AVAudioSourceNode drains it
            audioEngine.enqueuePlaybackAudio(pcmData)
            isPlaying = pcmData.count > 0

        case .transcript(let text, let role):
            if role == "model" {
                addTranscript(TranscriptEntry(type: .assistant, text: text))
            } else {
                addTranscript(TranscriptEntry(type: .user, text: text))
            }

        case .toolCall(let functionCalls):
            for fc in functionCalls {
                guard let name = fc["name"] as? String,
                      let args = fc["args"] as? [String: Any],
                      let callId = fc["id"] as? String else { continue }
                Task {
                    await handleToolCall(name: name, args: args, callId: callId)
                }
            }

        case .turnComplete:
            isPlaying = false

        case .interrupted:
            // Barge-in: user started speaking while Gemini was playing.
            // Flush the playback buffer immediately.
            audioEngine.flushPlayback()
            isPlaying = false

        case .error(let message):
            state = .error(message)
            addTranscript(.system("Error: \(message)"))

        case .disconnected:
            if state != .idle {
                state = .error("Connection lost")
                addTranscript(.system("Connection lost"))
            }
        }
    }

    // MARK: - Tool Call Handling (client-side execution)

    private func handleToolCall(name: String, args: [String: Any], callId: String) async {
        state = .runningTool(name)
        addTranscript(.system("Running: \(name)"))

        let result: [String: Any]

        switch name {
        case "run_inspection":
            result = await executeRunInspection(args: args)
        case "report_anomalies":
            result = await executeReportAnomalies(args: args)
        case "order_parts":
            result = await executeOrderParts(args: args)
        case "edit_findings":
            result = executeEditFindings(args: args)
        default:
            result = ["error": "Unknown tool: \(name)"]
        }

        // Send tool response back through the relay → Gemini
        relayClient.sendToolResponse(callId: callId, name: name, result: result)
        state = .connected
    }

    // MARK: - Tool: take_photo

    private func executeTakePhoto(args: [String: Any]) async -> [String: Any] {
        guard let delegate = cameraDelegate else {
            return ["error": "Camera not available"]
        }

        addTranscript(.system("Capturing photo…"))

        do {
            let imageData = try await delegate.capturePhotoData()
            addTranscript(.system("Photo captured (\(imageData.count / 1024)KB)"))

            // Send image to Gemini for visual context
            if let compressed = UIImage(data: imageData)?.jpegData(compressionQuality: 0.5) {
                relayClient.sendImage(compressed)
            }

            // Also run inspection via Modal
            let voiceText = args["voice_text"] as? String ?? "Inspector requested photo capture"
            return await callModalInspect(imageData: imageData, voiceText: voiceText)
        } catch {
            return ["error": "Photo capture failed: \(error.localizedDescription)"]
        }
    }

    // MARK: - Tool: run_inspection

    private func executeRunInspection(args: [String: Any]) async -> [String: Any] {
        let voiceText = args["voice_text"] as? String ?? ""

        if let delegate = cameraDelegate {
            do {
                let imageData = try await delegate.capturePhotoData()
                addTranscript(.system("Photo captured for inspection"))
                return await callModalInspect(imageData: imageData, voiceText: voiceText)
            } catch {
                return ["error": "Camera capture failed: \(error.localizedDescription)"]
            }
        }

        return ["error": "No camera available for inspection"]
    }

    private func callModalInspect(imageData: Data, voiceText: String) async -> [String: Any] {
        addTranscript(.system("Sending to AI vision (30-60s)…"))

        do {
            let response = try await network.runInspection(
                imageData: imageData,
                voiceText: voiceText,
                equipmentId: equipmentId,
                equipmentModel: equipmentModel
            )

            let fullDict = encodeToDictionary(response)
            lastInspectionResult = fullDict

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
                "error": resp.error as Any,
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
                "errors": resp.errors,
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
        let idx = findingNumber - 1

        guard idx >= 0 && idx < anomalies.count else {
            return ["error": "Finding #\(findingNumber) does not exist. There are \(anomalies.count) findings."]
        }

        if action == "remove" {
            let removed = anomalies.remove(at: idx)
            result["anomalies"] = anomalies
            lastInspectionResult = result
            return [
                "status": "removed",
                "removed": removed["issue"] as? String ?? "",
                "remaining_findings": anomalies.enumerated().map {
                    "#\($0.offset+1) \($0.element["severity"] as? String ?? "?"): \($0.element["issue"] as? String ?? "?")"
                },
            ]
        } else if action == "update" {
            var finding = anomalies[idx]
            var changes: [String] = []

            if let newIssue = args["new_issue"] as? String, !newIssue.isEmpty {
                finding["issue"] = newIssue
                changes.append("issue updated")
            }
            if let newSev = args["new_severity"] as? String, !newSev.isEmpty {
                finding["severity"] = newSev
                changes.append("severity updated")
            }
            if let newDesc = args["new_description"] as? String, !newDesc.isEmpty {
                finding["description"] = newDesc
                changes.append("description updated")
            }

            anomalies[idx] = finding
            result["anomalies"] = anomalies
            lastInspectionResult = result

            addTranscript(.system("Edited finding #\(findingNumber): \(changes.joined(separator: ", "))"))
            return [
                "status": "updated",
                "changes": changes,
                "updated_findings": anomalies.enumerated().map {
                    "#\($0.offset+1) \($0.element["severity"] as? String ?? "?"): \($0.element["issue"] as? String ?? "?")"
                },
            ]
        }

        return ["error": "Unknown action: \(action). Use 'update' or 'remove'."]
    }

    // MARK: - Tool: submit_form_to_database (server-side generic)

    private func executeSubmitForm(args: [String: Any]) async -> [String: Any] {
        let formType = args["form_type"] as? String ?? ""
        let payloadStr = args["payload"] as? String ?? "{}"

        guard let payloadData = payloadStr.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
            return ["error": "Invalid payload JSON"]
        }

        // Route to the appropriate handler based on form_type
        switch formType {
        case "report_anomalies":
            return await executeReportAnomalies(args: payload)
        case "order_parts":
            return await executeOrderParts(args: payload)
        case "edit_findings":
            return executeEditFindings(args: payload)
        default:
            return ["error": "Unknown form_type: \(formType)"]
        }
    }

    // MARK: - System Prompt

    private func buildSystemPrompt() -> String {
        """
        You are an AI inspection assistant for CAT heavy equipment.

        FLOW:
        1. When the user describes damage or mentions a component, call run_inspection immediately. \
        The inspection takes 30-60 seconds (AI vision on GPU). Tell the user \
        "Running the inspection now, this will take about 30 seconds" and WAIT \
        patiently for the tool response. Do NOT call the tool again.

        2. After getting inspection results, read each finding with its NUMBER, severity, and issue. \
        Example: "Finding 1: FAIL — severe rim corrosion. Finding 2: MONITOR — missing lug nut." \
        Then ask: "Would you like to correct or remove any findings before I save them?"

        3. If the inspector wants to change something (e.g. "finding 1 is not rust, it's a scratch", \
        "change finding 2 to fail", "remove finding 3"), call edit_findings for each change. \
        After editing, read back the updated findings and ask again if they look correct.

        4. When the inspector confirms the findings are correct, ask: \
        "Should I save these findings to the task database?" \
        If yes, call report_anomalies with confirmed=true. \
        If no, call report_anomalies with confirmed=false.

        5. After reporting, tell the user what parts are needed and ask: \
        "Should I check inventory and order replacement parts?" \
        If yes, call order_parts with confirmed=true. \
        If no, call order_parts with confirmed=false.

        Keep responses short and clear.
        Current equipment: \(equipmentId) (\(equipmentModel)), task_id=\(taskId), inspection_id=\(inspectionId).
        """
    }

    // MARK: - Helpers

    private func trimForSpeech(_ result: [String: Any]) -> [String: Any] {
        var trimmed: [String: Any] = [
            "overall_status": result["overall_status"] as? String ?? "",
            "component_identified": result["component_identified"] as? String ?? "",
        ]

        if let impact = result["operational_impact"] as? String {
            trimmed["operational_impact"] = String(impact.prefix(120))
        }

        if let anomalies = result["anomalies"] as? [[String: Any]] {
            trimmed["findings"] = anomalies.enumerated().map { idx, a in
                [
                    "number": idx + 1,
                    "severity": a["severity"] as? String ?? "?",
                    "issue": String((a["issue"] as? String ?? "?").prefix(80)),
                ] as [String: Any]
            }
        }

        if let parts = result["parts"] as? [[String: Any]] {
            trimmed["parts_needed"] = parts.prefix(5).map { p in
                [
                    "part_name": p["part_name"] as? String ?? "?",
                    "urgency": p["urgency"] as? String ?? "?",
                ]
            }
        }

        return trimmed
    }

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
        if transcript.count > 50 {
            transcript.removeFirst(transcript.count - 50)
        }
    }
}
