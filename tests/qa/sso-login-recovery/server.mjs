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
export const output = resolve(root, 'tmp/sso-login-recovery/visual');
export const origin = 'http://127.0.0.1:3438';

async function buildUtilities() {
  const result = await postcss([
    tailwindcss(resolve(root, 'tailwind.config.js')),
  ]).process('@tailwind utilities;', {
    from: resolve(root, 'tests/qa/sso-login-recovery/utilities.css'),
  });
  await mkdir(output, { recursive: true });
  await writeFile(resolve(output, 'current-utilities.css'), result.css);
  return '/tmp/sso-login-recovery/visual/current-utilities.css';
}

const syntheticPage = ({
  css,
  utilities,
  eyebrow,
  title,
  message,
  testId,
}) => `<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <title>${title}</title>
    <link rel="stylesheet" href="${css}">
    <link rel="stylesheet" href="${utilities}">
  </head>
  <body class="m-0 grid min-h-screen place-items-center bg-n-brand/5 p-4 text-n-slate-12">
    <main class="box-border w-full max-w-lg rounded-2xl bg-white p-10 shadow-xl ring-1 ring-inset ring-n-container" data-testid="${testId}">
      <p class="m-0 mb-3 text-xs font-bold uppercase tracking-widest text-n-brand">${eyebrow}</p>
      <h1 class="m-0 text-3xl font-bold leading-tight">${title}</h1>
      <p class="mt-3 leading-6 text-n-slate-11">${message}</p>
      <code class="mt-6 block break-all rounded-lg bg-n-alpha-2 p-3 text-n-slate-11" id="qa-location"></code>
    </main>
    <script>document.querySelector('#qa-location').textContent = location.pathname + location.search;</script>
  </body>
</html>`;

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
  if (!styles.length) {
    throw new Error('Built dashboard CSS missing; no substitute CSS permitted');
  }

  const css = `/vite-test/assets/${styles[0].name}`;
  const utilities = await buildUtilities();
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
    optimizeDeps: { entries: ['tests/qa/sso-login-recovery/entry.js'] },
    server: {
      host: '127.0.0.1',
      port: 3438,
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
    if (url.pathname === '/auth/autonomia') {
      res.setHeader('Content-Type', 'text/html; charset=utf-8');
      res.end(
        syntheticPage({
          css,
          utilities,
          eyebrow: 'Synthetic QA target · not real Auth',
          title: 'Returned to Auth login',
          message:
            'This isolated page proves the failed Chatwoot handoff ended and selected the trusted same-origin Auth entry point.',
          testId: 'synthetic-auth-login',
        })
      );
      return;
    }
    if (
      /^\/app\/accounts\/\d+\/(dashboard|conversations\/.+)$/.test(url.pathname)
    ) {
      res.setHeader('Content-Type', 'text/html; charset=utf-8');
      res.end(
        syntheticPage({
          css,
          utilities,
          eyebrow: 'Synthetic QA target · not a backend session',
          title: 'Chatwoot login succeeded',
          message:
            'The real frontend login client accepted the simulated API response and preserved its existing success redirect.',
          testId: 'synthetic-chatwoot-success',
        })
      );
      return;
    }
    if (url.pathname !== '/app/login') {
      next();
      return;
    }

    const html = `<!doctype html><html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="${css}"><link rel="stylesheet" href="${utilities}"></head><body><div id="app"></div><script type="module" src="/tests/qa/sso-login-recovery/entry.js"></script></body></html>`;
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.end(await server.transformIndexHtml(req.url, html));
  });

  const metadata = {
    pid: process.pid,
    host: '127.0.0.1',
    port: 3438,
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
