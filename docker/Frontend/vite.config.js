import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// Nutzt Umgebungsvariablen aus .env-Datei
export default defineConfig({
  plugins: [react()],
  build: {
    outDir: 'dist'
  }
})
