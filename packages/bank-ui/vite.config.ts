import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));

// Builds into the FiveM resource. base './' so nui://veyl_banking/web/dist/ paths resolve.
export default defineConfig({
  plugins: [react()],
  base: './',
  resolve: { alias: { '@veyl/ui': path.resolve(here, '../veyl-ui/src') } },
  build: {
    outDir: path.resolve(here, '../../resources/[veyl]/veyl_banking/web/dist'),
    emptyOutDir: true,
    sourcemap: false,
  },
});
