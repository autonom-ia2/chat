import { createServer } from 'vite';
import vue from '@vitejs/plugin-vue';
import postcss from 'postcss';
import tailwindcss from 'tailwindcss';
import { readFile, readdir, stat, writeFile, mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../../..');
const output = resolve(root, '.codex/800');
await mkdir(output, { recursive: true });
const files = await readdir(resolve(root, 'public/vite-test/assets'));
const styles = await Promise.all(
  files
    .filter(name => name.startsWith('dashboard-') && name.endsWith('.css'))
    .map(async name => ({
      name,
      time: (await stat(resolve(root, 'public/vite-test/assets', name)))
        .mtimeMs,
    }))
);
styles.sort((a, b) => b.time - a.time);
if (!styles.length)
  throw new Error('Build the actual dashboard before visual QA');
const utilities = await postcss([
  tailwindcss(resolve(root, 'tailwind.config.js')),
]).process('@tailwind utilities;', {
  from: resolve(root, 'tests/qa/email-workspace/utilities.css'),
});
await writeFile(resolve(output, 'utilities.css'), utilities.css);
const aliases = Object.fromEntries(
  Object.entries({
    dashboard: 'dashboard',
    shared: 'shared',
    assets: 'dashboard/assets',
    components: 'dashboard/components',
    helpers: 'shared/helpers',
    next: 'dashboard/components-next',
  }).map(([key, value]) => [key, resolve(root, 'app/javascript', value)])
);
const server = await createServer({
  configFile: false,
  envFile: false,
  root,
  publicDir: resolve(root, 'public'),
  cacheDir: resolve(output, 'vite-cache'),
  resolve: { alias: { vue: 'vue/dist/vue.esm-bundler.js', ...aliases } },
  plugins: [vue()],
  optimizeDeps: { entries: ['tests/qa/email-workspace/entry.js'] },
  server: { host: '127.0.0.1', port: 34782, strictPort: true, hmr: false },
  appType: 'custom',
});
const catalog = JSON.parse(
  await readFile(resolve(root, 'db/seeds/email_templates/catalog.json'), 'utf8')
);
const templates = await Promise.all(
  catalog.map(async (item, index) => ({
    id: index + 1,
    account_id: null,
    name: item.name,
    catalog_key: item.key,
    category: item.category,
    body_mjml: await readFile(
      resolve(output, 'models', item.key + '.mjml'),
      'utf8'
    ),
    body_html: await readFile(
      resolve(output, 'models', item.key + '.html'),
      'utf8'
    ),
  }))
);
templates.push({
  ...templates[0],
  id: 101,
  account_id: 800,
  name: 'Convite ao encontro de parceiros',
  catalog_key: null,
  category: 'meus-modelos',
});
const body = templates.find(item => item.catalog_key === 'new-flavor-simple');
const checks = {
  subject: true,
  content: true,
  sender: true,
  recipients: true,
  import: true,
  hygiene: true,
  provider: true,
};
const campaigns = [
  {
    id: 50,
    name: 'Novidades para nossos parceiros',
    subject: 'Conheça as novidades que preparamos para você',
    preheader: 'Uma nova forma de cuidar do relacionamento com seus clientes',
    status: 'draft',
    recipients_count: 1280,
    body_html: body.body_html,
    body_mjml: body.body_mjml,
  },
  {
    id: 51,
    name: 'Convite ao encontro de parceiros',
    subject: '',
    preheader: '',
    status: 'draft',
    recipients_count: 20,
    body_html: '',
    body_mjml: null,
  },
  {
    id: 52,
    name: 'Boletim semanal',
    subject: 'Os destaques da semana',
    status: 'scheduled',
    scheduled_at: '2026-10-05T12:00:00Z',
    recipients_count: 800,
    body_html: templates[4].body_html,
    body_mjml: templates[4].body_mjml,
  },
  {
    id: 53,
    name: 'Boas-vindas à comunidade',
    subject: 'Bem-vindo, vamos começar?',
    status: 'sent',
    sent_count: 960,
    recipients_count: 960,
    body_html: templates[1].body_html,
    body_mjml: templates[1].body_mjml,
    sent_at: '2026-09-29T12:00:00Z',
  },
].map(item => ({
  account_id: 800,
  delivery_mode: 'ses',
  sender_identity_id: 1,
  sender_domain: 'example.com',
  from_name: 'Equipe Chat2You',
  from_email: 'equipe@example.com',
  reply_to: 'atendimento@example.com',
  failed_count: 0,
  sent_count: 0,
  suppressed_count: 4,
  ai_status: 'idle',
  created_at: '2026-09-29T12:00:00Z',
  updated_at: '2026-09-30T12:00:00Z',
  recipient_import: null,
  protection: {
    state: 'healthy',
    mode: 'global',
    provider: { state: 'healthy', observed_at: '2026-09-30T12:00:00Z' },
    current: { sent: 0, hard_bounce: 0, soft_bounce: 0, complaint: 0 },
    capabilities: { reevaluate: true, resume: false, override: false },
  },
  preflight: {
    mode: 'off',
    status: 'ready',
    counts: {
      total: item.recipients_count,
      ready: item.recipients_count - 4,
      protected: 4,
      invalid: 0,
      review: 0,
      unknown: 0,
      unchecked: 0,
    },
    issues_count: 0,
    analysis_only: true,
    can_recheck: true,
  },
  ...item,
  send_readiness: {
    can_send:
      item.status === 'draft' && Boolean(item.subject && item.body_html),
    checks: {
      ...checks,
      subject: Boolean(item.subject),
      content: Boolean(item.body_html),
    },
    eligible_recipients: item.recipients_count - 4,
    protected_recipients: 4,
  },
}));
const events = [];
server.middlewares.use(async (req, res, next) => {
  const url = new URL(req.url, 'http://127.0.0.1:34782');
  if (url.pathname === '/qa/events') {
    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify(events));
    return;
  }
  if (url.pathname.startsWith('/api/')) {
    res.setHeader('Content-Type', 'application/json');
    const path = url.pathname.split('/').filter(Boolean);
    const resource = path[5];
    const id = Number(path[6]);
    const action = path[7];
    let payload;
    events.push({ method: req.method, path: url.pathname });
    if (resource === 'templates')
      payload = id
        ? templates.find(item => item.id === id)
        : templates.map(({ body_html, body_mjml, ...item }) => item);
    if (resource === 'sender_identities')
      payload = {
        payload: {
          sender_identities: [
            { id: 1, domain: 'example.com', status: 'verified' },
          ],
        },
      };
    if (resource === 'campaigns') {
      const campaign = campaigns.find(item => item.id === id);
      if (req.method === 'PATCH') {
        let text = '';
        for await (const chunk of req) text += chunk;
        Object.assign(campaign, JSON.parse(text).email_campaign);
      }
      if (['send_now', 'schedule', 'test_send'].includes(action)) {
        res.statusCode = 403;
        res.end(
          JSON.stringify({
            error: 'QA harness does not send or schedule email',
          })
        );
        return;
      }
      if (!id)
        payload = {
          payload: {
            campaigns: campaigns.filter(
              item =>
                !url.searchParams.get('status') ||
                item.status === url.searchParams.get('status')
            ),
          },
        };
      else if (action === 'placeholders')
        payload = {
          placeholders: [
            'nome',
            'email',
            'contact.name',
            'contact.email',
            'unsubscribe_url',
          ],
        };
      else if (action === 'validate')
        payload = { missing: [], blank_counts: {} };
      else payload = { payload: campaign };
    }
    if (resource === 'reports' && action === 'recipients')
      payload = {
        payload: {
          recipients: [
            {
              id: 1,
              name: 'Pessoa de teste',
              email: 'teste@example.com',
              status: 'pending',
              delivery_mode: 'ses',
            },
          ],
          meta: {
            count: 1,
            total_pages: 1,
            per_page: 50,
            delivery_mode: 'ses',
          },
        },
      };
    if (url.pathname.endsWith('/inboxes')) payload = { payload: [] };
    if (payload === undefined) {
      res.statusCode = 404;
      payload = { error: 'No synthetic fixture for this request' };
    }
    res.end(JSON.stringify(payload));
    return;
  }
  if (!url.pathname.startsWith('/app/accounts/800/')) return next();
  const html = `<!doctype html><html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/vite-test/assets/${styles[0].name}"><link rel="stylesheet" href="/.codex/800/utilities.css"></head><body><div id="app"></div><script type="module" src="/tests/qa/email-workspace/entry.js"></script></body></html>`;
  res.setHeader('Content-Type', 'text/html');
  res.end(await server.transformIndexHtml(req.url, html));
});
await server.listen();
console.log(
  'Actual campaign components, synthetic isolated API: http://127.0.0.1:34782/app/accounts/800/campaigns/email_campaigns'
);
