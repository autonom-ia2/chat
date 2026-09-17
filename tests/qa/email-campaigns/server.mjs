import { createServer } from 'vite';
import vue from '@vitejs/plugin-vue';
import postcss from 'postcss';
import tailwindcss from 'tailwindcss';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { readdir, stat, writeFile, mkdir, realpath } from 'node:fs/promises';
export const root = resolve(
  dirname(fileURLToPath(import.meta.url)),
  '../../..'
);
export const output = resolve(root, 'tmp/email436/visual');
export async function buildUtilities() {
  // Use production Tailwind config/content, including edits newer than the bundle.
  // The built dashboard remains responsible for theme/base/component styles.
  const result = await postcss([
    tailwindcss(resolve(root, 'tailwind.config.js')),
  ]).process('@tailwind utilities;', {
    from: resolve(root, 'tests/qa/email-campaigns/utilities.css'),
  });
  await mkdir(output, { recursive: true });
  await writeFile(resolve(output, 'current-utilities.css'), result.css);
  return '/tmp/email436/visual/current-utilities.css';
}
export async function startServer() {
  await mkdir(output, { recursive: true });
  const assets = resolve(root, 'public/vite-test/assets');
  const styles = await Promise.all(
    (await readdir(assets))
      .filter(name => /^dashboard-.*\.css$/.test(name))
      .map(async name => ({
        name,
        time: (await stat(resolve(assets, name))).mtimeMs,
      }))
  );
  styles.sort((a, b) => b.time - a.time);
  if (!styles.length)
    throw new Error('Built dashboard CSS missing; no substitute CSS permitted');
  const css = `/vite-test/assets/${styles[0].name}`;
  const utilities = await buildUtilities();
  // Mirrors vite.shared.ts; resolve against this repository, never the caller cwd.
  const alias = {
    vue: 'vue/dist/vue.esm-bundler.js',
    ...Object.fromEntries(
      Object.entries({
        components: 'dashboard/components',
        next: 'dashboard/components-next',
        v3: 'v3',
        dashboard: 'dashboard',
        helpers: 'shared/helpers',
        shared: 'shared',
        survey: 'survey',
        widget: 'widget',
        assets: 'dashboard/assets',
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
    plugins: [
      vue({
        template: {
          compilerOptions: { isCustomElement: tag => tag === 'ninja-keys' },
        },
      }),
    ],
    optimizeDeps: { entries: ['tests/qa/email-campaigns/entry.js'] },
    server: {
      host: '127.0.0.1',
      fs: {
        strict: true,
        allow: [root, await realpath(resolve(root, 'node_modules'))],
      },
      port: 3437,
      strictPort: true,
      hmr: false,
      watch: null,
    },
    appType: 'custom',
  });
  server.middlewares.use(async (req, res, next) => {
    if (!req.url.startsWith('/app/accounts/436/crm/campaign-management'))
      return next();
    const html = `<!doctype html><html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="${css}"><link rel="stylesheet" href="${utilities}"></head><body><div id="app"></div><script type="module" src="/tests/qa/email-campaigns/entry.js"></script></body></html>`;
    res.setHeader('Content-Type', 'text/html');
    res.end(await server.transformIndexHtml(req.url, html));
  });
  const metadata = {
    pid: process.pid,
    host: '127.0.0.1',
    port: 3437,
    css,
    utilities,
    startedAt: new Date().toISOString(),
    listening: false,
  };
  await writeFile(
    resolve(output, 'server.json'),
    JSON.stringify(metadata, null, 2)
  );
  try {
    await server.listen();
    metadata.listening = true;
    await writeFile(
      resolve(output, 'server.json'),
      JSON.stringify(metadata, null, 2)
    );
  } catch (error) {
    await server.close();
    metadata.error = error.message;
    metadata.closedAt = new Date().toISOString();
    await writeFile(
      resolve(output, 'server.json'),
      JSON.stringify(metadata, null, 2)
    );
    throw error;
  }
  return { server, css, utilities };
}
