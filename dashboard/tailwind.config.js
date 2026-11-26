/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  darkMode: 'class',
  theme: {
    extend: {
      colors: {
        // Apple iOS / macOS Dark Mode System Colors
        ios: {
          bg: '#000000',           // Pitch black (systemBackground)
          surface: '#121214',      // Elevated background
          card: '#161618',         // Deep crisp Apple obsidian card
          cardHover: '#1f1f23',    // secondarySystemBackground hover
          elevated: '#242428',     // tertiarySystemBackground
          grouped: '#18181b',      // secondarySystemGroupedBackground
          border: 'rgba(255, 255, 255, 0.10)',
          borderBright: 'rgba(255, 255, 255, 0.20)',
          separator: 'rgba(255, 255, 255, 0.08)',
          label: '#ffffff',        // Primary white text
          secondary: '#a1a1a6',    // High-contrast secondary text (Apple HIG)
          subtext: '#98989d',      // Crisp subtext
          tertiary: '#76767c',     // Tertiary muted labels
          blue: '#0a84ff',         // systemBlue
          blueLight: '#409cff',
          red: '#ff453a',          // systemRed
          orange: '#ff9f0a',       // systemOrange
          yellow: '#ffd60a',       // systemYellow
          green: '#30d158',        // systemGreen
          mint: '#63e6e2',         // systemMint
          teal: '#64d2ff',         // systemTeal
          cyan: '#70d7ff',         // systemCyan
          indigo: '#5e5ce6',       // systemIndigo
          purple: '#bf5af2',       // systemPurple
          pink: '#ff375f',         // systemPink
        },
        // Backwards compatible aliases for existing code
        command: {
          950: '#000000',
          900: '#121214',
          850: '#1c1c1e',
          800: '#26262a',
          700: '#2c2c2e',
          600: '#3a3a3c',
          border: 'rgba(255, 255, 255, 0.08)',
          borderBright: 'rgba(10, 132, 255, 0.4)',
        },
        electric: {
          blue: '#0a84ff',
          sky: '#64d2ff',
          accent: '#0071e3',
        },
        tactical: {
          emerald: '#30d158',
          amber: '#ff9f0a',
          crimson: '#ff453a',
          violet: '#bf5af2',
          cyan: '#64d2ff',
          slate: '#8e8e93',
        }
      },
      fontFamily: {
        sans: [
          '-apple-system',
          'BlinkMacSystemFont',
          '"SF Pro Display"',
          '"SF Pro Text"',
          'Inter',
          'system-ui',
          'Segoe UI',
          'Roboto',
          'sans-serif'
        ],
        mono: [
          '"SF Mono"',
          'JetBrains Mono',
          'Menlo',
          'Monaco',
          'Consolas',
          'monospace'
        ],
      },
      borderRadius: {
        'apple': '18px',
        'apple-sm': '12px',
        'apple-lg': '22px',
      },
      boxShadow: {
        'ios-card': '0 4px 20px -2px rgba(0, 0, 0, 0.18), 0 1px 1px 0 rgba(255, 255, 255, 0.08) inset',
        'ios-float': '0 12px 32px -4px rgba(0, 0, 0, 0.28), 0 1px 2px 0 rgba(255, 255, 255, 0.1) inset',
        'ios-pill': '0 2px 8px -1px rgba(0, 0, 0, 0.15)',
      },
      letterSpacing: {
        tightest: '-0.03em',
        tighter: '-0.02em',
        tight: '-0.01em',
      }
    },
  },
  plugins: [],
}
