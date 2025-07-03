import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import path from 'path'
import type { UserConfigExport } from 'vite'

const config: UserConfigExport = defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
  build: {
    outDir: 'dist'
  }
})

export default config