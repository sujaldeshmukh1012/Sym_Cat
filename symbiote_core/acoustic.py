import io
import numpy as np
import librosa
import soundfile as sf

class SoundAnalyzer:
    """
    Industrial Acoustic Fault Detector.
    Uses spectral feature extraction (Centroid, Bandwidth, Flatness) 
    to identify mechanical anomalies like grinding, knocking, or high-frequency whining.
    """

    def __init__(self, sample_rate=22050):
        self.sr = sample_rate

    def analyze(self, audio_bytes: bytes) -> dict:
        try:
            # 1. Load audio from bytes
            audio_io = io.BytesIO(audio_bytes)
            y, sr = librosa.load(audio_io, sr=self.sr)

            if len(y) == 0:
                return {"error": "Empty audio buffer"}

            # 2. Extract Key Industry Features
            
            # Spectral Centroid: "Brightness" of sound. Grinding/Metal-on-metal is high.
            centroid = librosa.feature.spectral_centroid(y=y, sr=sr)[0]
            avg_centroid = np.mean(centroid)

            # Spectral Flatness: Measure of how noise-like the sound is vs tone-like.
            # Faulty bearings/fans often produce more tonal or distinct noise patterns.
            flatness = librosa.feature.spectral_flatness(y=y)[0]
            avg_flatness = np.mean(flatness)

            # RMS Energy: Loudness. Spikes indicate intermittent knocks.
            rms = librosa.feature.rms(y=y)[0]
            max_rms = np.max(rms)
            avg_rms = np.mean(rms)
            crest_factor = max_rms / (avg_rms + 1e-6) # High crest factor = intermittent knocking

            # 3. Industry Logic Heuristics
            # These values would typically be calibrated to a "baseline" machine sound.
            # Here we provide a generalized fault detection logic.

            faults = []
            score = 0.0 # 0 (Clean) to 1.0 (Critical Fault)

            # Fault 1: Metal-on-Metal Grinding (High Centroid + High Flatness)
            # Normal idling can reach 2kHz; grinding usually produces very high freq "shrieks" > 4kHz
            if avg_centroid > 4500 and avg_flatness > 0.1:
                faults.append({
                    "issue": "Metal-on-metal grinding detected",
                    "severity": "FAIL",
                    "confidence": 0.85,
                    "technical_reason": f"Spectral centroid ({avg_centroid:.1f}Hz) indicates high-frequency mechanical friction."
                })
                score = max(score, 0.9)

            # Fault 2: Mechanical Knocking / Impact (High Crest Factor)
            # Industrial engines have rhythmic pulses (Crest Factor 2-4 is often normal)
            # A true "knock" or "impact" spike is usually > 1.5
            if crest_factor > 1.5:
                faults.append({
                    "issue": "Mechanical knocking or impact detected",
                    "severity": "MONITOR",
                    "confidence": 0.75,
                    "technical_reason": f"Crest factor ({crest_factor:.1f}) indicates pulsatile mechanical energy."
                })
                score = max(score, 0.6)

            # Fault 3: Low Frequency Rumbeling/Vibration
            if avg_centroid < 800 and avg_rms > 0.1:
                 faults.append({
                    "issue": "Internal cavitation or heavy vibration",
                    "severity": "MONITOR",
                    "confidence": 0.65,
                    "technical_reason": "Excessive low-frequency energy detected below 800Hz."
                })
                 score = max(score, 0.5)

            status = "NORMAL"
            if score >= 0.8: status = "FAIL"
            elif score >= 0.5: status = "MONITOR"

            return {
                "overall_status": status,
                "faults": faults,
                "metrics": {
                    "avg_centroid_hz": float(avg_centroid),
                    "crest_factor": float(crest_factor),
                    "avg_flatness": float(avg_flatness)
                },
                "analysis_mode": "spectral_anomaly_detection"
            }

        except Exception as e:
            return {"error": f"Acoustic analysis failed: {str(e)}"}
