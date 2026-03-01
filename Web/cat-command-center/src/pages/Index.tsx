import { useState, useCallback } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { useNavigate } from "react-router-dom";
import HangarScene from "@/components/three/HangarScene";
import NarrativeOverlay from "@/components/NarrativeOverlay";
import SymbioteLogo from "@/components/SymbioteLogo";
import TransitionOverlay from "@/components/TransitionOverlay";

type Phase = "hangar" | "narrative" | "transition";

const Index = () => {
  const [phase, setPhase] = useState<Phase>("hangar");
  const navigate = useNavigate();

  // When the user clicks the cabin door → start narrative overlay
  const handleDoorClick = useCallback(() => {
    setPhase("narrative");
  }, []);

  // When the user clicks "Enter Command Center" in the narrative
  const handleEnterClick = useCallback(() => {
    setPhase("transition");
  }, []);

  // When the transition loading bar finishes → navigate to dashboard
  const handleTransitionComplete = useCallback(() => {
    navigate("/admin/dashboard");
  }, [navigate]);

  return (
    <div className="relative w-full h-screen overflow-hidden bg-background">
      {/* Symbiote branding — always visible on intro */}
      <SymbioteLogo />

      <AnimatePresence mode="wait">
        {phase !== "transition" && (
          <motion.div
            key="scene"
            exit={{ opacity: 0 }}
            transition={{ duration: 0.5 }}
            className="w-full h-full"
          >
            {/* 3D Scene — always rendered behind narrative */}
            <HangarScene onDoorClick={handleDoorClick} />

            {/* Narrative slides overlay (appears after door click) */}
            <NarrativeOverlay
              active={phase === "narrative"}
              onEnterClick={handleEnterClick}
            />

            {/* Bottom title bar (only in hangar phase) */}
            {phase === "hangar" && (
              <motion.div
                initial={{ opacity: 0, y: 20 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0 }}
                transition={{ duration: 0.6, delay: 0.5 }}
                className="absolute bottom-0 left-0 right-0 p-6 flex items-end justify-between pointer-events-none"
              >
                <div>
                  <h1 className="font-hud text-xl md:text-2xl text-primary tracking-widest">
                    SYMBIOTE
                  </h1>
                  <p className="font-body text-sm text-muted-foreground tracking-wider mt-1">
                    AI-POWERED INSPECTION PLATFORM
                  </p>
                </div>
                <div className="font-hud text-xs text-primary/40 tracking-widest animate-text-flicker">
                  CLICK CABIN TO ENTER
                </div>
              </motion.div>
            )}
          </motion.div>
        )}
      </AnimatePresence>

      {/* Transition overlay — golden loading bar */}
      <TransitionOverlay
        active={phase === "transition"}
        onComplete={handleTransitionComplete}
      />
    </div>
  );
};

export default Index;
