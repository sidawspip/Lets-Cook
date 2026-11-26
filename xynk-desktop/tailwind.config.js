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
          ink: '#172326',
          panel: '#354044',
          panelSoft: '#465156',
          line: '#8faaa8',
          text: '#f4f7f6',
          muted: '#d0d8da',
          lime: '#79d4bc',
          mint: '#e8c497',
          coral: '#b8a9e2',
        },
        primary: '#79d4bc',
        secondary: '#e8c497',
        surface: '#354044',
        'surface-soft': '#465156',
        border: '#8faaa8',
        onPrimary: '#172326',
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
        'glow-lime': '0 6px 16px rgba(0, 0, 0, 0.18)',
        'glow-mint': '0 6px 16px rgba(0, 0, 0, 0.18)',
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
