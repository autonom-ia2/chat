/* eslint-disable no-await-in-loop, no-restricted-syntax -- one page, one screenshot at a time:
   each step drives the same browser tab, so the models are taken in sequence on purpose. */
// Fidelity suite of the e-mail model importer (#1099, delivery D). Reads the pages the rake task
// autonomia:email_import:fidelidade wrote (manifest.json + <model>/original.html and imported.html,
// images already grey, nothing loaded from the network), takes a full-page screenshot of each side
// at 600 and 375 px, and compares them band by band (BAND px tall): the share of pixels that differ
// in each band, a picture of the differences, and per model the similarity (1 - mean band
// difference) and the worst bands. Writes report.json and report.md next to the pages.
//
// It reports and never fails: CI publishes the report as an artifact (continue-on-error) until the
// numbers are stable. The goal registered for each model is 70% of editable area (from the import).
//
//   node scripts/email-import-fidelity/shoot.mjs tmp/email-import-fidelity
//
// Browser: the repository's Playwright (tests/playwright) when installed; otherwise a headless
// Chrome driven over the DevTools protocol (CHROME_PATH, or the usual install places).
import { existsSync } from 'node:fs';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const BAND = 40;
// Sum of the RGB differences above which a pixel counts as different (antialiasing stays below).
const PIXEL_THRESHOLD = 48;
const WORST = 3;
const VIEWPORT_HEIGHT = 900;
const PLAYWRIGHT = resolve(
  'tests/playwright/node_modules/playwright/index.mjs'
);
const CHROMES = [
  process.env.CHROME_PATH,
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/usr/bin/google-chrome',
  '/usr/bin/google-chrome-stable',
  '/usr/bin/chromium',
  '/usr/bin/chromium-browser',
].filter(Boolean);

// ---- browsers: both answer shot(file, width) -> PNG base64 and evaluate(fn, arg) -> value ----

async function playwrightBrowser() {
  const { chromium } = await import(pathToFileURL(PLAYWRIGHT).href);
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ deviceScaleFactor: 1 });
  await context.route(
    url => ['http:', 'https:'].includes(url.protocol),
    route => route.abort()
  );
  const page = await context.newPage();
  return {
    name: 'playwright',
    async shot(file, width) {
      await page.setViewportSize({ width, height: VIEWPORT_HEIGHT });
      await page.goto(pathToFileURL(file).href, { waitUntil: 'load' });
      return (await page.screenshot({ fullPage: true })).toString('base64');
    },
    evaluate: (fn, arg) => page.evaluate(fn, arg),
    close: () => browser.close(),
  };
}

function devtoolsAddress(chrome) {
  return new Promise((done, fail) => {
    let seen = '';
    const timer = setTimeout(
      () => fail(new Error('Chrome did not start')),
      20000
    );
    chrome.stderr.on('data', chunk => {
      seen += chunk;
      const start = seen.indexOf('ws://');
      const end = start === -1 ? -1 : seen.indexOf('\n', start);
      if (end !== -1) {
        clearTimeout(timer);
        done(seen.slice(start, end).trim());
      }
    });
  });
}

async function chromeBrowser() {
  const binary = CHROMES.find(path => existsSync(path));
  if (!binary) throw new Error('No Playwright and no Chrome found');
  const profile = await mkdtemp(join(tmpdir(), 'import-fidelity-'));
  const chrome = spawn(binary, [
    '--headless=new',
    '--disable-gpu',
    '--no-sandbox',
    '--hide-scrollbars',
    '--no-first-run',
    `--user-data-dir=${profile}`,
    '--remote-debugging-port=0',
    'about:blank',
  ]);
  const socket = new WebSocket(await devtoolsAddress(chrome));
  await new Promise(done => {
    socket.addEventListener('open', done);
  });
  let next = 0;
  const waiting = new Map();
  const listeners = [];
  socket.addEventListener('message', ({ data }) => {
    const message = JSON.parse(data);
    if (message.id && waiting.has(message.id)) {
      const { done, fail } = waiting.get(message.id);
      waiting.delete(message.id);
      if (message.error) fail(new Error(message.error.message));
      else done(message.result);
    } else listeners.forEach(listener => listener(message));
  });
  const send = (method, params = {}, sessionId = undefined) =>
    new Promise((done, fail) => {
      next += 1;
      waiting.set(next, { done, fail });
      socket.send(JSON.stringify({ id: next, method, params, sessionId }));
    });
  const { targetId } = await send('Target.createTarget', {
    url: 'about:blank',
  });
  const { sessionId } = await send('Target.attachToTarget', {
    targetId,
    flatten: true,
  });
  const call = (method, params) => send(method, params, sessionId);
  await call('Page.enable');
  await call('Network.enable');
  await call('Network.setBlockedURLs', { urls: ['http://*', 'https://*'] });
  const loaded = () =>
    new Promise(done => {
      const listener = message => {
        if (
          message.method === 'Page.loadEventFired' &&
          message.sessionId === sessionId
        ) {
          listeners.splice(listeners.indexOf(listener), 1);
          done();
        }
      };
      listeners.push(listener);
    });
  return {
    name: 'chrome',
    async shot(file, width) {
      await call('Emulation.setDeviceMetricsOverride', {
        width,
        height: VIEWPORT_HEIGHT,
        deviceScaleFactor: 1,
        mobile: false,
      });
      const load = loaded();
      await call('Page.navigate', { url: pathToFileURL(file).href });
      await load;
      const { cssContentSize } = await call('Page.getLayoutMetrics');
      const height = Math.ceil(cssContentSize.height);
      const { data } = await call('Page.captureScreenshot', {
        format: 'png',
        captureBeyondViewport: true,
        clip: { x: 0, y: 0, width, height, scale: 1 },
      });
      return data;
    },
    async evaluate(fn, arg) {
      const { result, exceptionDetails } = await call('Runtime.evaluate', {
        expression: `(${fn})(${JSON.stringify(arg)})`,
        awaitPromise: true,
        returnByValue: true,
      });
      if (exceptionDetails) throw new Error(exceptionDetails.text);
      return result.value;
    },
    async close() {
      socket.close();
      const exited = new Promise(done => {
        chrome.once('exit', done);
      });
      chrome.kill();
      await exited;
      await rm(profile, { recursive: true, force: true, maxRetries: 3 });
    },
  };
}

async function openBrowser() {
  if (process.env.FIDELITY_BROWSER !== 'chrome' && existsSync(PLAYWRIGHT)) {
    return playwrightBrowser();
  }
  return chromeBrowser();
}

// ---- the comparison runs in the page: both screenshots on a canvas, band by band ----

/* eslint-disable no-undef */
async function compareInPage({ before, after, band, threshold }) {
  const load = data =>
    new Promise((done, fail) => {
      const image = new Image();
      image.onload = () => done(image);
      image.onerror = () => fail(new Error('screenshot did not load'));
      image.src = `data:image/png;base64,${data}`;
    });
  const [a, b] = await Promise.all([load(before), load(after)]);
  const width = Math.max(a.width, b.width);
  const height = Math.max(a.height, b.height);
  const pixels = image => {
    const canvas = document.createElement('canvas');
    canvas.width = width;
    canvas.height = height;
    const context = canvas.getContext('2d');
    context.fillStyle = '#ffffff';
    context.fillRect(0, 0, width, height);
    context.drawImage(image, 0, 0);
    return context.getImageData(0, 0, width, height).data;
  };
  const pa = pixels(a);
  const pb = pixels(b);
  const out = document.createElement('canvas');
  out.width = width;
  out.height = height;
  const outContext = out.getContext('2d');
  const diff = outContext.createImageData(width, height);
  const bands = [];
  for (let top = 0; top < height; top += band) {
    const bottom = Math.min(top + band, height);
    let different = 0;
    for (let y = top; y < bottom; y += 1) {
      for (let x = 0; x < width; x += 1) {
        const i = (y * width + x) * 4;
        const outside =
          y >= a.height || y >= b.height || x >= a.width || x >= b.width;
        const delta =
          Math.abs(pa[i] - pb[i]) +
          Math.abs(pa[i + 1] - pb[i + 1]) +
          Math.abs(pa[i + 2] - pb[i + 2]);
        const differs = outside || delta > threshold;
        if (differs) different += 1;
        const gray = Math.round((pa[i] + pa[i + 1] + pa[i + 2]) / 3);
        diff.data[i] = differs ? 230 : 128 + gray / 2;
        diff.data[i + 1] = differs ? 40 : 128 + gray / 2;
        diff.data[i + 2] = differs ? 40 : 128 + gray / 2;
        diff.data[i + 3] = 255;
      }
    }
    bands.push({ top, bottom, diff: different / ((bottom - top) * width) });
  }
  outContext.putImageData(diff, 0, 0);
  return {
    width,
    heights: { original: a.height, imported: b.height },
    bands,
    picture: out.toDataURL('image/png').split(',')[1],
  };
}
/* eslint-enable no-undef */

const percent = value => `${(value * 100).toFixed(1)}%`;

function summarize(result) {
  const mean =
    result.bands.reduce((sum, item) => sum + item.diff, 0) /
    (result.bands.length || 1);
  const worst = [...result.bands]
    .sort((x, y) => y.diff - x.diff)
    .slice(0, WORST)
    .filter(item => item.diff > 0)
    .map(item => ({
      from: item.top,
      to: item.bottom,
      diff: Number(item.diff.toFixed(3)),
    }));
  return {
    similarity: Number((1 - mean).toFixed(3)),
    heights: result.heights,
    bands: result.bands.length,
    worst,
  };
}

async function compareModel(browser, dir, entry, widths) {
  const shots = {};
  for (const width of widths) {
    const before = await browser.shot(resolve(dir, entry.original), width);
    const after = await browser.shot(resolve(dir, entry.imported), width);
    const result = await browser.evaluate(compareInPage, {
      before,
      after,
      band: BAND,
      threshold: PIXEL_THRESHOLD,
    });
    await writeFile(
      resolve(dir, entry.name, `original-${width}.png`),
      Buffer.from(before, 'base64')
    );
    await writeFile(
      resolve(dir, entry.name, `imported-${width}.png`),
      Buffer.from(after, 'base64')
    );
    await writeFile(
      resolve(dir, entry.name, `diff-${width}.png`),
      Buffer.from(result.picture, 'base64')
    );
    shots[width] = summarize(result);
  }
  return shots;
}

function markdown(report) {
  const { goal, widths } = report;
  const lines = [
    '# Fidelidade do importador de modelos de e-mail',
    '',
    `Meta: pelo menos ${percent(goal)} de área editável em cada modelo. Semelhança = 1 − média da diferença de pixels por faixa de ${BAND} px, com as imagens trocadas por cinza. Relatório, não trava.`,
    '',
    `Navegador: ${report.browser}. Modelos: ${report.models.length}. Na meta: ${report.models.filter(model => model.goal_met).length}.`,
    '',
    `| Modelo | Área editável | Meta | ${widths.map(width => `Semelhança ${width}px`).join(' | ')} | Pior faixa (${widths[0]}px) |`,
    `|---|---|---|${widths.map(() => '---').join('|')}|---|`,
  ];
  report.models.forEach(model => {
    if (model.error) {
      lines.push(
        `| ${model.name} | erro: ${model.error} | — | ${widths.map(() => '—').join(' | ')} | — |`
      );
      return;
    }
    const worst = model.shots[widths[0]]?.worst?.[0];
    lines.push(
      `| ${model.name} | ${percent(model.editable_area_ratio)} | ${model.goal_met ? 'sim' : 'NÃO'} | ${widths
        .map(width =>
          model.shots[width] ? percent(model.shots[width].similarity) : '—'
        )
        .join(
          ' | '
        )} | ${worst ? `${worst.from}–${worst.to}px (${percent(worst.diff)})` : '—'} |`
    );
  });
  lines.push(
    '',
    'Cada pasta traz original-*.png, imported-*.png e diff-*.png (vermelho onde difere).',
    ''
  );
  return lines.join('\n');
}

// A model the import refused keeps its error; one the browser could not draw, the browser's.
async function measured(browser, dir, entry, widths) {
  if (entry.error) return entry;
  try {
    return { ...entry, shots: await compareModel(browser, dir, entry, widths) };
  } catch (error) {
    return { ...entry, error: error.message };
  }
}

async function main() {
  const dir = resolve(process.argv[2] || 'tmp/email-import-fidelity');
  const manifest = JSON.parse(
    await readFile(resolve(dir, 'manifest.json'), 'utf8')
  );
  const browser = await openBrowser();
  const models = [];
  try {
    for (const entry of manifest.fixtures) {
      models.push(await measured(browser, dir, entry, manifest.widths));
      process.stdout.write(`${entry.name}\n`);
    }
  } finally {
    await browser.close();
  }
  const report = {
    goal: manifest.goal,
    widths: manifest.widths,
    browser: browser.name,
    band: BAND,
    models,
  };
  await writeFile(resolve(dir, 'report.json'), JSON.stringify(report, null, 2));
  await writeFile(resolve(dir, 'report.md'), markdown(report));
  process.stdout.write(`${resolve(dir, 'report.md')}\n`);
}

main().catch(error => {
  process.stderr.write(`${error.stack || error.message}\n`);
  process.exitCode = 1;
});
