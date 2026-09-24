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
  arrastar,
  digitarLinhas,
  limparCampo,
  definirValor,
  selecionar,
  acharOpcaoDoCombobox,
  anexarArquivo,
  verificarSemMarca,
  desfocarMarcasVisiveis,
  esperarTexto,
  esperarSemCarregando,
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
// Regra do Rodrigo: zoom > 2,5x deixa o recorte ilegível (um roteiro pediu
// 16x). O motor trava aqui, não confia no roteiro para respeitar sozinho.
const ZOOM_MAXIMO = 2.5;

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
// Retângulo que cobre dois (campo + opção escolhida), para o recorte com zoom
// mostrar os dois na cena do seletor.
function uniaoDeRetangulos(a, b) {
  const x = Math.min(a.x, b.x);
  const y = Math.min(a.y, b.y);
  const width = Math.max(a.x + a.width, b.x + b.width) - x;
  const height = Math.max(a.y + a.height, b.y + b.height) - y;
  return { x, y, width, height, centroX: x + width / 2, centroY: y + height / 2 };
}

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
  const zoomPedido = cena.zoom || 1;
  if (zoomPedido > ZOOM_MAXIMO) {
    console.warn(
      `  [aviso] cena "${cena.legenda}" pediu zoom ${zoomPedido}x — travado em ${ZOOM_MAXIMO}x (fica ilegível acima disso)`
    );
  }
  const zoom = Math.min(zoomPedido, ZOOM_MAXIMO);
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

    // Opcional: um clique que abre uma rota nunca visitada nesta gravação
    // (comum em telas com poucas visitas, ex. Vite em dev) pode demorar
    // segundos para compilar — bem mais que o retry padrão de remedição do
    // alvo logo abaixo. `aguardarTextoDepois` no roteiro espera um texto da
    // tela de destino aparecer antes de seguir, do mesmo jeito que a ação
    // "ir para" já faz com `aguardarTexto`. Sem essa chave no roteiro, o
    // comportamento é idêntico ao de antes.
    if (cena.aguardarTextoDepois) {
      // 30s de orçamento: com várias gravações rodando ao mesmo tempo (cada
      // uma com seu Chrome headless + rails runner), a CPU/rede compartilhada
      // deixa a primeira visita a uma rota nova bem mais lenta do que numa
      // sessão isolada — 15s já se mostrou curto sob essa carga.
      await esperarTexto(cliente, cena.aguardarTextoDepois, {
        tentativas: 150,
        intervaloMs: 200,
      });
    }
    // Depois de qualquer clique (pode ter trocado de tela): espera sumir
    // "Carregando..." antes de medir/registrar o depois. Sem custo quando
    // não tem nada carregando — a primeira checagem já sai negativa.
    await esperarSemCarregando(cliente);
    if (contexto.desfocarMarca) await desfocarMarcasVisiveis(cliente);

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
    // Opcional: `cena.limparAntes: true` apaga o valor padrão de um campo
    // (input/textarea) antes de digitar — ex. o nome do funil no CRM Kanban
    // já nasce preenchido. Sem essa chave, comportamento igual a sempre.
    if (cena.limparAntes) await limparCampo(cliente);
    await digitarLinhas(cliente, cena.texto);
    await esperar(400);
    await registrar({ tInicio, tFim: agora(), retanguloCss: retangulo });
  } else if (cena.acao === 'definirValor') {
    // Para campos que Input.insertText não preenche direito (ex.
    // input[type="datetime-local"|"date"|"color"|"range"]): clica no alvo
    // e escreve o valor pelo setter nativo, não por digitação simulada.
    const retangulo = await destacarEAcharRetangulo(cliente, cena.alvo);
    await moverCursor(cliente, retangulo.centroX, retangulo.centroY);
    await clicar(cliente, retangulo.centroX, retangulo.centroY);
    await esperar(200);
    await definirValor(cliente, cena.valor);
    await esperar(300);
    await registrar({ tInicio, tFim: agora(), retanguloCss: retangulo });
  } else if (cena.acao === 'selecionar') {
    // Clica no campo. No seletor do painel (combobox) a lista abre: o cursor
    // vai até a opção e clica nela, e o recorte cobre o campo e a opção. No
    // <select> nativo (fora do painel) o <option> não tem retângulo próprio:
    // escolhe por valor ou texto pelo setter, sem simular clique no <option>.
    const retangulo = await destacarEAcharRetangulo(cliente, cena.alvo);
    await moverCursor(cliente, retangulo.centroX, retangulo.centroY);
    await clicar(cliente, retangulo.centroX, retangulo.centroY);
    await esperar(200);
    const opcao = await acharOpcaoDoCombobox(cliente, cena.valor);
    if (opcao) {
      await esperar(PAUSA_DEPOIS_MS);
      await moverCursor(cliente, opcao.centroX, opcao.centroY);
      await esperar(cena.pausaAntesMs ?? PAUSA_ANTES_MS);
      await clicar(cliente, opcao.centroX, opcao.centroY);
      await esperar(PAUSA_DEPOIS_MS);
      await registrar({ tInicio, tFim: agora(), retanguloCss: uniaoDeRetangulos(retangulo, opcao) });
    } else {
      await selecionar(cliente, cena.valor);
      await esperar(300);
      await registrar({ tInicio, tFim: agora(), retanguloCss: retangulo });
    }
  } else if (cena.acao === 'anexarArquivo') {
    // cena.alvo é o botão/label VISÍVEL que abre o seletor de arquivo (é
    // nele que o cursor e o destaque aparecem); cena.seletorArquivo é o
    // seletor CSS do <input type="file"> de verdade, que pode estar
    // escondido — anexarArquivo() usa DOM.setFileInputFiles nele, não um
    // clique simulado.
    const retangulo = await destacarEAcharRetangulo(cliente, cena.alvo);
    await moverCursor(cliente, retangulo.centroX, retangulo.centroY);
    await esperar(cena.pausaAntesMs ?? PAUSA_ANTES_MS);
    await anexarArquivo(cliente, cena.seletorArquivo, cena.arquivo);
    await esperar(cena.pausaDepoisMs ?? PAUSA_DEPOIS_MS);
    await registrar({ tInicio, tFim: agora(), retanguloCss: retangulo });
  } else if (cena.acao === 'arrastar') {
    // Move um card entre colunas do Kanban (vuedraggable/sortable.js):
    // pressiona no alvo, arrasta até `cena.destino` (mesma forma de um
    // alvo) e solta lá. Registra dois segmentos, como "mover e clicar" —
    // um de antes do arrasto (alvo de origem) e um de depois (destino).
    const origem = await destacarEAcharRetangulo(cliente, cena.alvo);
    await moverCursor(cliente, origem.centroX, origem.centroY);
    await esperar(cena.pausaAntesMs ?? PAUSA_ANTES_MS);
    await registrar({ tInicio, tFim: null, retanguloCss: origem });

    const destino = await destacarEAcharRetangulo(cliente, cena.destino);
    const tSolta = agora();
    segmentos[segmentos.length - 1].tFim = tSolta;
    await arrastar(
      cliente,
      origem.centroX,
      origem.centroY,
      destino.centroX,
      destino.centroY,
      cena.duracaoArrastoMs ?? 900
    );
    await esperar(cena.pausaDepoisMs ?? PAUSA_DEPOIS_MS);
    await registrar({ tInicio: tSolta, tFim: agora(), retanguloCss: destino });
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
    // Mesmo orçamento de 30s de aguardarTextoDepois, pelo mesmo motivo
    // (várias gravações competindo por CPU ao mesmo tempo).
    if (cena.aguardarTexto) {
      await esperarTexto(cliente, cena.aguardarTexto, {
        tentativas: 150,
        intervaloMs: 200,
      });
    }
    await esperarSemCarregando(cliente);
    if (contexto.desfocarMarca) await desfocarMarcasVisiveis(cliente);
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

  console.log(`[${roteiro.id}] subindo Chrome headless…`);
  const chrome = await abrirChromeHeadless();
  const pastaBruta = mkdtempSync(join(tmpdir(), 'gravar-trajeto-frames-'));
  // O html de login nasce dentro do try: qualquer falha daqui em diante passa pelo
  // finally, e o link de uso único nunca fica esquecido em public/.
  let login;

  try {
    console.log(`[${roteiro.id}] gerando login local (sem imprimir token)…`);
    login = await criarLoginHtml({
      contaId: roteiro.login.contaId,
      usuarioNome: roteiro.login.usuarioNome,
      baseUrl: roteiro.baseUrl,
    });

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
    // Mesma ideia, mas para qualquer texto "Carregando..." que ainda esteja
    // visível (ex. "Carregando dados do gráfico…") — a folga fixa acima não
    // garante isso; essa checagem sim. Orçamento bem maior que o padrão
    // (30s, não 10s) só aqui: é o único lugar em que esperar mais NÃO
    // alonga o vídeo — a gravação ainda nem começou, então cada segundo
    // gasto aqui é um segundo a mais de garantia pro pôster, não um
    // segundo a mais de vídeo. Telas de relatório com gráfico (dado real
    // buscado à parte, não só o boot da SPA) podem passar dos 10s
    // (confirmado no 14.03: o pôster saía preso em "Carregando dados do
    // gráfico…" mesmo já capturando o fim da 1ª cena, porque a página só
    // termina de carregar depois disso).
    await esperarSemCarregando(cliente, { tentativas: 150, intervaloMs: 200 });

    await injetar(cliente);
    // Desfoca marca que esteja colada no próprio texto do pôster (o
    // primeiro quadro do vídeo) — `export const desfocarMarca = false` no
    // roteiro desliga isso, se algum dia precisar.
    if (roteiro.desfocarMarca !== false) await desfocarMarcasVisiveis(cliente);

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
    const contexto = {
      tInicioGravacao,
      baseUrl: roteiro.baseUrl,
      desfocarMarca: roteiro.desfocarMarca !== false,
    };
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
    if (login) apagarLoginHtml(login.caminhoAbsoluto);
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
  // Capa = fim da cena de abertura, 0,1s antes da legenda trocar: a tela já
  // carregou (spinner/"Carregando..." sumiram) e ainda é o ponto de
  // partida do vídeo, não o meio de uma ação.
  // Capa = fim do vídeo (a cena "Pronto", com o resultado na tela): mostra aonde o vídeo
  // leva. O começo é quase sempre a mesma tela depois do login e deixava as capas iguais.
  const tempoCapaSegundos = Math.max(
    0,
    (cenasGravadas.at(-1).tFim - 200) / 1000
  );
  await gerarPoster(saidaMp4, saidaJpg, tempoCapaSegundos);
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
    // Opcional: `export const desfocarMarca = false` desliga o desfoque
    // automático de marca (ligado por padrão em todo roteiro).
    desfocarMarca: modulo.desfocarMarca,
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
