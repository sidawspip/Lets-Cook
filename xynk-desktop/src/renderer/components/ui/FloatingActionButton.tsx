import { forwardRef } from 'react';

export const FloatingActionButton = forwardRef<HTMLButtonElement, {
  onClick: () => void;
  disabled?: boolean;
  children: React.ReactNode;
}>(({ onClick, disabled, children }, ref) => (
  <button
    ref={ref}
    onClick={onClick}
    disabled={disabled}
    className="fixed right-6 bottom-6 z-40 w-14 h-14 rounded-full
      shadow-[0_24px_24px_2px_rgba(158,98,255,0.47)]
      flex items-center justify-center
      transition-all duration-180
      disabled:opacity-50 disabled:cursor-not-allowed disabled:shadow-none
      active:scale-[0.96]"
    style={{
      background: 'linear-gradient(135deg, #FF78C8 0%, #9B6CFF 50%, #45D8FF 100%)',
      border: '1.3px solid rgba(255,255,255,0.6)',
    }}
  >
    {children}
  </button>
));

FloatingActionButton.displayName = 'FloatingActionButton';