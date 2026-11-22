interface WaveLoaderProps {
  label?: string;
  size?: number;
  showScrim?: boolean;
}

export function WaveLoader({ label = 'Loading…', size = 48, showScrim = false }: WaveLoaderProps) {
  return (
    <div className="flex flex-col items-center gap-4">
      {showScrim && (
        <div className="fixed inset-0 bg-black/60 backdrop-blur-sm z-[-1]" />
      )}
      <div className="relative flex items-center justify-center" style={{ width: size, height: size }}>
        <svg className="w-full h-full text-xynk-lime" viewBox="0 0 100 100">
          <defs>
            <linearGradient id="waveGradient" x1="0%" y1="0%" x2="100%" y2="0%">
              <stop offset="0%" stopColor="#F1A0FF" />
              <stop offset="50%" stopColor="#73D8FF" />
              <stop offset="100%" stopColor="#FF5D83" />
            </linearGradient>
          </defs>
          {[1, 2, 3, 4, 5].map((i) => (
            <circle
              key={i}
              cx="50"
              cy="50"
              r={10 + i * 8}
              stroke="url(#waveGradient)"
              strokeWidth="3"
              fill="none"
              strokeLinecap="round"
              style={{
                strokeDasharray: '10, 20',
                animation: `wave-draw 1.5s ease-in-out ${i * 0.15}s infinite, wave-rotate 8s linear infinite`,
              }}
            />
          ))}
        </svg>
        <style>{`
          @keyframes wave-draw {
            0% { stroke-dashoffset: 0; stroke-dasharray: 0, 30; }
            50% { stroke-dasharray: 15, 15; }
            100% { stroke-dashoffset: -30; stroke-dasharray: 0, 30; }
          }
          @keyframes wave-rotate {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
          }
        `}</style>
      </div>
      {label && (
        <p className="text-sm font-medium text-white/80 text-center">{label}</p>
      )}
    </div>
  );
}