// M3 (#1380): o catálogo pt_BR falha no 1º download (500) e responde no 2º. A tela tem de terminar em português.
// Rodadas: (a) sem cache do navegador limpo — a mesma aba já carregou o catálogo antes; (b) aba nova, cache vazio.
// Uso: DEMO_EMAIL=… DEMO_PASSWORD=… node idioma-e.cjs <pasta-de-saida>
// (o login da demo vem do ambiente; nada de usuário ou senha no arquivo)
const path = require('path');
const fs = require('fs');

const { chromium } = require(
  '/Users/Shared/maccluster-workspaces/chat2you/20261011-110147-1fdfc896-57b28b2084-aef1e447/src/tests/playwright/node_modules/playwright'
);

const saida = process.argv[2];
const { DEMO_EMAIL, DEMO_PASSWORD } = process.env;
if (!DEMO_EMAIL || !DEMO_PASSWORD) {
  console.error('Defina DEMO_EMAIL e DEMO_PASSWORD');
  process.exit(2);
}
const BASE = 'http://localhost:3321';
const LISTA = `${BASE}/app/accounts/1/campaigns/modelos-whatsapp`;
fs.mkdirSync(saida, { recursive: true });
const resultado = [];

const entrar = async pagina => {
  await pagina.goto(`${BASE}/app/login`);
  await pagina.fill('input[type="email"], input[name="email_address"]', DEMO_EMAIL);
  await pagina.fill('input[type="password"]', DEMO_PASSWORD);
  await pagina.click('button[type="submit"]');
  await pagina.waitForURL('**/app/accounts/**', { timeout: 90000 });
  await pagina.evaluate(() => fetch('/api/v1/profile', { method: 'PUT', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ profile: { ui_settings: { locale: 'pt_BR' } } }) }));
};

// O 1º pedido do catálogo pt_BR responde 500; os seguintes passam.
const falharPrimeiro = async (contexto, rodada) => {
  const pedidos = [];
  await contexto.route(url => url.pathname.includes('/i18n/locale/pt_BR/index.js'), async route => {
    pedidos.push(route.request().url());
    if (pedidos.length === 1) {
      await route.fulfill({ status: 500, contentType: 'text/plain', body: 'falha simulada' });
      return;
    }
    await route.continue();
  });
  return () => ({ rodada, pedidos });
};

const conferir = async (pagina, rodada, contagem) => {
  await pagina.goto(LISTA);
  // A falha recarrega a página uma vez: espera a tela estabilizar em português.
  await pagina
    .waitForFunction(() => document.querySelector('h1')?.textContent.trim() === 'Modelos de mensagem', null, { timeout: 60000 })
    .catch(() => null);
  await pagina.waitForTimeout(1500);
  const titulo = ((await pagina.textContent('h1').catch(() => '')) || '').trim();
  const marca = await pagina.evaluate(() => window.sessionStorage.getItem('dashboard:locale-reloaded'));
  const lang = await pagina.evaluate(() => document.querySelector('[data-modelo]') ? 'lista' : 'sem-lista');
  await pagina.screenshot({ path: path.join(saida, `m3-${rodada}.png`) });
  const { pedidos } = contagem();
  const ok = titulo === 'Modelos de mensagem';
  resultado.push({ rodada, titulo, ok, pedidosDoCatalogo: pedidos.length, urls: pedidos, lista: lang, marcaDeRecarga: marca });
  console.log(rodada, ok ? 'PORTUGUES' : 'FALHOU', JSON.stringify({ titulo, pedidos: pedidos.length, marca }));
};

(async () => {
  const browser = await chromium.launch({ executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', headless: true });

  // (a) cache do navegador cheio: entra (catálogo já baixado e em cache), depois a falha na volta.
  const a = await browser.newContext({ viewport: { width: 1440, height: 900 }, locale: 'pt-BR' });
  const pa = await a.newPage();
  await entrar(pa);
  await pa.goto(LISTA);
  await pa.waitForTimeout(3000);
  const contaA = await falharPrimeiro(a, 'a-com-cache');
  await conferir(pa, 'a-com-cache', contaA);

  // (b) aba nova, cache vazio: o 1º download do catálogo falha.
  const b = await browser.newContext({ viewport: { width: 1440, height: 900 }, locale: 'pt-BR' });
  const pb = await b.newPage();
  await entrar(pb);
  const contaB = await falharPrimeiro(b, 'b-sem-cache');
  await conferir(pb, 'b-sem-cache', contaB);

  await browser.close();
  fs.writeFileSync(path.join(saida, 'm3-resultado.json'), JSON.stringify(resultado, null, 2));
  process.exitCode = resultado.every(item => item.ok) ? 0 : 1;
})();
