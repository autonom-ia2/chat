#!/usr/bin/env node
// Motor genérico de gravação dos vídeos de trajeto da Central de Ajuda.
//
// Uso: node scripts/central-de-ajuda/gravar-trajeto.mjs <id>
//   ex.: node scripts/central-de-ajuda/gravar-trajeto.mjs 02.04
//
// Lê o roteiro declarativo de scripts/central-de-ajuda/trajetos/<id>.mjs,
// grava a tela do painel local via CDP (sem puppeteer/playwright — só o
// WebSocket global do Node 24 falando com um Chrome headless) e gera em
// public/central-de-ajuda/videos/:
//   <id>.mp4  — H.264, yuv420p, +faststart, sem áudio, 30 fps, 1280x800
//   <id>.vtt  — uma legenda por cena, com os tempos reais da gravação
//   <id>.jpg  — pôster (primeiro quadro do vídeo final)
//
// Login local sem expor token: o link de SSO nasce e morre dentro do
// `rails runner` (ver lib/login.mjs) — o Node nunca vê o valor.
/* eslint-disable no-console -- é uma CLI; o progresso na tela é o produto. */
/* eslint-disable no-await-in-loop -- cada cena/tentativa depende da anterior
   já ter acontecido na página; é sequencial de propósito. */

import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { abrirChromeHeadless, conectarPagina } from './lib/cdp.mjs';
import {
  injetar,
  limparDestaque,
  destacarEAcharRetangulo,
  moverCursor,
  clicar,
  digitarLinhas,
  verificarSemMarca,
  esperarTexto,
} from './lib/pagina.mjs';
import { rodarRails, criarLoginHtml, apagarLoginHtml } from './lib/login.mjs';
import {
  dimensoesImagem,
  reamostrarPara30fps,
  calcularRecorte,
  gravarSequenciaDaCena,
  codificarVideoFinal,
  gerarPoster,
  gerarVtt,
} from './lib/video.mjs';

const RAIZ_REPO = new URL('../../', import.meta.url).pathname;
const PASTA_SAIDA = join(RAIZ_REPO, 'public/central-de-ajuda/videos');
const LARGURA_CSS = 1280;
const ALTURA_CSS = 800;
const PAUSA_ANTES_MS = 1200; // "1,2 s parado antes de cada clique"
const PAUSA_DEPOIS_MS = 800; // "0,8 s parado depois do clique"

function esperar(ms) {
  return new Promise(resolve => {
    setTimeout(resolve, ms);
  });
}

async function esperarAppPronto(cliente, tentativas = 220) {
  for (let i = 0; i < tentativas; i += 1) {
    const { result } = await cliente.enviar('Runtime.evaluate', {
      expression: "!!document.querySelector('.border-t.border-n-weak button')",
      returnByValue: true,
    });
    if (result.value) return;
    await esperar(150);
  }
  throw new Error('O painel não terminou de carregar depois do login');
}

// Cada cena vira um ou mais "segmentos" de recorte — quase sempre um só,
// mas um clique que navega pra outra tela muda o que está atrás do cursor
// na pausa de depois: usar o retângulo medido ANTES do clique pra cena
// inteira arrisca recortar um pedaço do conteúdo novo que não tem nada a
// ver com o alvo (e pode expor texto que não devia aparecer). Por isso
// "mover e clicar" tenta remedir o mesmo alvo depois do clique — se ele
// ainda existir (um título de página com o mesmo texto do item de menu,
// por exemplo), o pedaço de depois do clique usa esse recorte novo; se não
// existir mais, cai de volta pro recorte de antes.
//
// A checagem de marca (verificarSemMarca) tem que rodar ENQUANTO a página
// ainda está no estado daquele segmento — se todas as checagens ficassem
// pra depois de todas as ações da cena, um segmento "de antes do clique"
// seria conferido contra a tela "de depois do clique", com coordenadas de
// uma tela checando o conteúdo de outra. Por isso cada segmento se
// registra E se confere no mesmo passo, não em lote no fim da cena.
async function registrarSegmento(cliente, segmentos, zoom, legenda, dados) {
  const recorteCss = calcularRecorte({
    retanguloCss: dados.retanguloCss,
    zoom,
    larguraPx: LARGURA_CSS,
    alturaPx: ALTURA_CSS,
    larguraCss: LARGURA_CSS,
    alturaCss: ALTURA_CSS,
  });
  await verificarSemMarca(cliente, recorteCss, legenda);
  segmentos.push(dados);
}

async function executarCena(cliente, cena, contexto) {
  const agora = () => Date.now() - contexto.tInicioGravacao;
  const tInicio = agora();
  const zoom = cena.zoom || 1;
  const segmentos = [];
  const registrar = dados =>
    registrarSegmento(cliente, segmentos, zoom, cena.legenda, dados);

  if (cena.acao === 'parar') {
    let retangulo = null;
    if (cena.alvo)
      retangulo = await destacarEAcharRetangulo(cliente, cena.alvo);
    else await limparDestaque(cliente);
    await esperar(cena.duracaoMs ?? 1200);
    await registrar({ tInicio, tFim: agora(), retanguloCss: retangulo });
  } else if (cena.acao === 'mover e clicar') {
    const retangulo = await destacarEAcharRetangulo(cliente, cena.alvo);
    await moverCursor(cliente, retangulo.centroX, retangulo.centroY);
    await esperar(cena.pausaAntesMs ?? PAUSA_ANTES_MS);
    // Confere o recorte de "antes do clique" com a página ainda no estado
    // de antes — só clica depois de aprovado.
    await registrar({ tInicio, tFim: null, retanguloCss: retangulo });
    await clicar(cliente, retangulo.centroX, retangulo.centroY);
    const tClique = agora();
    segmentos[segmentos.length - 1].tFim = tClique;

    let retanguloDepois = retangulo;
    try {
      retanguloDepois = await destacarEAcharRetangulo(cliente, cena.alvo, {
        tentativas: 20,
        intervaloMs: 150,
      });
    } catch {
      // O alvo de antes do clique não existe mais na tela nova (era um
      // item de menu, por exemplo) — mantém o recorte de antes do clique;
      // se isso deixar marca visível, a checagem abaixo derruba a gravação
      // em vez de deixar passar quieto.
    }
    await esperar(cena.pausaDepoisMs ?? PAUSA_DEPOIS_MS);
    await registrar({
      tInicio: tClique,
      tFim: agora(),
      retanguloCss: retanguloDepois,
    });
  } else if (cena.acao === 'passar o mouse') {
    const retangulo = await destacarEAcharRetangulo(cliente, cena.alvo);
    await moverCursor(cliente, retangulo.centroX, retangulo.centroY);
    await esperar(cena.duracaoMs ?? 1200);
    await registrar({ tInicio, tFim: agora(), retanguloCss: retangulo });
  } else if (cena.acao === 'digitar') {
    const retangulo = await destacarEAcharRetangulo(cliente, cena.alvo);
    await moverCursor(cliente, retangulo.centroX, retangulo.centroY);
    await clicar(cliente, retangulo.centroX, retangulo.centroY);
    await esperar(300);
    await digitarLinhas(cliente, cena.texto);
    await esperar(400);
    await registrar({ tInicio, tFim: agora(), retanguloCss: retangulo });
  } else if (cena.acao === 'ir para') {
    // Troca de rota client-side (history + popstate), não um Page.navigate:
    // um reload de página inteira reinicia a SPA e passa ~1s com a tela
    // branca do boot do Vite — nada que um usuário real veria clicando
    // dentro do próprio painel.
    await cliente.enviar('Runtime.evaluate', {
      expression: `
        history.pushState(null, '', ${JSON.stringify(cena.url)});
        window.dispatchEvent(new PopStateEvent('popstate'));
      `,
    });
    // Só corta a cena quando o conteúdo de destino já carregou de verdade —
    // sem isso o quadro pega a lista vazia com "Carregando...".
    if (cena.aguardarTexto) await esperarTexto(cliente, cena.aguardarTexto);
    await esperar(cena.duracaoMs ?? 900);
    await registrar({ tInicio, tFim: agora(), retanguloCss: null });
  } else {
    throw new Error(`Ação desconhecida no roteiro: ${cena.acao}`);
  }

  return { legenda: cena.legenda, zoom, tInicio, tFim: agora(), segmentos };
}

async function gravar(roteiro) {
  console.log(`[${roteiro.id}] preparando conta de teste…`);
  if (roteiro.preparar) await roteiro.preparar({ rodarRails });

  console.log(`[${roteiro.id}] gerando login local (sem imprimir token)…`);
  const login = await criarLoginHtml({
    contaId: roteiro.login.contaId,
    usuarioNome: roteiro.login.usuarioNome,
    baseUrl: roteiro.baseUrl,
  });

  console.log(`[${roteiro.id}] subindo Chrome headless…`);
  const chrome = await abrirChromeHeadless();
  const pastaBruta = mkdtempSync(join(tmpdir(), 'gravar-trajeto-frames-'));

  try {
    const cliente = await conectarPagina(chrome.porta);
    await cliente.enviar('Page.enable');
    await cliente.enviar('Emulation.setDeviceMetricsOverride', {
      width: LARGURA_CSS,
      height: ALTURA_CSS,
      deviceScaleFactor: 2,
      mobile: false,
    });
    // Os prints da Central são no tema claro; sem forçar isso, o Chrome
    // headless segue com o painel escuro e a tela fica irreconhecível pra
    // quem já viu os prints. O painel não guarda tema no servidor (não é
    // ui_settings) — App.vue lê localStorage["color_scheme"] (padrão "auto")
    // e cai pra prefers-color-scheme; forçamos os dois.
    await cliente.enviar('Emulation.setEmulatedMedia', {
      features: [{ name: 'prefers-color-scheme', value: 'light' }],
    });
    await cliente.enviar('Page.addScriptToEvaluateOnNewDocument', {
      source:
        "try { localStorage.setItem('color_scheme', 'light'); } catch (e) {}",
    });

    console.log(`[${roteiro.id}] entrando como ${roteiro.login.usuarioNome}…`);
    await cliente.enviar('Page.navigate', { url: login.urlFile });
    await esperarAppPronto(cliente);
    apagarLoginHtml(login.caminhoAbsoluto);
    // A barra lateral já existe no DOM nesse ponto, mas a tela ainda pode
    // estar com um spinner de carregamento por cima (dados da conta
    // chegando) — sem essa folga, o primeiro quadro gravado (o pôster) pega
    // o spinner no lugar da tela de verdade.
    await esperar(1500);

    await injetar(cliente);

    let indiceFrame = 0;
    const frames = [];
    let tInicioGravacao = null;

    cliente.em('Page.screencastFrame', async params => {
      const t = Date.now() - tInicioGravacao;
      indiceFrame += 1;
      const arquivo = join(
        pastaBruta,
        `bruto_${String(indiceFrame).padStart(6, '0')}.jpg`
      );
      writeFileSync(arquivo, Buffer.from(params.data, 'base64'));
      frames.push({ tRel: t, arquivo });
      await cliente.enviar('Page.screencastFrameAck', {
        sessionId: params.sessionId,
      });
    });

    tInicioGravacao = Date.now();
    await cliente.enviar('Page.startScreencast', {
      format: 'jpeg',
      quality: 90,
      maxWidth: LARGURA_CSS * 2,
      maxHeight: ALTURA_CSS * 2,
      everyNthFrame: 1,
    });

    console.log(`[${roteiro.id}] gravando ${roteiro.cenas.length} cenas…`);
    const contexto = { tInicioGravacao, baseUrl: roteiro.baseUrl };
    const cenasGravadas = [];
    // eslint-disable-next-line no-restricted-syntax -- sequencial de propósito
    for (const cena of roteiro.cenas) {
      const registro = await executarCena(cliente, cena, contexto);
      cenasGravadas.push(registro);
      console.log(
        `  cena "${registro.legenda}" — ${(registro.tInicio / 1000).toFixed(1)}s–${(registro.tFim / 1000).toFixed(1)}s`
      );
    }

    await esperar(200); // últimos frames a caminho
    await cliente.enviar('Page.stopScreencast');
    await esperar(150);

    if (frames.length < 2) {
      throw new Error('Poucos frames capturados — a gravação falhou');
    }

    // Os primeiros ~300-400ms de screencast do Chrome (headless, mesmo
    // depois de todo o "app pronto" + folga) vêm de um frame do compositor
    // que ainda não pegou o tema claro nem o CSS que esconde o
    // mini-profiler — sem isso, a cena de abertura (o pôster) mostra a
    // tela errada mesmo com o app já certo por trás. Descartar esses
    // primeiros frames do pool de reamostragem faz a cena de abertura
    // simplesmente segurar o primeiro frame bom até a gravação alcançar.
    const AQUECIMENTO_MS = 400;
    const framesBons = frames.filter(f => f.tRel >= AQUECIMENTO_MS);
    const framesFinal = framesBons.length ? framesBons : frames;

    return { frames: framesFinal, cenasGravadas, pastaBruta };
  } finally {
    chrome.encerrar();
    apagarLoginHtml(login.caminhoAbsoluto);
  }
}

async function montarVideo(roteiro, { frames, cenasGravadas }) {
  const duracaoTotalMs = cenasGravadas[cenasGravadas.length - 1].tFim;
  const framesReamostrados = reamostrarPara30fps(frames, duracaoTotalMs, 30);

  const { largura: larguraPx, altura: alturaPx } = await dimensoesImagem(
    frames[0].arquivo
  );

  const pastaSegmentos = mkdtempSync(
    join(tmpdir(), 'gravar-trajeto-segmentos-')
  );
  const todosSegmentos = cenasGravadas.flatMap(cena =>
    cena.segmentos.map(segmento => ({ ...segmento, zoom: cena.zoom }))
  );
  const segmentosParaFfmpeg = todosSegmentos.map((segmento, indice) => {
    const inicioFrame = Math.round((segmento.tInicio / 1000) * 30);
    const fimFrame = Math.max(
      inicioFrame + 1,
      Math.round((segmento.tFim / 1000) * 30)
    );
    const framesDoSegmento = framesReamostrados.slice(inicioFrame, fimFrame);
    const pasta = join(
      pastaSegmentos,
      `seg-${String(indice).padStart(3, '0')}`
    );
    gravarSequenciaDaCena(framesDoSegmento, pasta);

    const recorte = calcularRecorte({
      retanguloCss: segmento.retanguloCss,
      zoom: segmento.zoom,
      larguraPx,
      alturaPx,
      larguraCss: LARGURA_CSS,
      alturaCss: ALTURA_CSS,
    });
    return { pasta, recorte };
  });

  mkdirSync(PASTA_SAIDA, { recursive: true });
  const saidaMp4 = join(PASTA_SAIDA, `${roteiro.id}.mp4`);
  const saidaJpg = join(PASTA_SAIDA, `${roteiro.id}.jpg`);
  const saidaVtt = join(PASTA_SAIDA, `${roteiro.id}.vtt`);

  console.log(`[${roteiro.id}] codificando vídeo final…`);
  const resultado = await codificarVideoFinal({
    cenas: segmentosParaFfmpeg,
    saidaMp4,
  });
  await gerarPoster(saidaMp4, saidaJpg);
  gerarVtt(cenasGravadas, saidaVtt);

  rmSync(pastaSegmentos, { recursive: true, force: true });

  return {
    saidaMp4,
    saidaJpg,
    saidaVtt,
    bytes: resultado.bytes,
    duracaoTotalMs,
  };
}

async function main() {
  const id = process.argv[2];
  if (!id) {
    console.error('Uso: node scripts/central-de-ajuda/gravar-trajeto.mjs <id>');
    process.exit(1);
  }

  const modulo = await import(`./trajetos/${id}.mjs`);
  const roteiro = {
    id: modulo.id,
    login: modulo.login,
    baseUrl: modulo.baseUrl,
    preparar: modulo.preparar,
    cenas: modulo.cenas,
  };
  if (
    !roteiro.id ||
    !roteiro.login ||
    !roteiro.baseUrl ||
    !roteiro.cenas?.length
  ) {
    throw new Error(
      `Roteiro trajetos/${id}.mjs incompleto (id/login/baseUrl/cenas)`
    );
  }

  const gravado = await gravar(roteiro);
  try {
    const saida = await montarVideo(roteiro, gravado);
    console.log(`[${roteiro.id}] pronto:`);
    console.log(`  ${saida.saidaMp4}`);
    console.log(`  ${saida.saidaJpg}`);
    console.log(`  ${saida.saidaVtt}`);
    console.log(
      `  duração ${(saida.duracaoTotalMs / 1000).toFixed(1)}s, ${(saida.bytes / 1024).toFixed(0)} KB`
    );
  } finally {
    rmSync(gravado.pastaBruta, { recursive: true, force: true });
  }
}

main().catch(erro => {
  console.error(erro);
  process.exit(1);
});
