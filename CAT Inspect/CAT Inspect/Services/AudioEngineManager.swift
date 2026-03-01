//
//  AudioEngineManager.swift
//  CAT Inspect
//
//  Robust audio pipeline for the Gemini Live relay.
//
//  Responsibilities:
//  ─ Mic capture → 16-bit PCM @ 16 kHz mono (uplink to FastAPI)
//  ─ Playback via AVAudioSourceNode draining a thread-safe circular buffer
//  ─ Echo cancellation via .playAndRecord + .measurement mode
//  ─ Backpressure handling: drops oldest audio if buffer exceeds capacity
//

import AVFoundation
import Accelerate
import Foundation

// MARK: - Thread-safe Circular Audio Buffer

/// Lock-free-ish ring buffer for PCM audio bytes.
/// Writers (network thread) and readers (audio render thread) access
/// disjoint regions; the lock is held only for pointer updates.
final class CircularAudioBuffer: @unchecked Sendable {
    private var buffer: [UInt8]
    private let capacity: Int
    private var readIndex = 0
    private var writeIndex = 0
    private var count = 0
    private let lock = NSLock()

    /// Create a buffer with the given byte capacity.
    /// Default 96 000 bytes ≈ 2 s of 24 kHz 16-bit mono.
    init(capacity: Int = 96_000) {
        self.capacity = capacity
        self.buffer = [UInt8](repeating: 0, count: capacity)
    }

    /// Number of readable bytes.
    var availableBytes: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    /// Write `data` into the buffer.
    /// If the buffer would overflow, the **oldest** samples are dropped
    /// (the read pointer advances) — this implements back-pressure by
    /// preferring fresh audio over stale audio.
    func write(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }

        let needed = data.count
        if needed > capacity {
            // Data larger than entire buffer — keep only the tail
            let start = needed - capacity
            data.withUnsafeBytes { raw in
                let ptr = raw.baseAddress!.assumingMemoryBound(to: UInt8.self)
                buffer.withUnsafeMutableBufferPointer { dst in
                    _ = memcpy(dst.baseAddress!, ptr.advanced(by: start), capacity)
                }
            }
            readIndex = 0
            writeIndex = 0
            count = capacity
            return
        }

        // Drop oldest if not enough room
        let freeSpace = capacity - count
        if needed > freeSpace {
            let drop = needed - freeSpace
            readIndex = (readIndex + drop) % capacity
            count -= drop
        }

        data.withUnsafeBytes { raw in
            let ptr = raw.baseAddress!.assumingMemoryBound(to: UInt8.self)
            let firstChunk = min(needed, capacity - writeIndex)
            buffer.withUnsafeMutableBufferPointer { dst in
                memcpy(dst.baseAddress!.advanced(by: writeIndex), ptr, firstChunk)
                if firstChunk < needed {
                    memcpy(dst.baseAddress!, ptr.advanced(by: firstChunk), needed - firstChunk)
                }
            }
        }

        writeIndex = (writeIndex + needed) % capacity
        count += needed
    }

    /// Read up to `maxBytes` into the provided pointer. Returns actual bytes read.
    @discardableResult
    func read(into pointer: UnsafeMutablePointer<UInt8>, maxBytes: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }

        let toRead = min(maxBytes, count)
        if toRead == 0 { return 0 }

        let firstChunk = min(toRead, capacity - readIndex)
        buffer.withUnsafeBufferPointer { src in
            memcpy(pointer, src.baseAddress!.advanced(by: readIndex), firstChunk)
            if firstChunk < toRead {
                memcpy(pointer.advanced(by: firstChunk), src.baseAddress!, toRead - firstChunk)
            }
        }

        readIndex = (readIndex + toRead) % capacity
        count -= toRead
        return toRead
    }

    /// Discard all buffered audio.
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        readIndex = 0
        writeIndex = 0
        count = 0
    }
}

// MARK: - AudioEngineManager

@MainActor
final class AudioEngineManager: ObservableObject {

    // MARK: - Published state
    @Published var isCapturing = false
    @Published var isPlaying = false
    @Published var isMuted = false
    @Published var inputLevel: Float = 0     // 0…1 for VU meter

    // MARK: - Callbacks
    /// Called on a background thread with 100–200 ms chunks of PCM16 @ 16 kHz.
    var onAudioCaptured: ((Data) -> Void)?

    // MARK: - Audio engine components
    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private var converter: AVAudioConverter?

    // MARK: - Formats
    /// Mic capture target: 16-bit LE PCM, 16 kHz, mono
    private let captureFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16_000,
        channels: 1,
        interleaved: true
    )!

    /// Gemini playback: 16-bit LE PCM, 24 kHz, mono
    private let playbackSampleRate: Double = 24_000
    private var playbackFormat: AVAudioFormat!

    // MARK: - Circular buffer for incoming Gemini audio
    nonisolated let playbackBuffer = CircularAudioBuffer(capacity: 192_000)  // ~4 s @ 24 kHz

    // MARK: - Pre-buffer for wake-word transition
    /// Stores the last ~600 ms of mic audio so intent isn't lost during
    /// the WebSocket handshake after "Hey Cat" triggers.
    private var preBuffer = CircularAudioBuffer(capacity: 19_200)  // 600 ms @ 16 kHz 16-bit

    // MARK: - Init

    nonisolated init() {}

    // MARK: - Audio Session

    /// Configure the shared audio session for simultaneous capture + playback
    /// with echo cancellation. Uses `.measurement` mode which enables the
    /// system's acoustic echo canceller (AEC) on the selected route.
    func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .measurement,            // Enables AEC + flat frequency response
            options: [
                .defaultToSpeaker,         // Loudspeaker for hands-free use
                .allowBluetoothHFP,        // Support BT headsets
                .mixWithOthers,            // Don't interrupt other audio
            ]
        )
        try session.setPreferredSampleRate(16_000)
        try session.setPreferredIOBufferDuration(0.02)  // 20 ms hardware buffer
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Start Capture (Mic → onAudioCaptured)

    func startCapture() throws {
        guard !isCapturing else { return }

        try configureAudioSession()

        let inputNode = engine.inputNode
        let hwFormat = inputNode.outputFormat(forBus: 0)

        guard let conv = AVAudioConverter(from: hwFormat, to: captureFormat) else {
            throw AudioError.converterCreationFailed
        }
        converter = conv

        // Install mic tap — fires every ~100 ms
        inputNode.installTap(onBus: 0, bufferSize: AVAudioFrameCount(hwFormat.sampleRate * 0.1), format: hwFormat) {
            [weak self] buffer, _ in
            guard let self else { return }
            if self.isMuted { return }

            // Resample to 16 kHz PCM16 mono
            let ratio = 16_000.0 / hwFormat.sampleRate
            let outFrames = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
            guard let outBuf = AVAudioPCMBuffer(pcmFormat: self.captureFormat, frameCapacity: outFrames) else { return }

            var error: NSError?
            let status = conv.convert(to: outBuf, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            guard status != .error, error == nil, outBuf.frameLength > 0 else { return }

            let byteCount = Int(outBuf.frameLength) * 2  // 16-bit = 2 bytes/sample
            guard let int16Ptr = outBuf.int16ChannelData?[0] else { return }
            let pcmData = Data(bytes: int16Ptr, count: byteCount)

            // Always write to pre-buffer (for wake-word transition)
            self.preBuffer.write(pcmData)

            // Level metering (RMS)
            if let floatData = buffer.floatChannelData?[0] {
                var rms: Float = 0
                vDSP_rmsqv(floatData, 1, &rms, vDSP_Length(buffer.frameLength))
                Task { @MainActor in self.inputLevel = min(rms * 5, 1.0) }
            }

            // Forward to callback
            self.onAudioCaptured?(pcmData)
        }

        // ---- Playback source node (pulls from circular buffer) ----
        setupPlaybackSourceNode()

        try engine.start()
        isCapturing = true
    }

    // MARK: - Playback via AVAudioSourceNode

    /// The AVAudioSourceNode is a "pull" node — the audio render thread
    /// calls our closure every hardware buffer period (~20 ms). We drain
    /// the circular buffer; if it's empty we output silence (zeros).
    private func setupPlaybackSourceNode() {
        // Find actual hardware output sample rate for the source node
        _ = engine.outputNode.outputFormat(forBus: 0).sampleRate
        playbackFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: playbackSampleRate,
            channels: 1,
            interleaved: true
        )!

        let circBuf = playbackBuffer  // capture for render closure

        let node = AVAudioSourceNode(format: playbackFormat) { _, _, frameCount, bufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(bufferList)
            let bytesNeeded = Int(frameCount) * 2  // 16-bit

            for i in 0..<ablPointer.count {
                guard let dataPtr = ablPointer[i].mData?.assumingMemoryBound(to: UInt8.self) else { continue }
                let read = circBuf.read(into: dataPtr, maxBytes: bytesNeeded)
                // Zero-fill any unread portion (silence)
                if read < bytesNeeded {
                    memset(dataPtr.advanced(by: read), 0, bytesNeeded - read)
                }
                ablPointer[i].mDataByteSize = UInt32(bytesNeeded)
            }
            return noErr
        }

        sourceNode = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: playbackFormat)
    }

    // MARK: - Enqueue Playback Audio

    /// Called from the network layer when Gemini audio arrives.
    /// Simply appends to the circular buffer — the source node will drain it.
    nonisolated func enqueuePlaybackAudio(_ data: Data) {
        playbackBuffer.write(data)
    }

    /// Stop Gemini playback immediately (barge-in).
    func flushPlayback() {
        playbackBuffer.reset()
    }

    // MARK: - Pre-buffer Access

    /// Drain the pre-buffer to recover ~500 ms of audio captured before
    /// the WebSocket connection was established (post wake-word).
    func drainPreBuffer() -> Data {
        let available = preBuffer.availableBytes
        guard available > 0 else { return Data() }
        var bytes = [UInt8](repeating: 0, count: available)
        preBuffer.read(into: &bytes, maxBytes: available)
        return Data(bytes)
    }

    // MARK: - Stop

    func stopCapture() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        if let node = sourceNode {
            engine.detach(node)
            sourceNode = nil
        }
        isCapturing = false
        isPlaying = false
        playbackBuffer.reset()
        preBuffer.reset()
    }

    // MARK: - Mute toggle

    func toggleMute() {
        isMuted.toggle()
    }
}

// MARK: - Errors

enum AudioError: LocalizedError {
    case converterCreationFailed
    case engineStartFailed(String)

    var errorDescription: String? {
        switch self {
        case .converterCreationFailed:
            return "Failed to create AVAudioConverter (hardware format incompatible)"
        case .engineStartFailed(let reason):
            return "Audio engine start failed: \(reason)"
        }
    }
}
