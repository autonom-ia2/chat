// #2776 (protótipo) — grava os clipes do vídeo no painel de demonstração, 1440x900, com cursor visível e ritmo de
// gente. A demo não tem IA: as chamadas do Construtor (build_threads), do agente rascunho e do "Testar" (test +
// ai_requests) são respondidas aqui, pela rede (page.route), com o roteiro fictício de agentes.json. O resto do
// painel é o de verdade.
// Uso no M2 (mesmo ambiente do prints.cjs do kit): node gravar.cjs <agentes.json> <saida> [clipe...]
// Ambiente: PW, BASE, DEMO_ESTADO_DIR (com o estado de login do John já gravado pelo bin/demo prints).
/* eslint-disable no-console, no-await-in-loop, no-restricted-syntax */
const fs = require('fs');
const path = require('path');

const { chromium } = require(process.env.PW);

const [arquivo, saida, ...soEstes] = process.argv.slice(2);
const BASE = process.env.BASE;
const CONTA = 1;
const TAMANHO = { width: 1440, height: 900 };
const roteiro = JSON.parse(fs.readFileSync(arquivo, 'utf8'));
const estado = path.join(process.env.DEMO_ESTADO_DIR, 'estado-john.json');
const ABERTURA = 'Oi! Me conta o que esse agente vai fazer. Pode ser do seu jeito.';

// Cursor desenhado na página (o vídeo do Playwright não mostra o do sistema).
const CURSOR = `
(() => {
  const pôr = () => {
    if (document.getElementById('cursor-demo')) return;
    const c = document.createElement('div');
    c.id = 'cursor-demo';
    c.style.cssText = 'position:fixed;left:0;top:0;width:22px;height:22px;z-index:2147483647;pointer-events:none;' +
      'transform:translate(-3px,-2px);transition:transform 40ms linear;';
    c.innerHTML = '<svg width="22" height="22" viewBox="0 0 24 24"><path d="M4 2l16 10-7 1.5L9.5 21z" ' +
      'fill="#111" stroke="#fff" stroke-width="1.5" stroke-linejoin="round"/></svg>';
    document.body.appendChild(c);
    window.addEventListener('mousemove', e => {
      c.style.left = e.clientX + 'px';
      c.style.top = e.clientY + 'px';
    }, true);
    window.addEventListener('mousedown', () => { c.style.transform = 'translate(-3px,-2px) scale(0.85)'; }, true);
    window.addEventListener('mouseup', () => { c.style.transform = 'translate(-3px,-2px)'; }, true);
  };
  if (document.body) pôr(); else document.addEventListener('DOMContentLoaded', pôr);
})();`;

const pausa = (p, ms) => p.waitForTimeout(ms);

let mouse = { x: 720, y: 450 };
async function irAte(p, seletor) {
  const alvo = p.locator(seletor).first();
  await alvo.waitFor({ state: 'visible', timeout: 60000 });
  await alvo.scrollIntoViewIfNeeded();
  const caixa = await alvo.boundingBox();
  const x = caixa.x + caixa.width / 2;
  const y = caixa.y + Math.min(caixa.height / 2, 22);
  await p.mouse.move(x, y, { steps: 28 });
  mouse = { x, y };
  await pausa(p, 250);
  return alvo;
}
async function clicar(p, seletor) {
  const alvo = await irAte(p, seletor);
  await alvo.click();
  await pausa(p, 400);
}
async function digitar(p, seletor, texto) {
  await clicar(p, seletor);
  await p.keyboard.type(texto, { delay: 38 });
  await pausa(p, 500);
}

const json = (route, corpo, status = 200) =>
  route.fulfill({ status, contentType: 'application/json', body: JSON.stringify(corpo) });

// O Construtor: abre com a pergunta inicial, faz UMA pergunta depois do que a pessoa contou e fecha na segunda
// resposta (needs_more_info:false), com o rascunho já pronto. `ferramentas_sugeridas` é a escolha do modelo.
function simularRede(p, ag) {
  const threadId = ag.id + 50000;
  const mensagens = [];
  let respostasDaPessoa = 0;
  let pronto = false;
  let pendente = null;
  let pedidos = 0;
  const estadoDoThread = () => ({
    payload: {
      id: threadId,
      agent_id: ag.id,
      status: pendente ? 'processing' : 'ready',
      messages: [...mensagens],
      state: {
        needs_more_info: !pronto,
        next_question: pronto ? null : mensagens.filter(m => m.role === 'assistant').at(-1)?.content || null,
        turn: respostasDaPessoa,
        applied: pronto,
        no_materials_declared: false,
        error: null,
        error_fields: [],
        truncated_fields: [],
      },
      created_at: '2026-11-09T14:00:00Z',
      updated_at: '2026-11-09T14:00:00Z',
    },
  });
  const responder = () => {
    if (respostasDaPessoa === 0) mensagens.push({ role: 'assistant', content: ABERTURA });
    else if (respostasDaPessoa === 1) mensagens.push({ role: 'assistant', content: ag.pergunta });
    else pronto = true;
    pendente = null;
  };
  const agente = () => ({
    id: ag.id,
    name: pronto ? ag.nome : 'Novo agente',
    agent_type: 'custom',
    actuation: 'external',
    status: 'draft',
    mode: 'guided',
    enabled: false,
    starter_questions: pronto ? [ag.teste] : [],
    greeting: `Oi! Eu sou ${pronto ? ag.nome : 'o agente'}. Como posso ajudar?`,
    tone: ag.jeito,
    has_instruction: pronto,
    config: { response_window: null, canal_pedido: 'whatsapp' },
    channels_count: 0,
    tem_onde_trabalhar: false,
    ajuda: [],
    ajudante: false,
    na_equipe: false,
    ferramentas_ligadas: 0,
    ferramentas_sugeridas: pronto ? ag.ferramentas : [],
    created_at: '2026-11-09T14:00:00Z',
    updated_at: '2026-11-09T14:00:00Z',
  });

  // O Playwright tenta a rota registrada por último primeiro: o coringa do rascunho vai antes das específicas.
  return p
    .route(`**/api/v1/accounts/*/autonomia/agents/${ag.id}/**`, route =>
      route.request().method() === 'GET' ? json(route, { payload: [] }) : route.fallback()
    )
    .then(() => Promise.all([
    p.route('**/api/v1/accounts/*/autonomia/build_threads', route => {
      if (route.request().method() !== 'POST') return route.fallback();
      pendente = setTimeout(responder, 1800);
      return json(route, estadoDoThread(), 202);
    }),
    p.route(`**/api/v1/accounts/*/autonomia/build_threads/${threadId}/messages`, route => {
      const corpo = route.request().postDataJSON() || {};
      if (corpo.message && !corpo.force_close) {
        mensagens.push({ role: 'user', content: corpo.message });
        respostasDaPessoa += 1;
      }
      if (corpo.force_close) respostasDaPessoa = Math.max(respostasDaPessoa, 2);
      pendente = setTimeout(responder, 2600);
      return json(route, estadoDoThread(), 202);
    }),
    p.route(`**/api/v1/accounts/*/autonomia/build_threads/${threadId}`, route => json(route, estadoDoThread())),
    p.route(`**/api/v1/accounts/*/autonomia/agents/${ag.id}`, route => json(route, agente())),
    p.route(`**/api/v1/accounts/*/autonomia/agents/${ag.id}/test`, route => {
      pedidos += 1;
      return json(route, { id: `t${pedidos}`, status: 'pending', poll_url: `/api/v1/accounts/${CONTA}/ai_requests/t${pedidos}` }, 202);
    }),
    p.route('**/api/v1/accounts/*/ai_requests/*', route =>
      json(route, {
        status: 'done',
        result: {
          reply: ag.resposta.join('\n\n'),
          confidence: 0.92,
          handoff: { should: false, reason: null },
          answered_from_knowledge: false,
          used_knowledge: [],
          humanized: true,
          chunks: ag.resposta.map((text, i) => ({ text, type: 'text', delay_ms: i ? 1400 : 600 })),
        },
      })
    ),
  ]));
}

const ALTURA = { 1440: 900, 390: 844 };
let largura = 1440;
let clipe = '';
let foto = 0;
// Print da etapa, como os do kit: <clipe>/<NN>-<etapa>-light-<largura>.png.
async function print(p, etapa) {
  foto += 1;
  const pasta = path.join(saida, 'prints', clipe);
  fs.mkdirSync(pasta, { recursive: true });
  await p.screenshot({ path: path.join(pasta, `${String(foto).padStart(2, '0')}-${etapa}-light-${largura}.png`) });
}

async function novoContexto(browser, nome) {
  clipe = nome;
  foto = 0;
  const pasta = path.join(saida, 'bruto', nome);
  fs.mkdirSync(pasta, { recursive: true });
  const ctx = await browser.newContext({
    viewport: { width: largura, height: ALTURA[largura] },
    ...(largura === 1440 ? { recordVideo: { dir: pasta, size: TAMANHO } } : {}),
    locale: 'pt-BR',
    timezoneId: 'America/Sao_Paulo',
    colorScheme: 'light',
    storageState: estado,
  });
  await ctx.addInitScript(CURSOR);
  await ctx.addInitScript(() => {
    const css = document.createElement('style');
    css.textContent = '.profiler-results{display:none!important}';
    document.addEventListener('DOMContentLoaded', () => document.head.appendChild(css));
  });
  return ctx;
}

async function gravarAgente(browser, ag) {
  const ctx = await novoContexto(browser, ag.clipe);
  const p = await ctx.newPage();
  await simularRede(p, ag);
  await p.goto(`${BASE}/app/accounts/${CONTA}/agents/new?modelo=custom`, { waitUntil: 'domcontentloaded' });
  await p.mouse.move(mouse.x, mouse.y);
  await p.locator('[data-fala="agente"]').first().waitFor({ timeout: 60000 });
  await pausa(p, 2200);
  await print(p, 'construtor-abre');
  // (a) a pessoa conta o que ele faz
  await digitar(p, 'form textarea', ag.conta);
  await clicar(p, '[data-enviar]');
  await p.locator(`[data-fala="agente"]:has-text("${ag.pergunta.slice(0, 20)}")`).first().waitFor({ timeout: 60000 });
  await pausa(p, 1800);
  await print(p, 'contou-o-que-faz');
  await digitar(p, 'form textarea', ag.jeito);
  await clicar(p, '[data-enviar]');
  // (b) o Confira: "já vem com estas ferramentas"
  await p.locator('[data-ja-vem]').waitFor({ timeout: 90000 });
  await pausa(p, 1500);
  await print(p, 'confira-ja-vem-com');
  for (const id of ag.ferramentas) {
    await irAte(p, `[data-ja-vem-item="${id}"]`);
    await pausa(p, 700);
  }
  await pausa(p, 1200);
  // (c) o Testar: uma conversa curta em que a ferramenta resolve
  await clicar(p, `[data-perguntas] button:has-text("${ag.teste.slice(0, 18)}")`);
  await p.locator(`[data-balao="agente"]:has-text("${ag.resposta.at(-1).slice(0, 18)}")`).waitFor({ timeout: 60000 });
  await pausa(p, 2500);
  await print(p, 'testar-resolve');
  await pausa(p, 2500);
  await p.close();
  await ctx.close();
}

// Clipe à parte: a vitrine e o "incluir pela vitrine" (Valor do carro para a Ana), e o cartão "pode ganhar".
async function gravarVitrine(browser) {
  const ctx = await novoContexto(browser, '0-vitrine');
  const p = await ctx.newPage();
  await p.goto(`${BASE}/app/accounts/${CONTA}/agents/ferramentas-prontas`, { waitUntil: 'domcontentloaded' });
  await p.mouse.move(mouse.x, mouse.y);
  await p.locator('[data-vitrine-cartao="FIPE"]').waitFor({ timeout: 60000 });
  await pausa(p, 2500);
  await irAte(p, '[data-vitrine-destaque]');
  await pausa(p, 1500);
  await digitar(p, '[data-vitrine-busca]', 'valor do carro');
  await pausa(p, 1200);
  await clicar(p, '[data-vitrine-cartao="FIPE"]');
  await pausa(p, 2500);
  await clicar(p, '[data-experimentar]');
  await p.locator('[data-experimente-resultado]').waitFor({ timeout: 30000 });
  await pausa(p, 2500);
  await clicar(p, '[data-vitrine-agentes] >> text=Ana');
  await irAte(p, '[data-vitrine-quando]');
  await pausa(p, 2000);
  await clicar(p, '[data-vitrine-ensinar]');
  await p.locator('[data-vitrine-sucesso]').waitFor({ timeout: 30000 });
  await pausa(p, 2500);
  await clicar(p, '[data-vitrine-ver-agente]');
  await p.locator('[data-pronta="FIPE"]').waitFor({ timeout: 60000 });
  await pausa(p, 3500);
  await p.keyboard.press('Escape');
  await pausa(p, 1500);
  // O cartão "pode ganhar" (a próxima do ramo que a Ana ainda não tem): um toque.
  await irAte(p, '[data-vitrine-sugestao]');
  await pausa(p, 2000);
  await clicar(p, '[data-vitrine-sugestao-incluir]');
  await pausa(p, 3000);
  await p.close();
  await ctx.close();
}

(async () => {
  if (!fs.existsSync(estado)) throw new Error(`sem login gravado em ${estado}: rode antes o bin/demo prints com o John`);
  const browser = await chromium.launch({ channel: process.env.DEMO_CANAL || 'chrome' });
  const relato = [];
  try {
    if (!soEstes.length || soEstes.includes('0-vitrine')) {
      try {
        await gravarVitrine(browser);
        relato.push({ clipe: '0-vitrine', ok: true });
      } catch (e) {
        relato.push({ clipe: '0-vitrine', falhou: e.message.slice(0, 300) });
      }
    }
    for (const ag of roteiro.agentes) {
      if (soEstes.length && !soEstes.includes(ag.clipe)) continue;
      try {
        await gravarAgente(browser, ag);
        relato.push({ clipe: ag.clipe, ok: true });
      } catch (e) {
        relato.push({ clipe: ag.clipe, falhou: e.message.slice(0, 300) });
      }
    }
    // Celular: só prints (sem vídeo), de um agente, para conferir o bloco "já vem com" em 390.
    largura = 390;
    const celular = roteiro.agentes.find(ag => ag.clipe === '2-auto');
    if (!soEstes.length || soEstes.includes('celular')) {
      try {
        await gravarAgente(browser, { ...celular, clipe: '2-auto-celular' });
        relato.push({ clipe: '2-auto-celular', ok: true });
      } catch (e) {
        relato.push({ clipe: '2-auto-celular', falhou: e.message.slice(0, 300) });
      }
    }
  } finally {
    await browser.close();
  }
  console.log(JSON.stringify(relato, null, 2));
})();
