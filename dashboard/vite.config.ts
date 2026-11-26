import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    allowedHosts: [
      'many-kiwis-rhyme.loca.lt',
      'rare-cups-itch.loca.lt',
    ],
  },
})
