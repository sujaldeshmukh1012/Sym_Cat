//
//  GeminiRelayClient.swift
//  CAT Inspect
//
//  WebSocket client that connects to the FastAPI relay at /ws/live.
//  Instead of talking directly to Google's servers, the iOS app sends
//  audio/images/tool-responses through our FastAPI bridge.
//
//  Wire protocol (matches api/routers/gemini_live.py):
//  ─────────────────────────────────────────────────────
//  UPLINK (iOS → FastAPI):
//    Binary frame: Raw PCM 16-bit LE mono @ 16 kHz
//    JSON: {"type": "audio",         "data": "<b64>"}
//    JSON: {"type": "image",         "data": "<b64>", "mime_type": "image/jpeg"}
//    JSON: {"type": "tool_response", "function_responses": [...]}
//    JSON: {"type": "config",        "model": "...", "voice": "...", ...}
//    JSON: {"type": "end_session"}
//
//  DOWNLINK (FastAPI → iOS):
//    Binary frame: Raw PCM 16-bit LE mono @ 24 kHz
//    JSON: {"type": "session_ready",  "model": "...", "voice": "..."}
//    JSON: {"type": "transcript",     "text": "...",  "role": "model"}
//    JSON: {"type": "tool_call",      "function_calls": [...]}
//    JSON: {"type": "turn_complete"}
//    JSON: {"type": "interrupted"}
//    JSON: {"type": "error",          "message": "..."}
//

import Foundation
import Combine

// MARK: - Relay event types (decoded from server JSON)

enum RelayEvent {
    case sessionReady(model: String, voice: String)
    case audioChunk(Data)                          // raw PCM bytes
    case transcript(text: String, role: String)
    case toolCall(functionCalls: [[String: Any]])
    case turnComplete
    case interrupted
    case error(String)
    case disconnected
}

// MARK: - GeminiRelayClient

/// Manages the WebSocket connection to the FastAPI /ws/live endpoint.
/// Provides a Combine publisher for incoming events and methods to
/// send audio, images, and tool responses upstream.
@MainActor
final class GeminiRelayClient: NSObject, ObservableObject {

    // MARK: Published
    @Published var isConnected = false

    // MARK: Event stream
    /// Downstream events from the relay. Subscribe to receive audio, tool calls, etc.
    let eventSubject = PassthroughSubject<RelayEvent, Never>()

    // MARK: Config
    private let relayPath = "/ws/live"

    // MARK: Internal
    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var isClosed = false

    // Audio send queue — coalesces small PCM chunks to reduce WS frame overhead.
    // Sends at most every 100 ms (matches the mic tap interval).
    private var audioSendBuffer = Data()
    private var audioSendTimer: Timer?
    private let audioSendInterval: TimeInterval = 0.1  // 100 ms

    // MARK: - Connect

    /// Open a WebSocket to the FastAPI relay and optionally send a config message.
    func connect(
        model: String? = nil,
        voice: String? = nil,
        systemPrompt: String? = nil
    ) {
        guard !isConnected else { return }
        isClosed = false

        // Build relay WebSocket URL from the backend config
        var components = URLComponents(
            url: BackendServiceConfig.apiBaseURL,
            resolvingAgainstBaseURL: false
        )!
        components.scheme = BackendServiceConfig.apiBaseURL.scheme == "https" ? "wss" : "ws"
        components.path = relayPath

        guard let url = components.url else {
            eventSubject.send(.error("Invalid relay URL"))
            return
        }

        print("[RelayClient] Connecting to \(url.absoluteString)")

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = 600
        urlSession = URLSession(configuration: config, delegate: nil, delegateQueue: nil)
        webSocket = urlSession?.webSocketTask(with: url)
        webSocket?.resume()

        // Send optional config as the very first message
        if model != nil || voice != nil || systemPrompt != nil {
            let configMsg: [String: Any] = [
                "type": "config",
                "model": model ?? "gemini-2.0-flash-live-001",
                "voice": voice ?? "Charon",
                "system_prompt": systemPrompt ?? "",
            ]
            sendJSON(configMsg)
        }

        startReceiveLoop()
        startAudioSendTimer()
    }

    // MARK: - Disconnect

    func disconnect() {
        isClosed = true
        audioSendTimer?.invalidate()
        audioSendTimer = nil

        // Send end_session before closing
        sendJSON(["type": "end_session"])

        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        isConnected = false
        eventSubject.send(.disconnected)
        print("[RelayClient] Disconnected")
    }

    // MARK: - Send Audio (PCM bytes)

    /// Queue raw PCM16 audio for sending. Coalesced into ~100 ms binary frames.
    /// This is called from the mic tap (background thread).
    nonisolated func sendAudio(_ pcmData: Data) {
        // Binary frames are the fastest path — no base64 overhead.
        // We batch into ~100 ms chunks via the timer on the main actor.
        Task { @MainActor [weak self] in
            self?.audioSendBuffer.append(pcmData)
        }
    }

    /// Flush the audio send buffer immediately (e.g., pre-buffer drain).
    func flushAudioBuffer() {
        guard !audioSendBuffer.isEmpty else { return }
        let data = audioSendBuffer
        audioSendBuffer = Data()
        webSocket?.send(.data(data)) { error in
            if let error { print("[RelayClient] Audio send error: \(error)") }
        }
    }

    // MARK: - Send Image (JPEG)

    /// Send a JPEG image to the relay for visual context.
    func sendImage(_ jpegData: Data, mimeType: String = "image/jpeg") {
        let b64 = jpegData.base64EncodedString()
        sendJSON([
            "type": "image",
            "data": b64,
            "mime_type": mimeType,
        ])
        print("[RelayClient] Sent image (\(jpegData.count / 1024) KB)")
    }

    // MARK: - Send Tool Response

    /// Forward the result of a client-side tool call back to Gemini via the relay.
    func sendToolResponse(callId: String, name: String, result: [String: Any]) {
        sendJSON([
            "type": "tool_response",
            "function_responses": [
                [
                    "id": callId,
                    "name": name,
                    "response": result,
                ]
            ],
        ])
        print("[RelayClient] Sent tool_response for \(name)")
    }

    // MARK: - Receive Loop

    private func startReceiveLoop() {
        webSocket?.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, !self.isClosed else { return }

                switch result {
                case .success(let message):
                    self.handleMessage(message)
                    self.startReceiveLoop()  // Continue receiving

                case .failure(let error):
                    if !self.isClosed {
                        print("[RelayClient] Receive error: \(error)")
                        self.isConnected = false
                        self.eventSubject.send(.error(error.localizedDescription))
                        self.eventSubject.send(.disconnected)
                    }
                }
            }
        }
    }

    // MARK: - Message Handling

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .data(let data):
            // Binary frame = raw PCM audio from Gemini (24 kHz)
            eventSubject.send(.audioChunk(data))

        case .string(let text):
            guard let data = text.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String else {
                return
            }

            switch type {
            case "session_ready":
                isConnected = true
                let model = json["model"] as? String ?? "?"
                let voice = json["voice"] as? String ?? "?"
                eventSubject.send(.sessionReady(model: model, voice: voice))
                print("[RelayClient] Session ready: model=\(model) voice=\(voice)")

            case "transcript":
                let text = json["text"] as? String ?? ""
                let role = json["role"] as? String ?? "model"
                eventSubject.send(.transcript(text: text, role: role))

            case "tool_call":
                let functionCalls = json["function_calls"] as? [[String: Any]] ?? []
                eventSubject.send(.toolCall(functionCalls: functionCalls))
                print("[RelayClient] Tool call(s): \(functionCalls.count)")

            case "turn_complete":
                eventSubject.send(.turnComplete)

            case "interrupted":
                eventSubject.send(.interrupted)

            case "error":
                let msg = json["message"] as? String ?? "Unknown relay error"
                eventSubject.send(.error(msg))
                print("[RelayClient] Error: \(msg)")

            default:
                print("[RelayClient] Unknown message type: \(type)")
            }

        @unknown default:
            break
        }
    }

    // MARK: - Audio Send Timer

    /// Fires every 100 ms to flush accumulated PCM data as a single binary frame.
    private func startAudioSendTimer() {
        audioSendTimer?.invalidate()
        audioSendTimer = Timer.scheduledTimer(withTimeInterval: audioSendInterval, repeats: true) {
            [weak self] _ in
            Task { @MainActor [weak self] in
                self?.flushAudioBuffer()
            }
        }
    }

    // MARK: - JSON Send Helper

    private func sendJSON(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: data, encoding: .utf8) else { return }
        webSocket?.send(.string(text)) { error in
            if let error { print("[RelayClient] Send error: \(error)") }
        }
    }
}
