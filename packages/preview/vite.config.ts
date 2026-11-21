import { defineConfig, type Plugin } from 'vite';
import react from '@vitejs/plugin-react';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const itemDir = path.resolve(here, '../../resources/[veyl]/veyl_inventory/web/images');

/** Serves the real packaged item images at /items/* so the preview uses the same assets as FiveM. */
function itemImages(): Plugin {
  return {
    name: 'veyl-item-images',
    configureServer(server) {
      server.middlewares.use('/items', (req, res, next) => {
        const file = path.join(itemDir, path.basename(decodeURIComponent((req.url ?? '').split('?')[0])));
        if (!file.startsWith(itemDir) || !fs.existsSync(file)) return next();
        const types: Record<string, string> = { '.svg': 'image/svg+xml', '.png': 'image/png', '.webp': 'image/webp' };
        res.setHeader('Content-Type', types[path.extname(file).toLowerCase()] ?? 'application/octet-stream');
        fs.createReadStream(file).pipe(res);
      });
    },
  };
}

// Development only: this app is never built into a FiveM resource.
export default defineConfig({
  plugins: [react(), itemImages()],
  resolve: { alias: { '@veyl/ui': path.resolve(here, '../veyl-ui/src') } },
});
