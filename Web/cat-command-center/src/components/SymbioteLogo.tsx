/**
 * Symbiote branding logo — fixed top-left with a hi-tech "scanning" CSS animation.
 * Renders an SVG-based "S" mark with animated scan line.
 */
const SymbioteLogo = () => {
  return (
    <div className="fixed top-5 left-5 z-50 flex items-center gap-3 select-none">
      {/* Logo mark */}
      <div className="relative w-10 h-10 rounded-full overflow-hidden symbiote-logo-glow">
        {/* Yin-yang style S mark */}
        <svg viewBox="0 0 40 40" className="w-full h-full">
          <defs>
            <linearGradient id="sym-gold" x1="0%" y1="0%" x2="100%" y2="100%">
              <stop offset="0%" stopColor="#FFCD00" />
              <stop offset="100%" stopColor="#B8960A" />
            </linearGradient>
            <linearGradient id="sym-dark" x1="0%" y1="0%" x2="100%" y2="100%">
              <stop offset="0%" stopColor="#3A3A3A" />
              <stop offset="100%" stopColor="#191919" />
            </linearGradient>
          </defs>
          {/* Background circle */}
          <circle cx="20" cy="20" r="19" fill="url(#sym-dark)" stroke="#FFCD00" strokeWidth="1" />
          {/* S-shape */}
          <path
            d="M26 12 C26 12, 14 12, 14 18 C14 24, 26 22, 26 28 C26 34, 14 32, 14 28"
            fill="none"
            stroke="url(#sym-gold)"
            strokeWidth="3.5"
            strokeLinecap="round"
          />
          {/* Eye dot */}
          <circle cx="22" cy="25" r="2" fill="#FFCD00" opacity="0.8" />
        </svg>

        {/* Scanning line effect */}
        <div className="absolute inset-0 overflow-hidden pointer-events-none">
          <div className="symbiote-scan-beam" />
        </div>
      </div>

      {/* Text */}
      <div className="flex flex-col">
        <span className="font-hud text-[11px] text-primary tracking-[0.25em] font-bold leading-none">
          SYMBIOTE
        </span>
        <span className="font-hud text-[7px] text-primary/40 tracking-[0.15em] mt-0.5">
          AI INSPECTOR
        </span>
      </div>
    </div>
  );
};

export default SymbioteLogo;
