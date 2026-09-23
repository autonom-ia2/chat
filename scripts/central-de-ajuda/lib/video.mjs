// Pós-produção com ffmpeg: recorte/zoom por cena, concatenação, pôster e
// legenda .vtt. Nada de biblioteca de imagem nova — só o binário ffmpeg, que
// já é esperado no ambiente (o pedido só veta puppeteer/playwright no
// package.json).

import { spawn } from 'node:child_process';
import { mkdirSync, statSync, copyFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

function rodarFfmpeg(args) {
  return new Promise((resolve, reject) => {
    const processo = spawn('ffmpeg', [
      '-y',
      '-hide_banner',
      '-loglevel',
      'error',
      ...args,
    ]);
    let erro = '';
    processo.stderr.on('data', d => {
      erro += d.toString();
    });
    processo.on('close', codigo => {
      if (codigo === 0) resolve();
      else reject(new Error(`ffmpeg saiu com código ${codigo}:\n${erro}`));
    });
  });
}

export async function dimensoesImagem(caminho) {
  return new Promise((resolve, reject) => {
    const processo = spawn('ffprobe', [
      '-v',
      'error',
      '-select_streams',
      'v:0',
      '-show_entries',
      'stream=width,height',
      '-of',
      'csv=p=0',
      caminho,
    ]);
    let saida = '';
    processo.stdout.on('data', d => {
      saida += d.toString();
    });
    processo.on('close', codigo => {
      if (codigo !== 0)
        return reject(new Error(`ffprobe falhou em ${caminho}`));
      const [largura, altura] = saida.trim().split(',').map(Number);
      return resolve({ largura, altura });
    });
  });
}

/**
 * Escolhe, para cada frame de saída (30 fps), o frame bruto mais recente já
 * recebido do screencast até aquele instante — converte a captura de taxa
 * variável do CDP numa linha do tempo de taxa constante.
 */
export function reamostrarPara30fps(brutos, duracaoMs, fps = 30) {
  const totalFrames = Math.max(1, Math.round((duracaoMs / 1000) * fps));
  const saida = [];
  let cursor = 0;
  for (let i = 0; i < totalFrames; i += 1) {
    const tAlvo = (i * 1000) / fps;
    while (cursor < brutos.length - 1 && brutos[cursor + 1].tRel <= tAlvo) {
      cursor += 1;
    }
    saida.push(brutos[cursor]);
  }
  return saida;
}

function paraPar(n) {
  const v = Math.round(n);
  return v % 2 === 0 ? v : v - 1;
}

/**
 * Calcula o recorte (em pixels físicos do frame capturado) para uma cena,
 * a partir do retângulo do alvo medido em px CSS no momento da gravação.
 */
export function calcularRecorte({
  retanguloCss,
  zoom,
  larguraPx,
  alturaPx,
  larguraCss,
  alturaCss,
}) {
  const dprX = larguraPx / larguraCss;
  const dprY = alturaPx / alturaCss;
  const z = zoom && zoom > 1 ? zoom : 1;

  const cropWCss = larguraCss / z;
  const cropHCss = alturaCss / z;

  const centroX = retanguloCss ? retanguloCss.centroX : larguraCss / 2;
  const centroY = retanguloCss ? retanguloCss.centroY : alturaCss / 2;

  const xCss = Math.min(
    Math.max(centroX - cropWCss / 2, 0),
    larguraCss - cropWCss
  );
  const yCss = Math.min(
    Math.max(centroY - cropHCss / 2, 0),
    alturaCss - cropHCss
  );

  return {
    w: paraPar(cropWCss * dprX),
    h: paraPar(cropHCss * dprY),
    x: Math.round(xCss * dprX),
    y: Math.round(yCss * dprY),
  };
}

/**
 * Monta a sequência de arquivos de uma cena (30 fps) numa pasta própria,
 * pronta para virar um input de ffmpeg (frame_00001.jpg, frame_00002.jpg…).
 */
export function gravarSequenciaDaCena(frames, pastaSaida) {
  mkdirSync(pastaSaida, { recursive: true });
  frames.forEach((frame, indice) => {
    const destino = join(
      pastaSaida,
      `frame_${String(indice + 1).padStart(5, '0')}.jpg`
    );
    copyFileSync(frame.arquivo, destino);
  });
}

/**
 * Concatena as cenas (cada uma já como sequência de frames + seu recorte)
 * num único mp4 H.264, sem áudio, 30 fps, yuv420p, +faststart. Tenta baixar
 * o bitrate se o resultado passar do alvo de tamanho.
 */
export async function codificarVideoFinal({
  cenas,
  saidaMp4,
  fps = 30,
  alvoBytes = 2 * 1024 * 1024,
}) {
  const inputs = [];
  const filtros = [];
  cenas.forEach((cena, i) => {
    inputs.push(
      '-framerate',
      String(fps),
      '-i',
      join(cena.pasta, 'frame_%05d.jpg')
    );
    const { w, h, x, y } = cena.recorte;
    filtros.push(
      `[${i}:v]crop=${w}:${h}:${x}:${y},scale=1280:800:flags=lanczos:out_range=limited,setsar=1,format=yuv420p[v${i}]`
    );
  });
  const concat = `${cenas.map((_, i) => `[v${i}]`).join('')}concat=n=${cenas.length}:v=1:a=0[outv]`;
  const filterComplex = [...filtros, concat].join(';');

  const tentativas = [
    { crf: 26, maxrate: '700k', bufsize: '1400k' },
    { crf: 30, maxrate: '450k', bufsize: '900k' },
    { crf: 34, maxrate: '300k', bufsize: '600k' },
  ];

  // eslint-disable-next-line no-restricted-syntax
  for (const tentativa of tentativas) {
    // eslint-disable-next-line no-await-in-loop
    await rodarFfmpeg([
      ...inputs,
      '-filter_complex',
      filterComplex,
      '-map',
      '[outv]',
      '-r',
      String(fps),
      '-pix_fmt',
      'yuv420p',
      '-c:v',
      'libx264',
      '-preset',
      'medium',
      '-crf',
      String(tentativa.crf),
      '-maxrate',
      tentativa.maxrate,
      '-bufsize',
      tentativa.bufsize,
      '-movflags',
      '+faststart',
      '-an',
      saidaMp4,
    ]);
    const { size } = statSync(saidaMp4);
    if (size <= alvoBytes) return { bytes: size, crf: tentativa.crf };
  }
  const { size } = statSync(saidaMp4);
  return { bytes: size, crf: tentativas[tentativas.length - 1].crf };
}

export async function gerarPoster(mp4, posterJpg) {
  await rodarFfmpeg(['-i', mp4, '-frames:v', '1', '-q:v', '3', posterJpg]);
}

function tempoVtt(ms) {
  const totalMs = Math.max(0, Math.round(ms));
  const h = Math.floor(totalMs / 3600000);
  const m = Math.floor((totalMs % 3600000) / 60000);
  const s = Math.floor((totalMs % 60000) / 1000);
  const milis = totalMs % 1000;
  const p2 = n => String(n).padStart(2, '0');
  const p3 = n => String(n).padStart(3, '0');
  return `${p2(h)}:${p2(m)}:${p2(s)}.${p3(milis)}`;
}

export function gerarVtt(cenas, caminhoVtt) {
  const linhas = ['WEBVTT', ''];
  cenas.forEach((cena, i) => {
    linhas.push(String(i + 1));
    linhas.push(`${tempoVtt(cena.tInicio)} --> ${tempoVtt(cena.tFim)}`);
    linhas.push(cena.legenda);
    linhas.push('');
  });
  writeFileSync(caminhoVtt, linhas.join('\n'));
}
