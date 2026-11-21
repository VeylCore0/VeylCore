import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));

// One app, built into two resources: `vite build --mode garage` and `vite build --mode dealer`.
const OUT: Record<string, string> = { garage: 'veyl_garages', dealer: 'veyl_dealership' };

export default defineConfig(({ mode }) => ({
  plugins: [react()],
  base: './',
  resolve: { alias: { '@veyl/ui': path.resolve(here, '../veyl-ui/src') } },
  build: {
    outDir: path.resolve(here, `../../resources/[veyl]/${OUT[mode] ?? 'veyl_garages'}/web/dist`),
    emptyOutDir: true,
    sourcemap: false,
  },
}));
