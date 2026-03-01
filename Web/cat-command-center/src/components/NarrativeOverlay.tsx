import { useState, useEffect } from "react";
import { motion, AnimatePresence } from "framer-motion";

interface NarrativeOverlayProps {
  /** Called after all 3 slides + CTA have been shown and user clicks Enter */
  onEnterClick: () => void;
  /** Whether to show the overlay at all */
  active: boolean;
}

const narrativeSlides = [
  {
    tag: "IDENTIFICATION",
    title: "SYMBIOTE",
    body: "",
    isTitle: true,
  },
  {
    tag: "MISSION",
    title: "ELEVATOR PITCH",
    body: "Voice-first AI inspection platform for CAT heavy equipment. Speak damage, get diagnosis, order parts — hands free in under 60 seconds. Built for the field, not the office.",
    isTitle: false,
  },
  {
    tag: "PURPOSE",
    title: "INSPIRATION",
    body: "Downtime costs $2,000/hr. We built a system that works with work gloves on. No keyboards, just results.",
    isTitle: false,
  },
];

const NarrativeOverlay = ({ onEnterClick, active }: NarrativeOverlayProps) => {
  const [currentSlide, setCurrentSlide] = useState(0);
  const [showCTA, setShowCTA] = useState(false);
  const [ctaHovered, setCtaHovered] = useState(false);

  // Auto-advance slides on a timer
  useEffect(() => {
    if (!active) return;

    const durations = [3000, 6000, 5000]; // ms per slide
    if (currentSlide < narrativeSlides.length) {
      const timer = setTimeout(() => {
        if (currentSlide < narrativeSlides.length - 1) {
          setCurrentSlide((c) => c + 1);
        } else {
          setShowCTA(true);
        }
      }, durations[currentSlide] || 4000);
      return () => clearTimeout(timer);
    }
  }, [currentSlide, active]);

  // Allow keyboard skip
  useEffect(() => {
    if (!active) return;
    const handleKey = (e: KeyboardEvent) => {
      if (e.key === " " || e.key === "Enter" || e.key === "ArrowRight") {
        if (showCTA) {
          onEnterClick();
        } else if (currentSlide < narrativeSlides.length - 1) {
          setCurrentSlide((c) => c + 1);
        } else {
          setShowCTA(true);
        }
      }
    };
    window.addEventListener("keydown", handleKey);
    return () => window.removeEventListener("keydown", handleKey);
  }, [active, currentSlide, showCTA, onEnterClick]);

  if (!active) return null;

  return (
    <div className="absolute inset-0 z-20 flex items-center justify-center pointer-events-none">
      {/* Holographic scanline overlay */}
      <div className="absolute inset-0 pointer-events-none overflow-hidden">
        <div
          className="absolute inset-0 opacity-[0.03]"
          style={{
            backgroundImage:
              "repeating-linear-gradient(0deg, transparent, transparent 2px, rgba(255,205,0,0.15) 2px, rgba(255,205,0,0.15) 4px)",
          }}
        />
      </div>

      {/* Corner HUD elements */}
      <div className="absolute top-6 right-6 font-hud text-[10px] text-primary/40 tracking-[0.3em] animate-text-flicker">
        SYMBIOTE v3.0
      </div>
      <div className="absolute bottom-6 right-6 font-hud text-[10px] text-primary/30 tracking-widest">
        {showCTA
          ? "READY"
          : `${String(currentSlide + 1).padStart(2, "0")} / ${String(narrativeSlides.length).padStart(2, "0")}`}
      </div>

      <AnimatePresence mode="wait">
        {!showCTA ? (
          <motion.div
            key={`slide-${currentSlide}`}
            initial={{ opacity: 0, y: 20, filter: "blur(8px)" }}
            animate={{ opacity: 1, y: 0, filter: "blur(0px)" }}
            exit={{ opacity: 0, y: -20, filter: "blur(8px)" }}
            transition={{ duration: 0.6, ease: "easeOut" }}
            className="max-w-xl px-6 text-center pointer-events-auto"
          >
            {narrativeSlides[currentSlide].isTitle ? (
              /* Slide 1: Big project name */
              <div>
                <div className="font-hud text-[10px] text-primary/50 tracking-[0.5em] mb-4">
                  {narrativeSlides[currentSlide].tag}
                </div>
                <h1 className="font-hud text-5xl md:text-7xl font-black text-primary tracking-[0.15em] drop-shadow-[0_0_30px_rgba(255,205,0,0.4)]">
                  {narrativeSlides[currentSlide].title}
                </h1>
                <div className="mt-4 w-24 h-[2px] mx-auto bg-gradient-to-r from-transparent via-primary to-transparent" />
              </div>
            ) : (
              /* Slides 2-3: Glass card with text */
              <div className="glass-card rounded-lg p-8 md:p-10">
                <div className="font-hud text-[10px] text-primary/50 tracking-[0.4em] mb-3">
                  {narrativeSlides[currentSlide].tag}
                </div>
                <h2 className="font-hud text-xl md:text-2xl font-bold text-primary mb-4 tracking-wider">
                  {narrativeSlides[currentSlide].title}
                </h2>
                <p className="font-body text-base md:text-lg text-foreground/80 leading-relaxed">
                  {narrativeSlides[currentSlide].body}
                </p>
              </div>
            )}

            {/* Click to skip hint */}
            <div className="mt-6 font-hud text-[9px] text-primary/25 tracking-widest animate-pulse">
              PRESS SPACE TO CONTINUE
            </div>
          </motion.div>
        ) : (
          <motion.div
            key="cta"
            initial={{ opacity: 0, scale: 0.85, filter: "blur(10px)" }}
            animate={{ opacity: 1, scale: 1, filter: "blur(0px)" }}
            transition={{ duration: 0.6, ease: "easeOut" }}
            className="flex flex-col items-center gap-6 pointer-events-auto"
          >
            <div className="font-hud text-xs text-primary/50 tracking-[0.4em]">
              AUTHORIZATION COMPLETE
            </div>
            <button
              className="relative group px-10 py-5 bg-primary text-primary-foreground font-hud text-lg md:text-xl tracking-wider rounded overflow-hidden transition-all duration-300 hover:shadow-[0_0_60px_hsl(47_100%_50%/0.5)]"
              onMouseEnter={() => setCtaHovered(true)}
              onMouseLeave={() => setCtaHovered(false)}
              onClick={onEnterClick}
            >
              {ctaHovered && (
                <div className="absolute inset-0 overflow-hidden pointer-events-none">
                  <div className="absolute inset-x-0 h-8 bg-gradient-to-b from-transparent via-primary-foreground/20 to-transparent animate-scan-line" />
                </div>
              )}
              <span className="relative z-10">
                {ctaHovered ? "⚡ SYSTEM AUTHORIZED" : "ENTER COMMAND CENTER"}
              </span>
            </button>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
};

export default NarrativeOverlay;
