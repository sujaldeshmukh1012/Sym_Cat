import { useState, useCallback, useEffect } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { useNavigate } from "react-router-dom";
import { ChevronLeft, ChevronRight } from "lucide-react";

const slides = [
  {
    label: "01",
    title: "WHO WE ARE",
    body: "The Elite HackIllinois Crew. We don't just build apps; we build the future of the jobsite.",
  },
  {
    label: "02",
    title: "THE TECH",
    body: "Omni-Glass: Raspberry Pi Edge + Modal VLM + Actian VectorDB. Hands-free. Eyes-on. Zero manual entry.",
  },
  {
    label: "03",
    title: "THE VISION",
    body: "Turning unstructured field data into instant procurement orders.",
  },
];

const CabInterior = () => {
  const [current, setCurrent] = useState(0);
  const [ctaHovered, setCtaHovered] = useState(false);
  const navigate = useNavigate();

  const next = useCallback(() => setCurrent((c) => Math.min(c + 1, slides.length)), []);
  const prev = useCallback(() => setCurrent((c) => Math.max(c - 1, 0)), []);

  useEffect(() => {
    const handleKey = (e: KeyboardEvent) => {
      if (e.key === "ArrowRight" || e.key === " ") next();
      if (e.key === "ArrowLeft") prev();
    };
    window.addEventListener("keydown", handleKey);
    return () => window.removeEventListener("keydown", handleKey);
  }, [next, prev]);

  const isCTA = current === slides.length;

  return (
    <div className="fixed inset-0 bg-background flex items-center justify-center overflow-hidden">
      {/* Cockpit vignette */}
      <div
        className="absolute inset-0 pointer-events-none"
        style={{
          background: "radial-gradient(ellipse at center, transparent 40%, hsl(0 0% 0% / 0.7) 100%)",
        }}
      />

      {/* Corner HUD decorations */}
      <div className="absolute top-6 left-6 font-hud text-xs text-primary/50 tracking-widest animate-text-flicker">
        CSYMBIOTE v0.1
      </div>
      <div className="absolute top-6 right-6 font-hud text-xs text-primary/50 tracking-widest">
        SYS:ONLINE
      </div>
      <div className="absolute bottom-6 left-6 font-hud text-xs text-muted-foreground tracking-widest">
        {isCTA ? "READY" : `SLIDE ${String(current + 1).padStart(2, "0")} / ${String(slides.length).padStart(2, "0")}`}
      </div>

      {/* Horizontal HUD lines */}
      <div className="absolute top-0 left-0 right-0 h-px bg-primary/10" />
      <div className="absolute bottom-0 left-0 right-0 h-px bg-primary/10" />

      <div className="relative z-10 w-full max-w-2xl px-6">
        <AnimatePresence mode="wait">
          {!isCTA ? (
            <motion.div
              key={current}
              initial={{ opacity: 0, y: 30 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -30 }}
              transition={{ duration: 0.4 }}
              className="glass-card rounded-lg p-8 md:p-12"
            >
              <div className="font-hud text-xs text-primary/60 tracking-[0.3em] mb-2">
                {slides[current].label}
              </div>
              <h2 className="font-hud text-2xl md:text-4xl font-bold text-primary mb-6 tracking-wider">
                {slides[current].title}
              </h2>
              <p className="font-body text-lg md:text-xl text-foreground/80 leading-relaxed">
                {slides[current].body}
              </p>
            </motion.div>
          ) : (
            <motion.div
              key="cta"
              initial={{ opacity: 0, scale: 0.9 }}
              animate={{ opacity: 1, scale: 1 }}
              transition={{ duration: 0.5 }}
              className="flex flex-col items-center gap-8"
            >
              <div className="font-hud text-sm text-primary/60 tracking-[0.4em]">
                AUTHORIZATION COMPLETE
              </div>
              <button
                className="relative group px-10 py-5 bg-primary text-primary-foreground font-hud text-lg md:text-xl tracking-wider rounded overflow-hidden transition-all duration-300 hover:shadow-[0_0_40px_hsl(47_100%_50%/0.4)]"
                onMouseEnter={() => setCtaHovered(true)}
                onMouseLeave={() => setCtaHovered(false)}
                onClick={() => navigate("/admin/dashboard")}
              >
                {/* Scan line effect */}
                {ctaHovered && (
                  <div className="absolute inset-0 overflow-hidden pointer-events-none">
                    <div className="absolute inset-x-0 h-8 bg-gradient-to-b from-transparent via-primary-foreground/20 to-transparent animate-scan-line" />
                  </div>
                )}
                <span className="relative z-10">
                  {ctaHovered ? "SYSTEM AUTHORIZED" : "ENTER COMMAND CENTER"}
                </span>
              </button>
            </motion.div>
          )}
        </AnimatePresence>

        {/* Navigation arrows */}
        <div className="flex items-center justify-between mt-10">
          <button
            onClick={prev}
            disabled={current === 0}
            className="p-3 rounded border border-border text-muted-foreground hover:text-primary hover:border-primary transition-colors disabled:opacity-20 disabled:cursor-not-allowed"
          >
            <ChevronLeft className="w-5 h-5" />
          </button>
          {/* Progress dots */}
          <div className="flex gap-2">
            {[...slides, null].map((_, i) => (
              <div
                key={i}
                className={`w-2 h-2 rounded-full transition-colors ${
                  i === current ? "bg-primary" : "bg-border"
                }`}
              />
            ))}
          </div>
          <button
            onClick={next}
            disabled={isCTA}
            className="p-3 rounded border border-border text-muted-foreground hover:text-primary hover:border-primary transition-colors disabled:opacity-20 disabled:cursor-not-allowed"
          >
            <ChevronRight className="w-5 h-5" />
          </button>
        </div>
      </div>
    </div>
  );
};

export default CabInterior;
