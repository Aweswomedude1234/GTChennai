import { defineConfig } from 'vite';
export default defineConfig({
  base: './',
  server: { port: 5199, strictPort: true },
  build: { target: 'es2022', chunkSizeWarningLimit: 4000 },
  worker: { format: 'es' },
  optimizeDeps: { exclude: ['@dimforge/rapier3d-compat'] },
});
