//
//  WakeWordManager.swift
//  CAT Inspect
//
//  Picovoice Porcupine wake-word detection for "Hey Cat".
//
//  Reads the Picovoice access key from Info.plist (key: PICOVOICE_ACCESS_KEY).
//  The .ppn keyword file (Hey-Cat-AI_en_ios_v4_0_0.ppn) must be in the app bundle.
//
//  PorcupineManager runs its OWN microphone tap internally, so during passive
//  listening the AudioEngineManager does NOT need to be running. When the wake
//  word fires we stop Porcupine, hand off mic ownership to AudioEngineManager,
//  and start the relay session.
//

import Foundation
import AVFoundation
import Combine
import Porcupine

/// Manages always-on wake word detection using Picovoice Porcupine.
/// When "Hey Cat" is detected, publishes an event so the relay session can start.
final class WakeWordManager: ObservableObject {
    
    // MARK: - Published State
    @Published var isListening: Bool = false
    @Published var wakeWordDetected: Bool = false
    
    // MARK: - Porcupine
    private var porcupineManager: PorcupineManager?
    
    // MARK: - Configuration
    private let accessKey: String
    private let keywordFileName: String
    
    // MARK: - Pre-buffer timestamp
    /// Records when the wake word fired so the caller can measure handshake latency.
    private(set) var triggerTimestamp: Date?
    
    // MARK: - Callback
    var onWakeWordDetected: (() -> Void)?
    
    // MARK: - Init (reads from Info.plist)
    
    /// Convenience: reads `PICOVOICE_ACCESS_KEY` from Info.plist automatically.
    /// Falls back to an empty string (Porcupine will error on start).
    convenience init() {
        let key = Bundle.main.object(forInfoDictionaryKey: "PICOVOICE_ACCESS_KEY") as? String ?? ""
        self.init(accessKey: key)
    }
    
    /// Full initializer with explicit key and keyword file name.
    /// - Parameters:
    ///   - accessKey: Your Picovoice access key (from console.picovoice.ai)
    ///   - keywordFileName: The .ppn file name in the bundle WITHOUT the extension.
    init(
        accessKey: String,
        keywordFileName: String = "Hey-Cat-AI_en_ios_v4_0_0"
    ) {
        self.accessKey = accessKey
        self.keywordFileName = keywordFileName
    }
    
    // MARK: - Start listening (passive mode)
    
    /// Starts Porcupine's built-in mic tap and listens for "Hey Cat".
    /// Does NOT require AudioEngineManager — Porcupine owns the mic here.
    func startListening() {
        guard !isListening else { return }
        
        guard !accessKey.isEmpty, accessKey != "$(PICOVOICE_ACCESS_KEY)" else {
            print("[WakeWord] ❌ PICOVOICE_ACCESS_KEY not set.")
            print("[WakeWord]    Add it to Info.plist or pass it in init(accessKey:).")
            print("[WakeWord]    Get a key at https://console.picovoice.ai")
            return
        }
        
        do {
            // Configure audio session for mic access
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.defaultToSpeaker, .allowBluetoothHFP]
            )
            try session.setActive(true)
        } catch {
            print("[WakeWord] Audio session error: \(error)")
            return
        }
        
        do {
            // Find the .ppn keyword file in the app bundle
            guard let keywordPath = Bundle.main.path(
                forResource: keywordFileName,
                ofType: "ppn"
            ) else {
                print("[WakeWord] ❌ Could not find \(keywordFileName).ppn in bundle.")
                print("[WakeWord]    The file should be at the project root and added to the target.")
                return
            }
            
            print("[WakeWord] Found keyword file: \(keywordPath)")
            
            // Create PorcupineManager — it runs its own mic tap internally
            porcupineManager = try PorcupineManager(
                accessKey: accessKey,
                keywordPath: keywordPath,
                sensitivity: 0.7,  // 0.0 = fewest false positives, 1.0 = fewest misses
                onDetection: { [weak self] _ in
                    guard let self = self else { return }
                    
                    print("[WakeWord] 🎯 'Hey Cat' detected!")
                    self.triggerTimestamp = Date()
                    
                    DispatchQueue.main.async {
                        self.wakeWordDetected = true
                        self.onWakeWordDetected?()
                        
                        // Reset flag after a short delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            self.wakeWordDetected = false
                        }
                    }
                }
            )
            
            try porcupineManager?.start()
            
            DispatchQueue.main.async {
                self.isListening = true
            }
            print("[WakeWord] ✅ Porcupine listening for 'Hey Cat'")
            
        } catch {
            print("[WakeWord] ❌ Porcupine init error: \(error)")
            print("[WakeWord] Common fixes:")
            print("  1. Check your access key is valid")
            print("  2. Ensure the .ppn file matches your Porcupine SDK version (v4)")
            print("  3. Verify the .ppn was trained for iOS platform")
        }
    }
    
    // MARK: - Stop / Resume
    
    /// Stop Porcupine listening. Call this when transitioning to active session
    /// so AudioEngineManager can take over the mic without conflict.
    func stopListening() {
        do {
            try porcupineManager?.stop()
        } catch {
            print("[WakeWord] ⚠️ Error stopping Porcupine: \(error)")
        }
        DispatchQueue.main.async {
            self.isListening = false
        }
        print("[WakeWord] ⏹ Stopped listening")
    }
    
    /// Resume listening after an active session ends.
    func resumeListening() {
        guard !isListening else { return }
        do {
            try porcupineManager?.start()
            DispatchQueue.main.async {
                self.isListening = true
            }
            print("[WakeWord] ▶️ Resumed listening")
        } catch {
            print("[WakeWord] ❌ Failed to resume: \(error)")
        }
    }
    
    // MARK: - Session lifecycle helpers
    
    /// Called when the relay session becomes active.
    /// Stops Porcupine so AudioEngineManager can own the mic.
    func activateSession() {
        stopListening()
    }
    
    /// Called when the relay session ends.
    /// Resumes Porcupine for passive wake-word detection.
    func deactivateSession() {
        resumeListening()
    }
    
    // MARK: - Cleanup
    
    func destroy() {
        do {
            try porcupineManager?.stop()
        } catch {
            print("[WakeWord] ⚠️ Error stopping Porcupine: \(error)")
        }
        do {
            try porcupineManager?.delete()
        } catch {
            print("[WakeWord] ⚠️ Error deleting Porcupine: \(error)")
        }
        porcupineManager = nil
        DispatchQueue.main.async {
            self.isListening = false
        }
        print("[WakeWord] 🗑 Destroyed Porcupine resources")
    }
    
    deinit {
        destroy()
    }
}
