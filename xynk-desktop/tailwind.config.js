/** @type {import('tailwindcss').Config} */
export default {
  content: [
    './src/renderer/**/*.{ts,tsx}',
    './index.html',
  ],
  darkMode: 'class',
  theme: {
    extend: {
      colors: {
        xynk: {
          ink: '#121629',
          panel: '#252946',
          panelSoft: '#343858',
          line: '#7774AA',
          text: '#F8F5FF',
          muted: '#BDBAD4',
          lime: '#D68CFA',
          mint: '#75B9F8',
          coral: '#F581CA',
        },
        primary: '#F1A0FF',
        secondary: '#73D8FF',
        surface: '#252946',
        'surface-soft': '#343858',
        border: '#7774AA',
        onPrimary: '#121629',
      },
      fontFamily: {
        sans: ['Inter', 'system-ui', 'sans-serif'],
        condensed: ['Inter Tight', 'system-ui', 'sans-serif'],
        medium: ['Inter', 'system-ui', 'sans-serif'],
      },
      borderRadius: {
        'xl': '1rem',
        '2xl': '1.125rem',
        '3xl': '1.5rem',
        '4xl': '1.75rem',
      },
      boxShadow: {
        'glow-lime': '0 0 24px 2px rgba(241, 160, 255, 0.47)',
        'glow-mint': '0 0 24px 2px rgba(115, 216, 255, 0.47)',
        'inner-glow': 'inset 0 0 24px 2px rgba(241, 160, 255, 0.1)',
      },
      animation: {
        'slide-up': 'slideUp 0.26s ease-out',
        'fade-in': 'fadeIn 0.18s ease-out',
      },
      keyframes: {
        slideUp: {
          '0%': { transform: 'translateY(10px)', opacity: '0' },
          '100%': { transform: 'translateY(0)', opacity: '1' },
        },
        fadeIn: {
          '0%': { opacity: '0' },
          '100%': { opacity: '1' },
        },
      },
    },
  },
  plugins: [],
};
