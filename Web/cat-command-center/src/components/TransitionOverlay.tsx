import { useEffect, useRef, useState } from "react";
import { motion } from "framer-motion";
import gsap from "gsap";

interface TransitionOverlayProps {
  /** Whether this overlay is active */
  active: boolean;
  /** Called when the transition animation completes */
  onComplete: () => void;
}

/**
 * Full-screen overlay that plays when the user clicks "Enter Command Center".
 * Shows a golden loading bar (the "snake turning into a bar") with hydraulic SFX.
 */
const TransitionOverlay = ({ active, onComplete }: TransitionOverlayProps) => {
  const barRef = useRef<HTMLDivElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const [statusText, setStatusText] = useState("INITIALIZING SYMBIOTE LINK…");

  useEffect(() => {
    if (!active) return;

    // Play hydraulic hiss sound
    try {
      const audioCtx = new AudioContext();
      // Synthesize a hydraulic hiss with white noise + band-pass
      const duration = 0.8;
      const bufferSize = audioCtx.sampleRate * duration;
      const buffer = audioCtx.createBuffer(1, bufferSize, audioCtx.sampleRate);
      const data = buffer.getChannelData(0);
      for (let i = 0; i < bufferSize; i++) {
        // Envelope: quick attack, slow decay
        const env = Math.exp(-i / (bufferSize * 0.15)) * 0.4;
        data[i] = (Math.random() * 2 - 1) * env;
      }
      const source = audioCtx.createBufferSource();
      source.buffer = buffer;

      // Band-pass filter for that "hissy" quality
      const filter = audioCtx.createBiquadFilter();
      filter.type = "bandpass";
      filter.frequency.value = 3000;
      filter.Q.value = 0.8;

      source.connect(filter);
      filter.connect(audioCtx.destination);
      source.start();
    } catch {
      // Audio may fail silently — not critical
    }

    // GSAP timeline for the loading bar
    const tl = gsap.timeline({
      onComplete: () => {
        onComplete();
      },
    });

    if (barRef.current) {
      tl.fromTo(
        barRef.current,
        { scaleX: 0 },
        {
          scaleX: 1,
          duration: 1.8,
          ease: "power2.inOut",
          onUpdate: function () {
            const progress = this.progress();
            if (progress > 0.3 && progress < 0.6) {
              setStatusText("MOUNTING COMMAND CENTER…");
            } else if (progress >= 0.6) {
              setStatusText("SYSTEM ONLINE");
            }
          },
        }
      );
    }

    // Flash the container at the end
    if (containerRef.current) {
      tl.to(containerRef.current, {
        backgroundColor: "rgba(255, 205, 0, 0.15)",
        duration: 0.2,
        yoyo: true,
        repeat: 1,
      });
      tl.to(containerRef.current, {
        opacity: 0,
        duration: 0.4,
        ease: "power2.in",
      });
    }

    return () => {
      tl.kill();
    };
  }, [active, onComplete]);

  if (!active) return null;

  return (
    <motion.div
      ref={containerRef}
      className="fixed inset-0 z-50 flex flex-col items-center justify-center bg-background"
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      transition={{ duration: 0.3 }}
    >
      {/* Vignette */}
      <div
        className="absolute inset-0 pointer-events-none"
        style={{
          background:
            "radial-gradient(ellipse at center, transparent 30%, rgba(0,0,0,0.8) 100%)",
        }}
      />

      {/* Status text */}
      <div className="relative z-10 mb-8">
        <div className="font-hud text-xs text-primary/60 tracking-[0.4em] animate-text-flicker">
          {statusText}
        </div>
      </div>

      {/* Golden loading bar */}
      <div className="relative z-10 w-80 md:w-96 h-1.5 bg-primary/10 rounded-full overflow-hidden">
        <div
          ref={barRef}
          className="h-full rounded-full origin-left"
          style={{
            background:
              "linear-gradient(90deg, #B8960A 0%, #FFCD00 40%, #FFE066 60%, #FFCD00 100%)",
            boxShadow: "0 0 20px rgba(255, 205, 0, 0.6), 0 0 60px rgba(255, 205, 0, 0.2)",
            transform: "scaleX(0)",
          }}
        />
      </div>

      {/* Symbiote text at bottom */}
      <div className="relative z-10 mt-12 font-hud text-[10px] text-primary/20 tracking-[0.5em]">
        SYMBIOTE
      </div>
    </motion.div>
  );
};

export default TransitionOverlay;
