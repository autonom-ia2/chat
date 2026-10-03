import { createServer } from 'vite';
import vue from '@vitejs/plugin-vue';
import postcss from 'postcss';
import tailwindcss from 'tailwindcss';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { mkdir, readdir, realpath, stat, writeFile } from 'node:fs/promises';

export const root = resolve(
  dirname(fileURLToPath(import.meta.url)),
  '../../..'
);
export const output = resolve(root, 'tmp/instagram-910/visual');
export const origin = 'http://127.0.0.1:39211';
export const pathname = '/app/accounts/910/settings/inboxes/new/instagram';

export async function startServer() {
  await mkdir(output, { recursive: true });
  const assets = resolve(root, 'public/vite-test/assets');
  const assetNames = await readdir(assets).catch(error => {
    if (error.code === 'ENOENT')
      throw new Error(
        'BLOCKED: built dashboard CSS missing; coordinator must build first'
      );
    throw error;
  });
  const styles = await Promise.all(
    assetNames
      .filter(name => name.startsWith('dashboard-') && name.endsWith('.css'))
      .map(async name => ({
        name,
        time: (await stat(resolve(assets, name))).mtimeMs,
      }))
  );
  styles.sort((a, b) => b.time - a.time);
  if (!styles.length)
    throw new Error(
      'BLOCKED: built dashboard CSS missing; coordinator must build first'
    );
  const css = `/vite-test/assets/${styles[0].name}`;
  const generated = await postcss([
    tailwindcss(resolve(root, 'tailwind.config.js')),
  ]).process('@tailwind utilities;', {
    from: resolve(root, 'tests/qa/instagram-testers/utilities.css'),
  });
  await writeFile(resolve(output, 'current-utilities.css'), generated.css);
  const utilities = '/tmp/instagram-910/visual/current-utilities.css';
  const alias = {
    vue: 'vue/dist/vue.esm-bundler.js',
    ...Object.fromEntries(
      Object.entries({
        dashboard: 'dashboard',
        shared: 'shared',
        assets: 'dashboard/assets',
        components: 'dashboard/components',
        next: 'dashboard/components-next',
        v3: 'v3',
        helpers: 'shared/helpers',
        widget: 'widget',
        survey: 'survey',
      }).map(([key, path]) => [key, resolve(root, 'app/javascript', path)])
    ),
  };
  const server = await createServer({
    configFile: false,
    envFile: false,
    root,
    publicDir: resolve(root, 'public'),
    cacheDir: resolve(output, 'vite-cache'),
    resolve: { alias },
    plugins: [vue()],
    optimizeDeps: { entries: ['tests/qa/instagram-testers/entry.js'] },
    server: {
      host: '127.0.0.1',
      port: 39211,
      strictPort: true,
      hmr: false,
      watch: null,
      fs: {
        strict: true,
        allow: [root, await realpath(resolve(root, 'node_modules'))],
      },
    },
    appType: 'custom',
  });
  server.middlewares.use(async (req, res, next) => {
    const url = new URL(req.url, origin);
    if (url.pathname === '/qa-avatar.svg') {
      res.setHeader('Content-Type', 'image/svg+xml');
      res.end(
        '<svg xmlns="http://www.w3.org/2000/svg" width="80" height="80"><rect width="80" height="80" fill="#475569"/><circle cx="40" cy="28" r="13" fill="#cbd5e1"/><path d="M15 76V62a25 25 0 0 1 50 0v14" fill="#cbd5e1"/></svg>'
      );
      return;
    }
    if (url.pathname !== pathname) {
      next();
      return;
    }
    const html = `<!doctype html><html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="${css}"><link rel="stylesheet" href="${utilities}"></head><body class="bg-n-background text-n-slate-12"><div id="app"></div><script type="module" src="/tests/qa/instagram-testers/entry.js"></script></body></html>`;
    res.setHeader('Content-Type', 'text/html');
    res.end(await server.transformIndexHtml(req.url, html));
  });
  const metadata = {
    pid: process.pid,
    origin,
    css,
    utilities,
    startedAt: new Date().toISOString(),
    listening: false,
  };
  try {
    await writeFile(
      resolve(output, 'server.json'),
      JSON.stringify(metadata, null, 2)
    );
    await server.listen();
    metadata.listening = true;
    await writeFile(
      resolve(output, 'server.json'),
      JSON.stringify(metadata, null, 2)
    );
  } catch (error) {
    await server.close();
    metadata.error = error.message;
    await writeFile(
      resolve(output, 'server.json'),
      JSON.stringify(metadata, null, 2)
    );
    throw error;
  }
  return { server, css, utilities };
}
