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
    className="glass-primary fixed right-6 bottom-6 z-40 w-14 h-14 rounded-full
      flex items-center justify-center
      transition-all duration-180
      disabled:opacity-50 disabled:cursor-not-allowed disabled:shadow-none
      active:scale-[0.96]"
  >
    {children}
  </button>
));

FloatingActionButton.displayName = 'FloatingActionButton';
