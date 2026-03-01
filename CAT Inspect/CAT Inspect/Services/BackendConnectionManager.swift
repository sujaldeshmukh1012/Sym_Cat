//
//  BackendConnectionManager.swift
//  CAT Inspect
//
//  Manages the persistent WebSocket connection to the local FastAPI server
//  and provides connectivity status to the rest of the app.
//

import Foundation
import Combine

// MARK: - Connection State

enum BackendConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int)

    var label: String {
        switch self {
        case .disconnected:                return "Disconnected"
        case .connecting:                  return "Connecting…"
        case .connected:                   return "Connected"
        case .reconnecting(let attempt):   return "Reconnecting (\(attempt))…"
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

// MARK: - BackendConnectionManager

@MainActor
final class BackendConnectionManager: NSObject, ObservableObject {
    static let shared = BackendConnectionManager()

    // MARK: Published
    @Published var state: BackendConnectionState = .disconnected
    @Published var lastPongTime: Date?
    @Published var serverVersion: String?

    // MARK: Config
    private let maxReconnectAttempts = 10
    private let baseReconnectDelay: TimeInterval = 2.0  // exponential backoff
    private let pingInterval: TimeInterval = 15.0

    // MARK: Internal
    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var reconnectAttempt = 0
    private var pingTimer: Timer?
    private var isIntentionalDisconnect = false

    private override init() {
        super.init()
    }

    // MARK: - Public API

    /// Start the connection to the FastAPI backend.
    /// First does a REST /health check, then opens the WebSocket.
    func connect() {
        guard !state.isConnected else {
            log("Already connected — ignoring connect()")
            return
        }
        isIntentionalDisconnect = false
        reconnectAttempt = 0
        log("Connecting to \(BackendServiceConfig.apiBaseURL.absoluteString)")
        log("WS URL will be \(BackendServiceConfig.wsURL.absoluteString)")
        attemptConnection()
    }

    /// Gracefully close the connection.
    func disconnect() {
        isIntentionalDisconnect = true
        pingTimer?.invalidate()
        pingTimer = nil
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        state = .disconnected
        log("Disconnected (user-initiated)")
    }

    /// Send a ping and wait for pong to verify connectivity.
    func sendPing() {
        guard state.isConnected else { return }
        let msg: [String: Any] = ["type": "ping"]
        send(msg)
    }

    /// Quick REST health check (non-WebSocket).
    func healthCheck() async -> Bool {
        let healthURL = BackendServiceConfig.apiBaseURL.appendingPathComponent("health")
        log("Health check → \(healthURL.absoluteString)")
        var request = URLRequest(url: healthURL)
        request.timeoutInterval = 5
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                log("Health check: no HTTP response")
                return false
            }
            log("Health check: HTTP \(http.statusCode)")
            guard http.statusCode == 200 else { return false }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let status = json["status"] as? String, status == "ok" {
                return true
            }
            return false
        } catch {
            log("Health check FAILED: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Connection Lifecycle

    /// First pings /health over REST, then opens the WebSocket.
    private func attemptConnection() {
        state = reconnectAttempt == 0 ? .connecting : .reconnecting(attempt: reconnectAttempt)

        Task {
            // Quick REST health check first — if this fails the server is down
            // and there's no point trying a WebSocket.
            let healthy = await healthCheck()
            if healthy {
                log("REST /health OK — opening WebSocket…")
                self.openWebSocket()
            } else {
                log("REST /health FAILED — server unreachable at \(BackendServiceConfig.apiBaseURL.absoluteString)")
                self.handleConnectionFailure(error: nil)
            }
        }
    }

    private func openWebSocket() {
        state = reconnectAttempt == 0 ? .connecting : .reconnecting(attempt: reconnectAttempt)
        let wsURL = BackendServiceConfig.wsURL
        log("Opening WebSocket to \(wsURL.absoluteString)")

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = 300
        urlSession = URLSession(configuration: config, delegate: nil, delegateQueue: nil)
        webSocket = urlSession?.webSocketTask(with: wsURL)
        webSocket?.resume()

        receiveLoop()

        // If we don't get a "connected" message within 5s, consider it failed
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if case .connecting = self.state {
                self.handleConnectionFailure(error: nil)
            } else if case .reconnecting = self.state {
                self.handleConnectionFailure(error: nil)
            }
        }
    }

    private func receiveLoop() {
        webSocket?.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch result {
                case .success(let message):
                    self.handleMessage(message)
                    // Continue receiving
                    self.receiveLoop()
                case .failure(let error):
                    if !self.isIntentionalDisconnect {
                        self.handleConnectionFailure(error: error)
                    }
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .data(let d): data = d
        case .string(let s): data = s.data(using: .utf8) ?? Data()
        @unknown default: return
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }

        switch type {
        case "connected":
            reconnectAttempt = 0
            state = .connected
            serverVersion = json["version"] as? String
            let serverMessage = json["message"] as? String ?? ""
            log("Connected! version=\(serverVersion ?? "?") msg=\(serverMessage)")
            startPingTimer()

        case "pong":
            lastPongTime = Date()
            log("Pong received")

        case "health":
            let activeConnections = json["active_connections"] as? Int ?? 0
            log("Health: \(activeConnections) active connections")

        case "error":
            let errorMsg = json["message"] as? String ?? "Unknown"
            log("Server error: \(errorMsg)")

        case "echo":
            log("Echo: \(json)")

        default:
            log("Message type=\(type): \(json)")
        }
    }

    private func handleConnectionFailure(error: Error?) {
        webSocket?.cancel(with: .abnormalClosure, reason: nil)
        webSocket = nil
        pingTimer?.invalidate()
        pingTimer = nil

        guard !isIntentionalDisconnect else { return }

        reconnectAttempt += 1

        if reconnectAttempt > maxReconnectAttempts {
            state = .disconnected
            log("Max reconnection attempts reached. Giving up.")
            return
        }

        state = .reconnecting(attempt: reconnectAttempt)
        let delay = baseReconnectDelay * pow(1.5, Double(reconnectAttempt - 1))
        let clampedDelay = min(delay, 30.0)  // cap at 30s
        log("Reconnecting in \(String(format: "%.1f", clampedDelay))s (attempt \(reconnectAttempt)/\(maxReconnectAttempts))")

        Task {
            try? await Task.sleep(nanoseconds: UInt64(clampedDelay * 1_000_000_000))
            guard !self.isIntentionalDisconnect else { return }
            self.attemptConnection()
        }
    }

    // MARK: - Ping timer

    private func startPingTimer() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: pingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sendPing()
            }
        }
    }

    // MARK: - Send helper

    private func send(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return }
        let msg = URLSessionWebSocketTask.Message.string(String(data: data, encoding: .utf8)!)
        webSocket?.send(msg) { [weak self] error in
            if let error {
                Task { @MainActor [weak self] in
                    self?.log("Send error: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Logging

    private func log(_ message: String) {
        print("[BackendWS] \(message)")
    }
}
