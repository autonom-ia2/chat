// Kit de demo (#2140): prints por jornada no painel local, com o Playwright do snapshot.
// Uso (o bin/demo chama no M2): node prints.cjs <jornadas.json> <saida>
// Ambiente: PW (módulo playwright), BASE (http://localhost:<porta>), DEMO_SENHA_ARQUIVO (arquivo 0600 com a
// senha: ela não passa pelo argv nem pelo ambiente), DEMO_ESTADO_DIR, DEMO_RELATO.
// O relato.json (URLs locais e erros) fica no M2, em DEMO_RELATO; só os PNGs vão para a worktree.
// Formato do jornadas.json: docs/runbooks/demo-tela-real.md.
/* eslint-disable no-console, no-await-in-loop, no-restricted-syntax */
const fs = require('fs');
const path = require('path');

const { chromium } = require(process.env.PW);

const [arquivoJornadas, saida] = process.argv.slice(2);
const BASE = process.env.BASE;
const TEMPO = Number(process.env.DEMO_TIMEOUT_MS || 300000);
const PERMITIDOS = 'abcdefghijklmnopqrstuvwxyz0123456789-';
// O selo do rack-mini-profiler já sai desligado (DISABLE_MINI_PROFILER=1); o CSS cobre demo antiga.
const SEM_SELO = '.profiler-results{display:none!important}';

const USUARIO_PERMITIDOS = `${PERMITIDOS}._+@`;
const nomeValido = nome =>
  typeof nome === 'string' && nome.length > 0 && [...nome].every(c => PERMITIDOS.includes(c));

const config = JSON.parse(fs.readFileSync(arquivoJornadas, 'utf8'));
const conta = config.conta || 1;
const usuario = config.usuario || 'john@acme.inc';
const larguras = config.larguras || [1440, 390];
const temas = config.temas || ['light'];
// Só estes valores entram no nome do arquivo e no navegador.
const ALTURA = { 1440: 900, 390: 844 };
const TEMAS = ['light', 'dark'];
larguras.forEach(l => {
  if (!Object.hasOwn(ALTURA, String(l))) throw new Error(`largura não aceita: ${l} (use 1440 ou 390)`);
});
temas.forEach(t => {
  if (!TEMAS.includes(t)) throw new Error(`tema não aceito: ${t} (use light ou dark)`);
});

if (![...usuario].every(c => USUARIO_PERMITIDOS.includes(c))) throw new Error(`usuario inválido: ${usuario}`);

const comConta = url => url.split('{conta}').join(String(conta));

for (const jornada of config.jornadas || []) {
  if (!nomeValido(jornada.nome)) throw new Error(`nome de jornada inválido: ${jornada.nome}`);
  for (const etapa of jornada.etapas || []) {
    if (!nomeValido(etapa.nome)) throw new Error(`nome de etapa inválido: ${etapa.nome}`);
  }
}

// Loga UMA vez e guarda o storageState: o fork limita sessões por usuário e o login repetido dá 409.
async function estadoDeLogin(browser) {
  const arquivo = path.join(process.env.DEMO_ESTADO_DIR, `estado-${usuario.split('@')[0]}.json`);
  if (fs.existsSync(arquivo)) {
    const ctx = await browser.newContext({ storageState: arquivo });
    const p = await ctx.newPage();
    await p.goto(`${BASE}/app/accounts/${conta}/dashboard`, { timeout: TEMPO });
    await p.waitForTimeout(3000);
    const valido = !p.url().includes('/app/login');
    await ctx.close();
    if (valido) {
      console.log(`login: reaproveitando ${path.basename(arquivo)} (sem novo login)`);
      return arquivo;
    }
    fs.rmSync(arquivo);
  }
  const ctx = await browser.newContext({ locale: 'pt-BR' });
  const p = await ctx.newPage();
  let statusLogin = null;
  p.on('response', r => {
    if (r.url().includes('/auth/sign_in') && r.request().method() === 'POST') statusLogin = r.status();
  });
  await p.goto(`${BASE}/app/login`, { timeout: TEMPO });
  await p.fill('input[type="email"], input[name="email_address"]', usuario, { timeout: TEMPO });
  await p.fill('input[type="password"]', fs.readFileSync(process.env.DEMO_SENHA_ARQUIVO, 'utf8').trim());
  await p.click('button[type="submit"]');
  try {
    await p.waitForURL('**/app/accounts/**', { timeout: 120000 });
  } catch (e) {
    if (statusLogin === 409) {
      throw new Error('login deu 409 (limite de sessões). Rode: bin/demo psql <slug> "DELETE FROM user_sessions"');
    }
    throw new Error(`login não entrou (HTTP ${statusLogin}): ${e.message.slice(0, 160)}`);
  }
  await ctx.storageState({ path: arquivo });
  await ctx.close();
  console.log(`login: feito uma vez, guardado em ${path.basename(arquivo)}`);
  return arquivo;
}

async function executarPasso(p, passo) {
  const opcoes = { timeout: 60000 };
  if (passo.clicar) await p.locator(passo.clicar).first().click(opcoes);
  else if (passo.preencher) await p.locator(passo.preencher[0]).first().fill(passo.preencher[1], opcoes);
  else if (passo.tecla) await p.keyboard.press(passo.tecla);
  else if (passo.esperar) await p.locator(passo.esperar).first().waitFor({ state: 'visible', ...opcoes });
  else if (passo.pausa) await p.waitForTimeout(passo.pausa);
  else throw new Error(`passo desconhecido: ${JSON.stringify(passo)}`);
}

// Cada jornada usa até duas abas: a logada (storageState) e, para etapas com "sem_login", uma anônima
// (tela de login, página pública). Nenhuma delas faz login de novo.
async function rodarJornada(browser, estado, jornada, tema, largura) {
  const erros = [];
  const abas = {};
  const aba = async semLogin => {
    const tipo = semLogin ? 'anonima' : 'logada';
    if (abas[tipo]) return abas[tipo].p;
    const ctx = await browser.newContext({
      viewport: { width: largura, height: ALTURA[largura] },
      locale: 'pt-BR',
      timezoneId: 'America/Sao_Paulo',
      colorScheme: tema,
      storageState: semLogin ? undefined : estado,
    });
    const p = await ctx.newPage();
    p.on('pageerror', x => erros.push(`pageerror ${x.message.slice(0, 160)}`));
    p.on('response', r => {
      if (r.status() >= 400) erros.push(`${r.status()} ${r.url().split('?')[0]}`);
    });
    abas[tipo] = { ctx, p };
    return p;
  };
  const resultado = [];
  for (const [indice, etapa] of jornada.etapas.entries()) {
    const nome = `${String(indice + 1).padStart(2, '0')}-${etapa.nome}-${tema}-${largura}`;
    const item = { jornada: jornada.nome, etapa: nome };
    const errosAntes = erros.length;
    try {
      const p = await aba(Boolean(etapa.sem_login));
      if (etapa.url) {
        await p.goto(`${BASE}${comConta(etapa.url)}`, { waitUntil: 'domcontentloaded', timeout: TEMPO });
        await p.addStyleTag({ content: SEM_SELO });
        await p.mouse.move(0, 0);
      }
      for (const passo of etapa.passos || []) await executarPasso(p, passo);
      if (etapa.esperar) await p.locator(etapa.esperar).first().waitFor({ state: 'visible', timeout: TEMPO });
      await p.waitForTimeout(etapa.pausa ?? 1500);
      const larguraConteudo = await p.evaluate(() => document.scrollingElement.scrollWidth);
      item.rolagem_lateral = larguraConteudo > largura;
      const arquivo = path.join(saida, jornada.nome, `${nome}.png`);
      fs.mkdirSync(path.dirname(arquivo), { recursive: true });
      await p.screenshot({ path: arquivo, fullPage: Boolean(etapa.pagina_inteira) });
      item.png = path.relative(saida, arquivo);
    } catch (e) {
      item.falhou = e.message.slice(0, 300);
    }
    item.erros = [...new Set(erros.slice(errosAntes))].slice(0, 15);
    item.erros_5xx = item.erros.filter(x => x.startsWith('5')).length;
    resultado.push(item);
  }
  await Promise.all(Object.values(abas).map(({ ctx }) => ctx.close()));
  return resultado;
}

(async () => {
  fs.mkdirSync(saida, { recursive: true });
  const browser = await chromium.launch({ channel: process.env.DEMO_CANAL || 'chrome' });
  const relato = [];
  try {
    const estado = await estadoDeLogin(browser);
    for (const tema of temas) {
      for (const largura of larguras) {
        for (const jornada of config.jornadas) {
          relato.push(...(await rodarJornada(browser, estado, jornada, tema, largura)));
        }
      }
    }
  } finally {
    await browser.close();
  }
  fs.writeFileSync(process.env.DEMO_RELATO, `${JSON.stringify(relato, null, 1)}\n`);
  for (const item of relato) {
    const situacao = item.falhou ? `FALHOU ${item.falhou}` : item.png;
    const extras = [
      item.rolagem_lateral ? 'ROLAGEM LATERAL' : '',
      item.erros.length ? `${item.erros.length} respostas/erros >=400 (${item.erros_5xx} 5xx)` : '',
    ].filter(Boolean);
    console.log(`${item.etapa}: ${situacao}${extras.length ? ` | ${extras.join(' | ')}` : ''}`);
    item.erros.forEach(x => console.log(`    ${x}`));
  }
  const quebradas = relato.filter(i => i.falhou || i.erros_5xx > 0);
  console.log(`prints: ${relato.length - quebradas.length} de ${relato.length} etapas sem falha nem 5xx`);
  process.exit(quebradas.length ? 1 : 0);
})().catch(e => {
  console.error(`FALHOU ${e.message}`);
  process.exit(1);
});
